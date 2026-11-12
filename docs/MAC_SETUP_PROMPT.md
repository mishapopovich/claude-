# Prompt for Claude on your Mac

Open the Claude desktop app on your Mac → **Code** tab → choose any folder → paste everything
in the box below as your first message. Keep your iPhone plugged in and unlocked.

```text
Please install my iPhone app "MP Coaching" on my plugged-in iPhone, using my free Apple ID
(Personal Team). Do as much as you can yourself with terminal commands, and tell me exactly
what to tap or click whenever a step needs me. Explain each thing I need to do in plain words.

1. Check Xcode: run `xcodebuild -version`. If Xcode is missing or older than 16, tell me to
   install/update it from the Mac App Store and wait for me. If needed run
   `sudo xcode-select -s /Applications/Xcode.app` and accept the license
   (`sudo xcodebuild -license accept`).

2. Get the code:
   git clone -b claude/personal-trainer-app-brief-ryffle https://github.com/mishapopovich/claude-.git ~/Developer/MPCoaching
   (If it already exists, `git pull` instead.) Work in ~/Developer/MPCoaching.

3. Find my signing team: look in ~/Library/Preferences/com.apple.dt.Xcode.plist
   (IDEProvisioningTeamByIdentifier / IDEProvisioningTeams) for my Personal Team ID.
   If there isn't one, tell me to open Xcode → Settings → Accounts → + → Apple ID, sign in,
   then wait for me and look again.

4. Find my iPhone: `xcrun devicectl list devices`. If it isn't listed or shows as unavailable,
   tell me to unlock it, tap "Trust This Computer", and (iOS 16+) turn on
   Settings → Privacy & Security → Developer Mode (the phone restarts). Wait and retry.

5. Build for my phone (this also registers the phone and makes the signing certificate):
   xcodebuild -project MPCoaching.xcodeproj -scheme MPCoaching -configuration Debug \
     -destination "id=<my iPhone's UDID>" -derivedDataPath build -allowProvisioningUpdates \
     DEVELOPMENT_TEAM=<team id> PRODUCT_BUNDLE_IDENTIFIER=com.<my-first-name>.mpcoaching build
   Use a unique lowercase bundle id. If the build fails only because a free Personal Team
   can't use HealthKit, build again adding CODE_SIGN_ENTITLEMENTS="" and tell me Apple Health
   will be off in this build. Fix any other error and retry.

6. Install and open it:
   xcrun devicectl device install app --device <UDID> build/Build/Products/Debug-iphoneos/MPCoaching.app
   xcrun devicectl device process launch --device <UDID> <bundle id>
   If launching fails as "untrusted", tell me to go to Settings → General →
   VPN & Device Management → my Apple ID → Trust, then retry.

7. When it's running, tell me: free installs expire after 7 days, and to reinstall I can just
   ask you to "rebuild and install MP Coaching" again (my data stays as long as I don't delete
   the app). Also save the commands you used into ~/Developer/MPCoaching/reinstall.sh so it's
   one command next time.

Don't change the app's code unless a build error requires it; if you do, tell me what you changed.
```
