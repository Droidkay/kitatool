"""
Kitatool Save: a small download server for kitatool.com/save.

Paste a TikTok, Instagram, X, Facebook or Pinterest link; the page asks this server what's in the
post (/api/info) and then downloads the chosen video or image through it (/api/file).

The work is done by yt-dlp (https://github.com/yt-dlp/yt-dlp), which this server keeps up to date
by itself. Only standard-library Python besides yt-dlp; ffmpeg is used for merging when needed.

Environment variables (all optional):
  ALLOWED_ORIGINS   comma-separated sites allowed to call the API (default: kitatool.com + localhost)
  IG_COOKIES        Netscape-format cookies for an Instagram account, for posts that need a login
  PORT              port to listen on (Render sets this)
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "8080"))
ALLOWED_ORIGINS = [o.strip() for o in os.environ.get(
    "ALLOWED_ORIGINS", "https://kitatool.com,https://www.kitatool.com,http://localhost:8000,http://127.0.0.1:8000"
).split(",") if o.strip()]

MAX_BYTES = 400 * 1024 * 1024        # never serve files bigger than this
INFO_TIMEOUT = 60                    # seconds for yt-dlp to inspect a post
DOWNLOAD_TIMEOUT = 240               # seconds for a download
RATE_LIMIT = (40, 600)               # 40 requests per 10 minutes per visitor
UA = ("Mozilla/5.0 (Linux; Android 14; SM-F946B) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36")

# Which links we accept. Anything else is refused, so the server can't be used as an open proxy.
PLATFORMS = [
    ("tiktok", re.compile(r"^(?:[\w-]+\.)?(?:tiktok\.com|tiktokv\.com)$")),
    ("instagram", re.compile(r"^(?:[\w-]+\.)?(?:instagram\.com|instagr\.am)$")),
    ("x", re.compile(r"^(?:[\w-]+\.)?(?:x\.com|twitter\.com)$")),
    ("facebook", re.compile(r"^(?:[\w-]+\.)?(?:facebook\.com|fb\.watch|fb\.com)$")),
    ("pinterest", re.compile(r"^(?:[\w-]+\.)?(?:pinterest\.[a-z.]+|pin\.it)$")),
]
# Image CDNs we may fetch for photo posts.
IMAGE_HOSTS = re.compile(
    r"(?:^|\.)(?:cdninstagram\.com|fbcdn\.net|tiktokcdn(?:-[a-z]+)?\.com|tiktokcdn\.com|ibyteimg\.com|"
    r"muscdn\.com|twimg\.com|pinimg\.com)$")


def platform_of(url):
    try:
        u = urllib.parse.urlparse(url)
    except Exception:
        return None
    if u.scheme not in ("http", "https") or not u.hostname:
        return None
    host = u.hostname.lower()
    for name, rx in PLATFORMS:
        if rx.match(host):
            return name
    return None


# ------------------------------------------------------------------ yt-dlp helpers

def cookies_args(platform):
    """Optional Instagram cookies (from the IG_COOKIES variable) for posts that need a login."""
    raw = os.environ.get("IG_COOKIES", "").strip()
    if platform != "instagram" or not raw:
        return []
    path = os.path.join(tempfile.gettempdir(), "ig_cookies.txt")
    if not os.path.exists(path):
        with open(path, "w") as f:
            f.write(raw.replace("\\n", "\n") + "\n")
    return ["--cookies", path]


def ytdlp(args, timeout):
    cmd = [sys.executable, "-m", "yt_dlp", "--no-warnings", "--user-agent", UA] + args
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return p.returncode, p.stdout, p.stderr


def ytdlp_version():
    try:
        return subprocess.run([sys.executable, "-m", "yt_dlp", "--version"], capture_output=True, text=True,
                              timeout=20).stdout.strip()
    except Exception:
        return "unknown"


def friendly_error(stderr, platform):
    s = (stderr or "").lower()
    if "login" in s or "rate-limit" in s or "cookies" in s:
        if platform == "instagram":
            return "Instagram wants a login for this post. It may be private, or Instagram is limiting the server."
        return "This post needs a login to view."
    if "private" in s:
        return "This post is private."
    if "unsupported url" in s:
        return "That link isn't a post we can read. Copy the link from the post's Share button."
    if "not available" in s or "404" in s or "removed" in s:
        return "This post isn't available any more."
    if "no video" in s:
        return "NO_VIDEO"
    return "Couldn't read that post. Try again in a moment."


def pick_video_formats(info):
    """Video choices for one post: best with sound, preferring no watermark (TikTok)."""
    fmts = info.get("formats") or []
    out = []
    progressive = [f for f in fmts if f.get("vcodec") not in (None, "none") and f.get("acodec") not in (None, "none")]
    clean = [f for f in progressive if "watermark" not in (f.get("format_note") or "").lower()
             and "watermark" not in (f.get("format_id") or "").lower()]
    pool = clean or progressive
    if pool:
        best = max(pool, key=lambda f: ((f.get("height") or 0), (f.get("tbr") or 0)))
        out.append({"kind": "video", "fmt": best.get("format_id"), "height": best.get("height"),
                    "label": f"Video{(' · ' + str(best['height']) + 'p') if best.get('height') else ''}",
                    "ext": "mp4"})
    elif any(f.get("vcodec") not in (None, "none") for f in fmts):
        # video and sound are separate (common on Instagram/X): let yt-dlp merge them
        h = max((f.get("height") or 0) for f in fmts if f.get("vcodec") not in (None, "none"))
        out.append({"kind": "video", "fmt": "bv*+ba/b", "height": h or None,
                    "label": f"Video{(' · ' + str(h) + 'p') if h else ''}", "ext": "mp4"})
    if any(f.get("acodec") not in (None, "none") for f in fmts):
        out.append({"kind": "audio", "fmt": "ba/b", "label": "Sound only", "ext": "m4a"})
    return out


def image_urls(info):
    """Photo posts: image addresses yt-dlp exposes (thumbnails of image-only entries)."""
    urls = []
    for t in info.get("thumbnails") or []:
        u = t.get("url")
        if u and IMAGE_HOSTS.search(urllib.parse.urlparse(u).hostname or ""):
            urls.append((t.get("width") or 0, u))
    urls.sort(reverse=True)
    return [urls[0][1]] if urls else []


# ------------------------------------------------------------------ fallbacks for photo posts

def http_get(url, headers=None, limit=4_000_000):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "en-US,en;q=0.9", **(headers or {})})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read(limit).decode("utf-8", "replace"), r.geturl()


def tiktok_photos(url):
    """TikTok photo (slideshow) posts: read the image list from the page data."""
    html, final = http_get(url)
    m = re.search(r'<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>(.*?)</script>', html, re.S)
    if not m:
        return None
    data = json.loads(m.group(1))
    item = (data.get("__DEFAULT_SCOPE__", {}).get("webapp.video-detail", {}).get("itemInfo", {}).get("itemStruct", {}))
    images = (item.get("imagePost") or {}).get("images") or []
    urls = []
    for img in images:
        lst = (img.get("imageURL") or {}).get("urlList") or []
        if lst:
            urls.append(lst[0])
    if not urls:
        return None
    author = (item.get("author") or {}).get("uniqueId") or ""
    return {"title": item.get("desc") or "TikTok photos", "author": author, "thumbnail": urls[0], "images": urls}


def instagram_photos(url):
    """Public Instagram photo posts: the embed page carries the full-size image without a login."""
    m = re.search(r"instagram\.com/(?:[\w.]+/)?(?:p|reel|reels|tv)/([\w-]+)", url)
    if not m:
        return None
    code = m.group(1)
    html, _ = http_get(f"https://www.instagram.com/p/{code}/embed/captioned/")
    found = []
    for u in re.findall(r'"display_url"\s*:\s*"([^"]+)"', html):
        found.append(u.encode().decode("unicode_escape").replace("\\/", "/"))
    if not found:
        for u in re.findall(r'class="EmbeddedMediaImage"[^>]*src="([^"]+)"', html):
            found.append(u.replace("&amp;", "&"))
    seen, urls = set(), []
    for u in found:
        key = u.split("?")[0]
        if key not in seen:
            seen.add(key)
            urls.append(u)
    if not urls:
        return None
    a = re.search(r'class="UsernameText"[^>]*>([^<]+)<', html)
    return {"title": "Instagram post", "author": a.group(1) if a else "", "thumbnail": urls[0], "images": urls}


# ------------------------------------------------------------------ the two API calls

def get_info(url):
    platform = platform_of(url)
    if not platform:
        return 400, {"error": "Paste a TikTok, Instagram, X, Facebook or Pinterest link."}

    code, out, err = ytdlp(["-J"] + cookies_args(platform) + [url], INFO_TIMEOUT)
    items, title, author, thumb, duration = [], "", "", "", None
    if code == 0 and out.strip():
        info = json.loads(out)
        title = info.get("title") or info.get("description") or ""
        author = info.get("uploader") or info.get("channel") or info.get("uploader_id") or ""
        thumb = info.get("thumbnail") or ""
        duration = info.get("duration")
        entries = info.get("entries") if info.get("_type") == "playlist" else None
        if entries:  # carousels and multi-video posts
            for i, e in enumerate(entries, start=1):
                if not e:
                    continue
                vids = pick_video_formats(e)
                if vids:
                    v = vids[0]
                    items.append({**v, "index": i, "label": f"#{i} · {v['label']}", "thumb": e.get("thumbnail")})
                else:
                    for u in image_urls(e):
                        items.append({"kind": "image", "src": u, "index": i, "label": f"#{i} · Photo", "ext": "jpg", "thumb": u})
            if not thumb and entries and entries[0]:
                thumb = entries[0].get("thumbnail") or ""
        else:
            items = pick_video_formats(info)
    else:
        reason = friendly_error(err, platform)
        if reason != "NO_VIDEO" and platform not in ("tiktok", "instagram"):
            return 422, {"error": reason}

    # Photo posts yt-dlp doesn't download: try the platform's own page data.
    if not any(i["kind"] in ("video", "image") for i in items) and platform in ("tiktok", "instagram"):
        try:
            p = tiktok_photos(url) if platform == "tiktok" else instagram_photos(url)
        except Exception:
            p = None
        if p:
            title = title or p["title"]
            author = author or p["author"]
            thumb = thumb or p["thumbnail"]
            items = [{"kind": "image", "src": u, "index": i, "label": f"Photo {i}" if len(p["images"]) > 1 else "Photo",
                      "ext": "jpg", "thumb": u} for i, u in enumerate(p["images"], start=1)]
        elif code != 0:
            return 422, {"error": friendly_error(err, platform).replace("NO_VIDEO", "Couldn't find any video or photos in that post.")}

    if not items:
        return 422, {"error": "Couldn't find any video or photos in that post."}

    base = re.sub(r"[^\w\- ]+", "", f"{platform} {author}".strip())[:60].strip().replace(" ", "_") or platform
    for it in items:
        name = f"{base}_{it.get('index', 1)}.{it['ext']}" if len(items) > 1 else f"{base}.{it['ext']}"
        if it["kind"] == "image":
            it["file"] = "/api/file?" + urllib.parse.urlencode({"img": it.pop("src"), "name": name})
        else:
            q = {"url": url, "fmt": it.pop("fmt"), "kind": it["kind"], "name": name}
            if it.get("index"):
                q["i"] = it["index"]
            it["file"] = "/api/file?" + urllib.parse.urlencode(q)
    return 200, {"platform": platform, "title": title[:300], "author": author, "thumbnail": thumb,
                 "duration": duration, "items": items}


def safe_name(name, ext):
    n = re.sub(r"[^\w\-.]+", "_", name or "")[:90].strip("._") or "kitatool"
    return n if n.lower().endswith("." + ext) else f"{n}.{ext}"


# ------------------------------------------------------------------ HTTP server

_hits = {}
_hits_lock = threading.Lock()


def allowed(ip):
    now = time.time()
    n, window = RATE_LIMIT
    with _hits_lock:
        q = [t for t in _hits.get(ip, []) if now - t < window]
        if len(q) >= n:
            _hits[ip] = q
            return False
        q.append(now)
        _hits[ip] = q
        return True


class Handler(BaseHTTPRequestHandler):
    server_version = "KitatoolSave/1.0"

    def log_message(self, fmt, *args):  # keep logs short, never log full links
        sys.stderr.write("%s %s\n" % (self.command, self.path.split("?")[0]))

    def cors(self):
        origin = self.headers.get("Origin", "")
        if origin in ALLOWED_ORIGINS or "*" in ALLOWED_ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin or "*")
            self.send_header("Vary", "Origin")
            self.send_header("Access-Control-Expose-Headers", "Content-Disposition, Content-Length")

    def send_json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.cors()
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def client_ip(self):
        return (self.headers.get("X-Forwarded-For", "").split(",")[0].strip() or self.client_address[0])

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query).items()}
        try:
            if u.path in ("/", "/api/health"):
                return self.send_json(200, {"ok": True, "ytdlp": YTDLP_VERSION[0]})
            if not allowed(self.client_ip()):
                return self.send_json(429, {"error": "Too many requests. Wait a few minutes and try again."})
            if u.path == "/api/info":
                code, obj = get_info(q.get("url", "").strip())
                return self.send_json(code, obj)
            if u.path == "/api/file":
                return self.serve_file(q)
            return self.send_json(404, {"error": "Not found"})
        except subprocess.TimeoutExpired:
            return self.send_json(504, {"error": "That took too long. Try again."})
        except (BrokenPipeError, ConnectionResetError):
            return None
        except Exception as e:  # noqa: BLE001
            sys.stderr.write(f"error: {type(e).__name__}: {e}\n")
            return self.send_json(500, {"error": "Something went wrong on the server."})

    def serve_file(self, q):
        if q.get("img"):
            src = q["img"]
            host = urllib.parse.urlparse(src).hostname or ""
            if not IMAGE_HOSTS.search(host):
                return self.send_json(400, {"error": "Not allowed."})
            req = urllib.request.Request(src, headers={"User-Agent": UA, "Referer": "https://www.instagram.com/"
                                                       if "instagram" in host or "fbcdn" in host else "https://www.tiktok.com/"})
            with urllib.request.urlopen(req, timeout=30) as r:
                ctype = r.headers.get("Content-Type", "image/jpeg")
                ext = "png" if "png" in ctype else "webp" if "webp" in ctype else "jpg"
                data = r.read(MAX_BYTES + 1)
            if len(data) > MAX_BYTES:
                return self.send_json(413, {"error": "File too large."})
            return self.send_bytes(data, ctype, safe_name(q.get("name"), ext))

        url = q.get("url", "")
        platform = platform_of(url)
        if not platform:
            return self.send_json(400, {"error": "Not allowed."})
        kind = q.get("kind", "video")
        fmt = q.get("fmt") or ("ba/b" if kind == "audio" else "bv*+ba/b")
        if not re.fullmatch(r"[\w.+/*\-\[\]=<>!:,]+", fmt):
            return self.send_json(400, {"error": "Bad format."})
        tmp = tempfile.mkdtemp(prefix="kt_")
        try:
            args = ["-f", fmt, "--max-filesize", str(MAX_BYTES), "-o", os.path.join(tmp, "out.%(ext)s"),
                    "--no-part", "--restrict-filenames"]
            if kind == "video":
                args += ["--merge-output-format", "mp4"]
            if q.get("i"):
                args += ["--playlist-items", str(int(q["i"]))]
            code, _, err = ytdlp(args + cookies_args(platform) + [url], DOWNLOAD_TIMEOUT)
            files = [f for f in os.listdir(tmp) if not f.endswith((".part", ".ytdl"))]
            if code != 0 or not files:
                return self.send_json(422, {"error": friendly_error(err, platform).replace("NO_VIDEO", "No video in this post.")})
            path = os.path.join(tmp, max(files, key=lambda f: os.path.getsize(os.path.join(tmp, f))))
            ext = path.rsplit(".", 1)[-1].lower()
            ctype = {"mp4": "video/mp4", "m4a": "audio/mp4", "mp3": "audio/mpeg", "webm": "video/webm",
                     "jpg": "image/jpeg", "png": "image/png"}.get(ext, "application/octet-stream")
            size = os.path.getsize(path)
            self.send_response(200)
            self.cors()
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(size))
            self.send_header("Content-Disposition", f'attachment; filename="{safe_name(q.get("name"), ext)}"')
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            with open(path, "rb") as f:
                shutil.copyfileobj(f, self.wfile, 256 * 1024)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def send_bytes(self, data, ctype, name):
        self.send_response(200)
        self.cors()
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Content-Disposition", f'attachment; filename="{name}"')
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)


# ------------------------------------------------------------------ keep yt-dlp fresh

YTDLP_VERSION = [ytdlp_version()]


def updater():
    """Sites change often; yt-dlp ships fixes within days. Update twice a day."""
    while True:
        time.sleep(12 * 3600)
        try:
            subprocess.run([sys.executable, "-m", "pip", "install", "-q", "-U", "yt-dlp"], timeout=300)
            YTDLP_VERSION[0] = ytdlp_version()
        except Exception:
            pass


if __name__ == "__main__":
    threading.Thread(target=updater, daemon=True).start()
    print(f"Kitatool Save on :{PORT} · yt-dlp {YTDLP_VERSION[0]}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
