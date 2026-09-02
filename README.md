# Sitless

Sitless helps you see how much of your day you spend standing versus inactive, using data your
Apple Watch already measures in Apple Health. There's no account, no cloud backend, and no
analytics — everything runs on your iPhone and Apple Watch, reading directly from Apple Health.

## Requirements

- Xcode with the current public iOS and watchOS SDKs (built and verified against Xcode 26).
- A physical iPhone, ideally paired with an Apple Watch, signed into an Apple ID with Health
  data. Real Apple-Watch-synced HealthKit data cannot be exercised on the iOS Simulator — the
  Simulator's HealthKit store only accepts manually entered samples.
- An Apple Developer account (free or paid) to install the app on-device.

## Building and running

1. Open `Sitless.xcodeproj` in Xcode.
2. Select the `Sitless` scheme (or `Sitless Watch App` for the Watch companion) with your
   physical device as the run destination.
3. Build and run. On first launch, Sitless explains what it reads from Apple Health before the
   system permission prompt appears.

### Free vs. paid Apple Developer account

Installing with a **free** Apple Developer account signs the app with a 7-day provisioning
profile — after 7 days the app stops launching on your device until you rebuild and reinstall
from Xcode. A **paid** Apple Developer Program membership issues a 1-year profile instead. This
is an Apple platform limitation, not something Sitless works around.

## Running tests

```
cd Packages/SitlessKit
xcodebuild test -scheme SitlessKit -destination "platform=iOS Simulator,name=iPhone 17 Pro"
```

or, from the repository root:

```
xcodebuild test -scheme Sitless -destination "platform=iOS Simulator,name=iPhone 17 Pro"
```

## Privacy

- No account, no cloud backend, no third-party analytics, no advertising.
- Standing, activity, sleep, and motion data are read directly from Apple Health and Core Motion
  on-device and are never uploaded anywhere.
- The only data that ever leaves your iPhone is your Standing Goal, pushed to your paired Apple
  Watch over WatchConnectivity so the two devices agree on your target — nothing else is
  exchanged between them, and neither device talks to a server.

## Off-wrist time — how it's inferred

A gap in the data doesn't always mean you were sitting still: your watch may simply have been on
the charger, in the shower, or left on a nightstand. Sitless infers those stretches from gaps
between consecutive heart-rate samples — the one signal an Apple Watch records continuously while
it's worn and stops recording entirely when it comes off — and shows them on the timeline as
Unknown rather than counting them as estimated sitting time. Time the app couldn't measure is
therefore left out of your standing percentage instead of dragging it down, and a day with enough
unmeasured time shows the "Partial data today" badge.

This is best-effort, and deliberately conservative in one direction:

- Only stretches *between* two heart-rate samples are considered — never the time before the
  first sample or after the last one of a day. Using Sitless without an Apple Watch means there
  are no heart-rate samples at all, so nothing is ever inferred and your day is classified exactly
  as it was before.
- The watch samples heart rate opportunistically, widening its cadence in Low Power Mode and
  through long stretches of stillness, so the silence threshold is set generously. The effect is
  that some genuinely off-wrist time is still counted as estimated sitting time, rather than
  worn-but-still time being wrongly written off as unmeasured.
- Sitless only ever knows that the watch wasn't being worn, never why. Charging, showering and
  simply forgetting it all look the same.

## Inactivity reminders — known limitation

Sitless can remind you to change position after a period of inactivity (Settings → Inactivity
reminder). It's implemented as a single rescheduling local notification: every time HealthKit
reports new standing activity, Sitless cancels the pending reminder and schedules a new one
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
  reminder's fire time, the reminder can still appear — Sitless re-evaluates suppression on
  every new signal it receives, but it cannot guarantee a check happens in the exact instant
  before delivery.
- Workout detection relies on HealthKit's own workout samples, which are committed once a
  session finishes rather than exposed live to other apps; Sitless treats a workout as active
  from its recorded start through a short grace period after its recorded end.

This is the most reliable behavior available through Apple's public, supported APIs, without
resorting to unreliable continuous background polling, which Sitless deliberately avoids.
