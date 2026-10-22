# Kitatool — gaming speed test

Live at **https://kitatool.com**. A static web app (HTML, CSS, JavaScript — no build step) that tests:

- Download and upload speed (Cloudflare's network, parallel streams)
- Ping, jitter and estimated packet loss
- Lag under load (ping while downloading / uploading) with a gaming score from A+ to F
- "Ready for" checks for shooters, football online, battle royale, cloud gaming, streaming and voice chat
- Ping to game-server regions (London, Frankfurt, Ireland, Paris, Cape Town, Bahrain, US East)
- Live Ping monitor and local test history

Hosted on GitHub Pages; the `CNAME` file points it at kitatool.com.

## Save — video and photo downloader

**https://kitatool.com/save.html** — paste a TikTok, Instagram, X, Facebook or Pinterest link and save the video, the sound, or every photo in a slideshow or carousel. TikTok videos come without the watermark. On Android, installing Kitatool from the browser menu adds it to the share sheet, so you can share a post straight to it.

The page is static, but downloading needs a small server, which lives in `server/`. It's Python with [yt-dlp](https://github.com/yt-dlp/yt-dlp) and ffmpeg, and it updates yt-dlp itself every 12 hours.

### Deploy the server (free, on Render)

1. Sign in at [render.com](https://render.com) with GitHub.
2. **New → Blueprint**, pick this repo. Render reads `render.yaml` and creates the `kitatool-save` service.
3. When it's live, open `https://kitatool-save.onrender.com/api/health`. It should show `{"ok": true, ...}`.
4. If Render gave the service a different address, change `window.KITA_SAVE_API` near the bottom of `save.html`.

Settings (Render → service → Environment):

| Variable | What it does |
|---|---|
| `ALLOWED_ORIGINS` | Sites allowed to call the server (default: kitatool.com) |
| `IG_COOKIES` | Optional. Instagram cookies in Netscape format, from a spare account, if Instagram starts asking for a login |

The free plan sleeps after 15 minutes without use, so the first request after that takes up to a minute. The page tells the user while it wakes.

Nothing is stored: files go to a temp folder and are deleted after sending, and logs never include the links. Please only save content you own or have permission to use.

## Light Dey? — live NEPA tracker

**https://kitatool.com/nepa.html** — pick your state, LGA and area, then tap **Light don come** or **Light don go**. Everyone sees which areas have light right now, how long it's been on or off, and hours of light today and this week. Home inverters running the [Lumen Power](https://github.com/Droidkay) app can report automatically, and those reports count more than taps.

It runs on a free [Supabase](https://supabase.com) database. People can't read or write the tables directly; the page only calls four functions, which check every report:

- a phone can report for at most 3 areas a day and 30 times an hour, and one network at most 120 times an hour
- repeating the same answer within 10 minutes is ignored
- reports older than 30 days are deleted

### Set up the database (once, about 5 minutes)

1. Create a free project at [supabase.com](https://supabase.com). Region: pick the closest (e.g. West EU).
2. Open **SQL Editor → New query**, paste all of `nepa/schema.sql`, and tap **Run**.
3. New query again: paste all of `nepa/lgas.sql` (the 774 LGAs), and **Run**.
4. Go to **Project Settings → API**. Copy the **Project URL** and the **anon public** key into `nepa/config.json`:
   ```json
   { "url": "https://xxxx.supabase.co", "key": "eyJ..." }
   ```
   The anon key is meant to be public; the functions above are the only thing it can use.
5. Commit and push. The page and the Lumen Power app both read this file.
