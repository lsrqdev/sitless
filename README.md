# StandLess

StandLess helps you see how much of your day you spend standing versus inactive, using data your
Apple Watch already measures in Apple Health. There's no account, no cloud backend, and no
analytics — everything runs on your iPhone and Apple Watch, reading directly from Apple Health.

## Requirements

- Xcode with the current public iOS and watchOS SDKs (built and verified against Xcode 26).
- A physical iPhone, ideally paired with an Apple Watch, signed into an Apple ID with Health
  data. Real Apple-Watch-synced HealthKit data cannot be exercised on the iOS Simulator — the
  Simulator's HealthKit store only accepts manually entered samples.
- An Apple Developer account (free or paid) to install the app on-device.

## Building and running

1. Open `StandLess.xcodeproj` in Xcode.
2. Select the `StandLess` scheme (or `StandLess Watch App` for the Watch companion) with your
   physical device as the run destination.
3. Build and run. On first launch, StandLess explains what it reads from Apple Health before the
   system permission prompt appears.

### Free vs. paid Apple Developer account

Installing with a **free** Apple Developer account signs the app with a 7-day provisioning
profile — after 7 days the app stops launching on your device until you rebuild and reinstall
from Xcode. A **paid** Apple Developer Program membership issues a 1-year profile instead. This
is an Apple platform limitation, not something StandLess works around.

## Running tests

```
cd Packages/StandLessKit
xcodebuild test -scheme StandLessKit
```

or, from the repository root:

```
xcodebuild test -scheme StandLess -destination "generic/platform=iOS Simulator"
```

## Privacy

- No account, no cloud backend, no third-party analytics, no advertising.
- Standing, activity, sleep, and motion data are read directly from Apple Health and Core Motion
  on-device and are never uploaded anywhere.
- The only data that ever leaves your iPhone is your Standing Goal, pushed to your paired Apple
  Watch over WatchConnectivity so the two devices agree on your target — nothing else is
  exchanged between them, and neither device talks to a server.

## Inactivity reminders — known limitation

StandLess can remind you to change position after a period of inactivity (Settings → Inactivity
reminder). It's implemented as a single rescheduling local notification: every time HealthKit
reports new standing activity, StandLess cancels the pending reminder and schedules a new one
`interval` minutes out, unless you're currently asleep, in a workout, or likely driving.

iOS and watchOS give apps no supported way to run code continuously in the background to re-check
these conditions in the final seconds before a notification fires, and HealthKit's background
delivery is itself best-effort — timing can be affected by Low Power Mode, Background App
Refresh settings, and general system state. Conditions are evaluated at the moment the reminder
is (re)scheduled, not at the moment it's about to appear, so:

- A reminder can occasionally appear later than its configured interval, since delivery of the
  triggering HealthKit update depends on the OS's background-delivery scheduler rather than a
  continuous timer.
- If you fall asleep, start a workout, or start driving between the last reschedule and the
  reminder's fire time, the reminder can still appear — StandLess re-evaluates suppression on
  every new signal it receives, but it cannot guarantee a check happens in the exact instant
  before delivery.
- Workout detection relies on HealthKit's own workout samples, which are committed once a
  session finishes rather than exposed live to other apps; StandLess treats a workout as active
  from its recorded start through a short grace period after its recorded end.

This is the most reliable behavior available through Apple's public, supported APIs, without
resorting to unreliable continuous background polling, which StandLess deliberately avoids.
