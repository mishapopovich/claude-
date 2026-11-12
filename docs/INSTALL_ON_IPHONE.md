# Test MP Coaching on your iPhone (free)

You need your iPhone, its cable, a computer, and your normal Apple ID. No paid account.

Two limits Apple puts on free installs:
- The app stops opening after **7 days**. Reinstall the same way and your data is still there
  (don't delete the app first).
- **Leaderboards are off** (they need iCloud, which free accounts can't use). Everything else works.

Pick the section for your computer.

---

## If you have a Mac (easiest)

1. Install **Xcode** from the Mac App Store (free, large download).
2. Download this project: on GitHub, switch to the branch `claude/personal-trainer-app-brief-ryffle`
   → green **Code** button → **Download ZIP**, and unzip it.
3. Double-click **MPCoaching.xcodeproj**.
4. Xcode → **Settings → Accounts → +** → sign in with your Apple ID.
5. In the left sidebar click **MPCoaching** (blue icon) → **Signing & Capabilities**:
   - Team: pick your name **(Personal Team)**
   - Bundle Identifier: change `com.example.mpcoaching` to something unique,
     e.g. `com.yourname.mpcoaching`
6. Plug in your iPhone, unlock it, tap **Trust**. Pick your iPhone at the top of Xcode, press **▶︎**.
7. On the iPhone, if asked:
   - **Settings → Privacy & Security → Developer Mode → On** (the phone restarts).
   - **Settings → General → VPN & Device Management** → your Apple ID → **Trust**.
8. Press ▶︎ again. The app opens.

Every 7 days: plug in and press ▶︎.

If Xcode shows an error about **HealthKit** on your free account: in Signing & Capabilities click
the trash icon next to HealthKit and press ▶︎ again. The app works, just without Apple Health data.

---

## If you have a Windows PC (no Mac)

1. **Get the app file.** On GitHub open the repo → **Actions** tab → **iPhone app file (for free
   sideloading)** → the newest green run → scroll to **Artifacts** → download **MPCoaching-ipa**
   and unzip it. You now have `MPCoaching.ipa`.
2. **Install iTunes and iCloud from apple.com** (the versions from apple.com, not the Microsoft
   Store), so Windows can talk to your iPhone.
3. Install **Sideloadly** (sideloadly.io).
4. Plug in your iPhone, unlock it, tap **Trust**.
5. Open Sideloadly, drag in `MPCoaching.ipa`, type your Apple ID, click **Start**.
   (It asks for your Apple ID password to sign the app. If you'd rather not use your main
   Apple ID, make a second free one just for this.)
6. On the iPhone:
   - **Settings → Privacy & Security → Developer Mode → On** (the phone restarts).
   - **Settings → General → VPN & Device Management** → your Apple ID → **Trust**.
7. Open MP Coaching.

Every 7 days: repeat step 5 (Sideloadly can also refresh automatically while your phone and PC
are on the same Wi-Fi).

If Apple Health won't connect with this method, that's a free-account limit on Health access;
the rest of the app still works.

---

## What to try in the first week
- Mark your shifts and clinicals for the week on the Today tab and see where sessions land.
- Do Day 1 and Day 2, logging every set. Check the PR page and an exercise's stats page.
- Settings → Apple Health → connect Sleep and Heart rate, so readiness uses them.
- Add your Anthropic API key (Settings) and ask the coach what to do today.
- Write down anything slow, confusing or missing. That list is the next round of work.

---

## Later: TestFlight (paid, $99/year)
When you want friends on it and leaderboards on, the paid Apple Developer account plus the
`TestFlight` GitHub workflow uploads builds for you. Steps are in `docs/TESTFLIGHT.md`.
