# TestFlight (paid Apple Developer account)

For later: lets friends install by link and turns on leaderboards. No Mac needed; GitHub builds and uploads it.

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
