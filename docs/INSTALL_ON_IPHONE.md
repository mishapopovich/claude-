# Getting MP Coaching on your iPhone

There are two ways. **TestFlight is the one to use**: it installs like a normal app, updates
itself, lasts 90 days per build, lets you invite friends (up to 10,000 testers) so the
leaderboards actually have people on them, and doesn't need a Mac.

| | TestFlight (recommended) | Xcode on a Mac, free Apple ID |
| --- | --- | --- |
| Cost | Apple Developer Program, $99/year (you need it for the App Store anyway) | Free |
| Needs a Mac | No (GitHub builds it) | Yes |
| Friends can install | Yes, by link | No |
| Leaderboards (iCloud) | Yes | No (free accounts can't use iCloud) |
| App expires | Each build after 90 days (just upload a new one) | After 7 days, reinstall from Xcode |

---

## Option A: TestFlight, no Mac needed

### 1. Join the Apple Developer Program (one time)
developer.apple.com/programs → Enroll. Takes from a few minutes to a couple of days to be approved.

### 2. Register the app (one time, on the web)
1. **developer.apple.com → Certificates, IDs & Profiles → Identifiers → +** → App IDs → App.
   - Bundle ID: something like `com.yourname.mpcoaching`
   - Capabilities: tick **HealthKit**, and **iCloud** (with CloudKit) if you want leaderboards.
2. For leaderboards: **Identifiers → (dropdown) iCloud Containers → +** → `iCloud.com.yourname.mpcoaching`.
   Then open your App ID again → iCloud → Configure → tick that container.
3. **appstoreconnect.apple.com → Apps → + New App** → iOS, name "MP Coaching", pick the bundle ID
   from step 1, any SKU (e.g. `mpcoaching`).

### 3. Create an API key so GitHub can upload builds (one time)
App Store Connect → **Users and Access → Integrations → App Store Connect API → +**
- Name: GitHub, Access: **App Manager**
- Download the `.p8` file (you can only download it once). Note the **Key ID** and the **Issuer ID**.

### 4. Add the secrets to GitHub (one time)
GitHub repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Your Team ID (developer.apple.com → Account → Membership details) |
| `BUNDLE_ID` | `com.yourname.mpcoaching` |
| `ASC_KEY_ID` | Key ID from step 3 |
| `ASC_ISSUER_ID` | Issuer ID from step 3 |
| `ASC_KEY_P8_BASE64` | The .p8 file as base64. On a Mac: `base64 -i AuthKey_XXXX.p8 \| pbcopy`. On Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8"))` |
| `CLOUDKIT_CONTAINER` | *(optional, leaderboards)* `iCloud.com.yourname.mpcoaching` |

### 5. Build and upload
GitHub → **Actions → TestFlight → Run workflow**. About 10–15 minutes. Apple then processes the
build (5–30 minutes) and emails you.

### 6. Install
1. Install the **TestFlight** app from the App Store on your iPhone.
2. App Store Connect → your app → **TestFlight** → Internal Testing → + → add yourself (your Apple ID email).
3. Open the email/TestFlight → Install. Done.

To let friends in: TestFlight → **External Testing** → create a group → add the build → enable the
**public link** and send it. The first external build goes through a short Apple review (usually
under a day).

### 7. Leaderboards: one-time iCloud setup
Leaderboards store data in CloudKit, and TestFlight builds use the **Production** database, which
needs the record types created first:
1. **icloud.developer.apple.com → CloudKit Console → your container → Schema.**
2. Create the 4 record types from `cloudkit/schema.ckdb` (Lifter, Username, LBGroup, Membership)
   with the listed fields, in the **Development** environment. Mark `Membership.groupCode` as
   **Queryable** (Indexes). On a Mac you can instead run:
   `xcrun cktool import-schema --team-id TEAMID --container-id iCloud.com.yourname.mpcoaching --environment development --file cloudkit/schema.ckdb`
3. **Deploy Schema Changes…** to Production.

Everything except leaderboards works without this.

---

## Option B: Xcode on a Mac (free, quick test)

1. Install Xcode from the Mac App Store. Open `MPCoaching.xcodeproj`.
2. Xcode → Settings → Accounts → add your Apple ID.
3. Select the **MPCoaching** target → Signing & Capabilities → Team: your name (Personal Team).
   Change the Bundle Identifier to something unique, e.g. `com.yourname.mpcoaching`.
4. Plug in your iPhone, pick it at the top, press ▶︎.
5. On the iPhone: Settings → General → VPN & Device Management → trust your developer profile.
   Also turn on Settings → Privacy & Security → **Developer Mode** when asked.

Free accounts: the app stops opening after 7 days (press ▶︎ again to reinstall; your data stays),
and iCloud leaderboards are not available. If Xcode refuses the HealthKit capability on a free
account, remove it under Signing & Capabilities: the app still runs, just without Health data.

---

## What to try in the first week
- Mark your shifts and clinicals for the week on the Today tab and see where sessions land.
- Do Day 1 and Day 2, logging every set. Check the PR page and an exercise's stats page.
- Connect Apple Health (Settings → Apple Health) so readiness uses your sleep and resting heart rate.
- Add your Anthropic API key and ask the coach what to do today.
- Write down anything slow, confusing or missing. That list is the next round of work.
