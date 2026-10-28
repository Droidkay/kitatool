NOTCH PLAYER 3.4  (Alcove-style)

Install:   cd ~/Downloads/NotchPlayer && bash build.sh

What you get
- Notch that grows into live activities: album art + animated bars while music plays, timer countdown, optional clock.
- Short peeks that drop out of the notch: new song, charging, low battery, timer done, meeting in 5 minutes.
- Hover the notch to open it. Pages: Music (seekable progress, accent colour from the cover), Calendar, Timer, Shelf.
- Shelf: drag any file toward the notch, it opens and holds the file. Drag it back out when you need it.
- Menu bar icon: Open at Login, Show Clock When Idle, Quit.

First run: allow Automation for Music/Spotify and Calendar access when macOS asks.
If build errors appear, paste: swift build -c release 2>&1 | grep -A3 "error:"

New in 3.2
- Volume HUD drops out of the notch when you change volume or mute.
- Swipe left/right with two fingers: switches pages when open; skips tracks when hovering the closed notch.
- Menu bar toggles: Show Clock When Idle, Volume HUD, Banners.

New in 3.3 - Companion Robot
- A little robot lives on the left of the notch. Its eyes follow your cursor and it blinks.
- It dances while music plays, focuses during a timer, celebrates when the timer ends,
  gets happy when you charge, droops on low battery, and falls asleep (zzz) after 2 idle minutes.
- It greets you when the app starts, says "All charged up" at 100%, and reminds you to stretch after an hour of use.
- Turn it off from the menu bar icon: Companion Robot.
- Opens by itself after a restart (Open at Login is on from the first run). Untick it in the menu bar icon to stop that.

New in 3.4 - Smarter robot + iPhone-style notifications
- Notifications: messages from WhatsApp, Messages, Mail, Slack etc. drop out of the notch
  like on iPhone (app icon, who it's from, the message). Hover to see recent ones; click one to open the app.
  Needs Full Disk Access: System Settings > Privacy & Security > Full Disk Access > turn on Notch Player,
  then quit and reopen it. Tip: set an app's banner style to None in System Settings > Notifications
  so you only see it in the notch.
- The robot checks on you every hour of active use: how long since your last break, music,
  your next meeting, water. Hover the notch to answer: Great / Okay / Tired / Stressed.
  Tired starts a 5-minute break timer. Stressed starts a 1-minute breathing exercise (with a Bible verse).
- New Buddy page (smiley tab): tap the robot for tips, jokes and verses; Water, Break, Focus (25 min),
  Breathe; today's active time, breaks, water and focus sessions.
- Morning greeting, and an end-of-day summary after 9pm.
- Menu bar: Robot Check-ins (30 min / 1 h / 2 h / Off), Change My Name, App Notifications, Bible Verses.
