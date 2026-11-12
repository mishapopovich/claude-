# MP Coaching

A science-based strength and nutrition coach for iPhone. It reads all your metrics (training,
sleep, resting heart rate, food, body weight, your shift schedule), holds you back when you're
over-fatigued, pushes you when you're recovered, and lets you compete with friends on
leaderboards.

**→ To test it on your iPhone for free, see [docs/INSTALL_ON_IPHONE.md](docs/INSTALL_ON_IPHONE.md).**

Every push is compiled on a real Mac by GitHub Actions (`iOS build` workflow), so the code in this
branch is known to build. The `TestFlight` workflow signs it and uploads it to App Store Connect.

## Features

| Area | What it does | Code |
| --- | --- | --- |
| **Coach engine** | Readiness score 0–100 from sleep, resting HR vs your 30-day baseline, shifts, how you said you feel, training-load spikes (7-day vs 4-week), and lifts dropping. Low readiness trims a set per exercise (one tap restores the full plan); high readiness says go for PRs. Suggests a deload after 6 hard weeks or when lifts drop | `Services/CoachEngine.swift`, `Views/Today/CoachInsightsView.swift` |
| **Weekly volume** | Hard sets per muscle group in the last 7 days against rough maintenance/productive/high ranges | same |
| **Nutrition** | Protein target (1.6–2.2 g/kg), maintenance calories measured from FatSecret/Health intake + weight trend, daily target for your goal (build muscle / lose fat / recomp / maintain), and "you're gaining too fast" style advice | same |
| **Guided workouts** | One tap per set (pre-filled from last time), auto rest timer, supersets alternate, edit/skip/extra sets, summary with PRs, saved to Apple Health | `Views/Train` |
| **Exercise pictures** | Machine-placard style: solid figure doing the movement, working muscles lit in blue, dashed motion arrow, plus a front/back muscle chart | `Views/Components/ExerciseIllustration.swift` |
| **Stats and PRs** | Per-exercise Epley 1RM and volume charts; bodyweight with 7-day average; bench/squat/deadlift tested vs estimated maxes and total | `Views/Library`, `Views/Progress` |
| **Leaderboards** | CloudKit friends (by @username) and groups (6-character invite code). Rankings: total, bench, squat, deadlift, training streak. "You're 15 lbs behind Alex" nudges on Today. Only lifts and session counts are shared, never body weight | `Services/SocialStore.swift`, `Views/Social` |
| **Share cards** | Branded 1080×1080 PR / total images for Instagram or Messages | `Views/Social/PRCard.swift` |
| **AI coach chat** | Your own Anthropic API key (Keychain), streaming, default Claude Sonnet 5.5. Sees the same readiness, volume, nutrition and leaderboard data as the app | `Views/Chat`, `Services/AnthropicClient.swift`, `Services/TrainerContext.swift` |
| **Check-ins** | 1–4/day or custom times, quiet hours, weekdays, skip on shift days | `Services/CheckInScheduler.swift` |
| **Shift-aware plan** | Mark 12h/24h shifts, clinicals, classes; sessions move to the best days | `Services/TrainingPlanner.swift` |
| **Look** | Black-first with blue highlights; Settings → Appearance switches Dark / Light / System | `Views/Components/Theme.swift` |

Tabs: **Today · Train · Coach · Leaderboard · PRs**. The exercise library is under Train;
Settings is the gear on Today.

## Project setup notes

- Xcode 16+ (CI uses the newest Xcode on GitHub's macOS runners). iOS 17+. iPhone only.
- Folder-synced project: any file added under `MPCoaching/` is built automatically.
- Bundle ID in the project is `com.example.mpcoaching`; the TestFlight workflow overrides it
  with your `BUNDLE_ID` secret.
- Leaderboards are off until a CloudKit container is set (`AppConfig.cloudKitContainerID`, or the
  `CLOUDKIT_CONTAINER` secret for TestFlight builds). The schema is in `cloudkit/schema.ckdb`.
- `project.yml` regenerates the project with XcodeGen if ever needed.

## Decisions so far

- Name: **MP Coaching**. Backend for social: **CloudKit** (no extra accounts, free tier, Apple ID
  sign-in). Pictures: drawn in code, no licensing. Distribution: **TestFlight first**.
- Business model: subscription later (StoreKit 2). Leaderboards and share cards are the growth hook.

## Next ideas

- Subscription paywall (StoreKit 2) once the free version feels right.
- Mesocycle planner: auto-ramping volume over 4–6 weeks, then a deload week.
- Apple Watch set logging. Custom exercises and programs.
- Weekly leaderboard challenges (most volume, most PRs, best streak) for the marketing hook.
