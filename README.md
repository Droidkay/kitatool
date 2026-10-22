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
