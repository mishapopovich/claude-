# Trainer (working name)

An iPhone-only personal trainer app: guided workouts with fast set logging, per-exercise stats,
bodyweight and big-three PRs, Apple Health read/write, check-ins on your own schedule, and an AI
coach powered by your own Anthropic API key.

This is the **MVP** from the build brief. Friends, groups and leaderboards (v2) are not built yet:
they wait on the backend decision (see open questions below).

## Run it

1. Open `Trainer.xcodeproj` in **Xcode 16 or newer** (the project uses folder-synced groups, so
   any file you add under `Trainer/` is picked up automatically).
2. Select the **Trainer** target → *Signing & Capabilities* → pick your Team. Change the bundle id
   (`com.example.trainer`) to something you own, e.g. `com.yourname.trainer`.
3. Run on an iPhone (HealthKit has limited data in the Simulator). iOS 17+.

If the project ever refuses to open, `brew install xcodegen && xcodegen generate` rebuilds it from
`project.yml`.

> The code was written without a Mac in the loop, so the first build may surface a few compiler
> errors. They should be small (a type name or a modifier); fix them as Xcode points them out.

## What's in the MVP

| Brief feature | Where |
| --- | --- |
| 1. AI coach chat (streaming, your own key in Keychain, model picker) | `Views/Chat`, `Services/AnthropicClient.swift`, `Services/TrainerContext.swift` |
| 2. Check-ins: 1–4/day presets, custom times, quiet hours, days on/off, skip on shift days | `Services/CheckInScheduler.swift`, `Views/Settings/CheckInSettingsView.swift` |
| 3. Exercise library: 35 exercises, picture, muscles, equipment, steps, mistakes | `Data/ExerciseCatalog.swift`, `Views/Library` |
| 4. Guided session, one-tap set logging, auto rest timer, edit/skip/extra sets, summary, saved to Health | `Views/Train/SessionView.swift`, `SetEntryPad.swift` |
| 5. Per-exercise stats: best weight, Epley 1RM chart, volume chart, recent sessions, PRs, 1M/3M/6M/All | `Views/Library/ExerciseStatsView.swift` |
| 6. Bodyweight (with 7-day average) and bench/squat/deadlift maxes, tested vs estimated, total | `Views/Progress/ProgressHubView.swift` |
| 8. HealthKit: read steps, energy, sleep, HR, body mass, food macros; write workouts and body mass; each group asked separately | `Services/HealthKitManager.swift`, Settings → Apple Health |
| Shift-aware week plan (sessions move around 12h/24h shifts, clinicals, classes) | `Services/TrainingPlanner.swift`, the week strip on Today/Train |

Tabs: **Today · Train · Coach · Library · PRs**. Settings is the gear on Today. Stats open from any
exercise (library, session history, PR page → "Stats for every exercise").

### How the pieces fit

- **Storage:** SwiftData, on device only. Weights are stored in kg and shown in lbs or kg.
- **PRs** come from logged sets each time they're shown, so editing or deleting a set never leaves
  a stale record. Tested 1RMs are stored separately and always labelled "tested". The first
  session of an exercise sets a baseline and isn't celebrated. After that, a beaten best shows a
  banner and a haptic the moment you log the set.
- **Set logging:** the weight and reps from the last set (or last time) are pre-filled, so most
  sets take **one tap** on *Log set*. Paired exercises (supersets) alternate automatically.
- **Check-ins:** local notifications fire at your times. The coach's message is written when you
  open the Coach tab (Claude if a key is set, a built-in message otherwise), so no server is
  needed. Notifications are scheduled 14 days ahead and refreshed every time the app opens.
- **Coach:** calls `https://api.anthropic.com/v1/messages` with streaming. The key never leaves
  the Keychain except in that request header. Default model `claude-sonnet-5-5` (changeable in
  Settings). The persona sits in a cached system block; a fresh data snapshot (week plan, recent
  sessions, maxes, bodyweight trend, Health summary numbers) follows it. Server-side refusal
  fallback is turned on for models that support it.
- **Pictures:** each exercise has an animated stick-figure drawing generated in code, so there's
  no image licensing question. To use a real photo, add an image named `exercise-<id>` (e.g.
  `exercise-deadlift`) to `Assets.xcassets` and it replaces the drawing.

## Acceptance checklist (from the brief)

- [x] Full Day 1 workout without leaving the session screen (picture opens as a sheet)
- [x] One tap to log a set once weight/reps are set (pre-filled from last time)
- [x] Stats page with a real chart after two logged sessions
- [x] PR page: bodyweight, three maxes, total, new PR flagged on log
- [x] No API key: logging, stats and PRs work, and the Coach tab explains how to add a key
- [x] With a key, the coach answers using recent training and Health data
- [x] Check-ins at chosen times; custom schedule accepts any times

## Open questions for you

1. **App name.** "Trainer" is a placeholder (display name + target name).
2. **Friends/leaderboard backend:** CloudKit shared database, Firebase, or Supabase? CloudKit is
   the simplest for an iPhone-only app (no extra accounts, Apple ID sign-in, free tier).
3. **Exercise pictures:** the drawings avoid licensing. If you want photos, where from and under
   what licence?
4. **Distribution:** TestFlight first, or straight to the App Store?
5. **Price:** free for personal use, one-time, or subscription?

Still to do before an App Store release: an app icon (`Assets.xcassets/AppIcon`), and a privacy
policy (needed because of HealthKit).
