-- Kitatool "Light dey?" — shared NEPA tracker.
-- Paste this whole file into Supabase → SQL Editor → Run. Safe to run again.
--
-- Nobody can read or write the tables directly. The web page and the Lumen Power app
-- only call the functions at the bottom, which check and rate-limit every report.

-- ------------------------------------------------------------------ tables
create table if not exists public.nepa_lgas (
  state text not null,
  lga   text not null,
  primary key (state, lga)
);

create table if not exists public.nepa_reports (
  id         bigint generated always as identity primary key,
  area       text not null,                 -- 'oyo|ibadan-north|bodija'
  state      text not null,
  lga        text not null,
  hood       text not null,                 -- neighbourhood as typed, tidied
  status     boolean not null,              -- true = light dey
  source     text not null default 'tap' check (source in ('tap', 'inverter')),
  device     text not null,                 -- random id made on the phone, not personal
  ip_hash    text,
  created_at timestamptz not null default now()
);
create index if not exists nepa_reports_area_time on public.nepa_reports (area, created_at desc);
create index if not exists nepa_reports_time      on public.nepa_reports (created_at desc);
create index if not exists nepa_reports_device    on public.nepa_reports (device, created_at desc);
create index if not exists nepa_reports_ip        on public.nepa_reports (ip_hash, created_at desc);

alter table public.nepa_lgas    enable row level security;
alter table public.nepa_reports enable row level security;
revoke all on public.nepa_lgas, public.nepa_reports from anon, authenticated;

-- ------------------------------------------------------------------ helpers (not callable from outside)
create or replace function public.nepa_slug(t text) returns text
language sql immutable as $$
  select trim(both '-' from regexp_replace(lower(coalesce(t, '')), '[^a-z0-9]+', '-', 'g'))
$$;

-- Minutes of light in [p_from, p_to) for an area, from the run of reports.
-- Each report holds until the next one. The state before p_from comes from the last
-- report in the 12 hours before it. Gaps of more than 8 hours with no report count as unknown.
create or replace function public.nepa_on_minutes(p_area text, p_from timestamptz, p_to timestamptz)
returns int language sql stable as $$
  with pts as (
    (select created_at as t, status from public.nepa_reports
      where area = p_area and created_at < p_from and created_at >= p_from - interval '12 hours'
      order by created_at desc limit 1)
    union all
    select created_at, status from public.nepa_reports
      where area = p_area and created_at >= p_from and created_at < p_to
  ), seg as (
    select greatest(t, p_from) as a,
           least(coalesce(lead(t) over (order by t), least(p_to, now())), p_to, t + interval '8 hours') as b,
           status
    from pts
  )
  select coalesce(round(sum(extract(epoch from (b - a))) / 60)::int, 0)
  from seg where status and b > a
$$;

-- Current status of one area as JSON.
create or replace function public.nepa_area_json(p_area text)
returns json language plpgsql stable as $$
declare
  r record;
  w_on numeric := 0; w_off numeric := 0;
  v_status text := 'unknown'; v_since timestamptz; v_stale boolean := false;
  v_reporters int := 0; v_last record; v_today date := (now() at time zone 'Africa/Lagos')::date;
  v_mid timestamptz := (v_today::timestamp at time zone 'Africa/Lagos');
  v_days json;
begin
  -- Fresh votes: the latest report from each phone in the last 45 minutes.
  -- An inverter counts as 3 votes, a tap as 1, and newer votes count a bit more.
  for r in
    select distinct on (device) device, status, source, created_at
    from public.nepa_reports
    where area = p_area and created_at > now() - interval '45 minutes'
    order by device, created_at desc
  loop
    v_reporters := v_reporters + 1;
    if r.status then
      w_on := w_on + (case when r.source = 'inverter' then 3 else 1 end) * (1 + extract(epoch from (r.created_at - now() + interval '45 minutes')) / 2700);
    else
      w_off := w_off + (case when r.source = 'inverter' then 3 else 1 end) * (1 + extract(epoch from (r.created_at - now() + interval '45 minutes')) / 2700);
    end if;
  end loop;

  select status, created_at, hood, lga, state into v_last
  from public.nepa_reports where area = p_area order by created_at desc limit 1;
  if v_last is null then
    return json_build_object('area', p_area, 'status', 'unknown');
  end if;

  if v_reporters > 0 then
    v_status := case when w_on > w_off then 'on' when w_off > w_on then 'off'
                     when v_last.status then 'on' else 'off' end;
  elsif v_last.created_at > now() - interval '24 hours' then
    v_status := case when v_last.status then 'on' else 'off' end;
    v_stale := true;
  end if;

  if v_status <> 'unknown' then
    -- Since: first report of the current state after the last report of the other state.
    select min(created_at) into v_since from public.nepa_reports
    where area = p_area and status = (v_status = 'on')
      and created_at > coalesce((select max(created_at) from public.nepa_reports
                                 where area = p_area and status = (v_status <> 'on')
                                   and created_at > now() - interval '7 days'), now() - interval '7 days');
  end if;

  select json_agg(json_build_object('day', d::date, 'on_min',
           public.nepa_on_minutes(p_area, (d at time zone 'Africa/Lagos'),
                                  ((d + interval '1 day') at time zone 'Africa/Lagos'))) order by d)
    into v_days
  from generate_series((v_today - 6)::timestamp, v_today::timestamp, interval '1 day') as d;

  return json_build_object(
    'area', p_area, 'state', v_last.state, 'lga', v_last.lga, 'hood', v_last.hood,
    'status', v_status, 'since', v_since, 'stale', v_stale, 'reporters', v_reporters,
    'last_at', v_last.created_at,
    'on_today_min', public.nepa_on_minutes(p_area, v_mid, now()),
    'today_min', round(extract(epoch from (now() - v_mid)) / 60)::int,
    'on_24h_min', public.nepa_on_minutes(p_area, now() - interval '24 hours', now()),
    'week', v_days);
end $$;

-- ------------------------------------------------------------------ public functions
-- Report light on/off for an area. Returns the area's new status.
create or replace function public.nepa_report(
  p_state text, p_lga text, p_hood text, p_status boolean,
  p_device text, p_source text default 'tap')
returns json language plpgsql security definer set search_path = public as $$
declare
  v_hood text; v_area text; v_ip text; v_ip_hash text; v_last record; v_n int;
begin
  if not exists (select 1 from nepa_lgas where state = p_state and lga = p_lga) then
    raise exception 'Pick your state and LGA from the list' using errcode = '22023';
  end if;
  v_hood := initcap(regexp_replace(trim(regexp_replace(coalesce(p_hood, ''), '[^[:alnum:] ''.&/-]+', ' ', 'g')), '\s+', ' ', 'g'));
  if length(v_hood) < 2 or length(v_hood) > 40 then
    raise exception 'Type your area or street name (2 to 40 letters)' using errcode = '22023';
  end if;
  if p_device is null or p_device !~ '^[A-Za-z0-9_-]{12,64}$' then
    raise exception 'Bad device id' using errcode = '22023';
  end if;
  if p_source not in ('tap', 'inverter') then
    raise exception 'Bad source' using errcode = '22023';
  end if;
  v_area := nepa_slug(p_state) || '|' || nepa_slug(p_lga) || '|' || nepa_slug(v_hood);

  begin
    v_ip := split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1);
  exception when others then v_ip := '';
  end;
  v_ip_hash := case when v_ip = '' then null else md5('kitatool-nepa:' || trim(v_ip)) end;

  -- Same phone, same area: a repeat of the same answer within 10 minutes is ignored,
  -- and a change of answer needs 30 seconds since the last one.
  select status, created_at into v_last from nepa_reports
  where device = p_device and area = v_area order by created_at desc limit 1;
  if v_last is not null then
    if v_last.status = p_status and v_last.created_at > now() - interval '10 minutes' then
      return nepa_area_json(v_area);
    end if;
    if v_last.created_at > now() - interval '30 seconds' then
      raise exception 'Easy! Wait a few seconds and try again' using errcode = 'P0001';
    end if;
  end if;

  -- A phone can report for at most 3 areas a day, and 30 times an hour.
  select count(distinct area) into v_n from nepa_reports
  where device = p_device and created_at > now() - interval '24 hours' and area <> v_area;
  if v_n >= 3 then
    raise exception 'You can only report for 3 areas a day' using errcode = 'P0001';
  end if;
  select count(*) into v_n from nepa_reports where device = p_device and created_at > now() - interval '1 hour';
  if v_n >= 30 then
    raise exception 'Too many reports. Try again later' using errcode = 'P0001';
  end if;
  if v_ip_hash is not null then
    select count(*) into v_n from nepa_reports where ip_hash = v_ip_hash and created_at > now() - interval '1 hour';
    if v_n >= 120 then
      raise exception 'Too many reports from this network. Try again later' using errcode = 'P0001';
    end if;
  end if;

  insert into nepa_reports (area, state, lga, hood, status, source, device, ip_hash)
  values (v_area, p_state, p_lga, v_hood, p_status, p_source, p_device, v_ip_hash);

  -- Keep the table small: drop reports older than 30 days now and then.
  if random() < 0.02 then
    delete from nepa_reports where created_at < now() - interval '30 days';
  end if;

  return nepa_area_json(v_area);
end $$;

-- One area's status, by state + LGA + area name.
create or replace function public.nepa_status(p_state text, p_lga text, p_hood text)
returns json language sql stable security definer set search_path = public as $$
  select nepa_area_json(nepa_slug(p_state) || '|' || nepa_slug(p_lga) || '|' || nepa_slug(p_hood))
$$;

-- Areas with reports in the last 24 hours, newest first. Optional state filter.
create or replace function public.nepa_board(p_state text default null, p_limit int default 60)
returns json language sql stable security definer set search_path = public as $$
  with areas as (
    select area, max(created_at) as last_at from nepa_reports
    where created_at > now() - interval '24 hours'
      and (p_state is null or state = p_state)
    group by area order by last_at desc limit least(greatest(coalesce(p_limit, 60), 1), 200)
  ), rows as (
    select nepa_area_json(area)::jsonb as j, last_at from areas
  )
  select json_build_object(
    'areas', coalesce(json_agg((j - 'week') order by last_at desc), '[]'::json),
    'on',  count(*) filter (where j ->> 'status' = 'on'),
    'off', count(*) filter (where j ->> 'status' = 'off'),
    'reports_24h', (select count(*) from nepa_reports where created_at > now() - interval '24 hours'
                      and (p_state is null or state = p_state)),
    'at', now())
  from rows
$$;

-- Area names people have used in an LGA, for the suggestions list.
create or replace function public.nepa_hoods(p_state text, p_lga text)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(hood order by n desc), '[]'::json) from (
    select hood, count(*) as n from nepa_reports
    where state = p_state and lga = p_lga and created_at > now() - interval '30 days'
    group by hood order by n desc limit 40) x
$$;

revoke execute on function public.nepa_slug(text), public.nepa_on_minutes(text, timestamptz, timestamptz),
  public.nepa_area_json(text) from public, anon, authenticated;
grant execute on function public.nepa_report(text, text, text, boolean, text, text),
  public.nepa_status(text, text, text), public.nepa_board(text, int), public.nepa_hoods(text, text)
  to anon, authenticated;
