# PrayBar

A small, native prayer-time menu-bar app for **macOS 13+ on Apple Silicon**. See the next prayer at a glance, with a countdown or clock time. Prayer calculations run locally using [Adhan Swift](https://github.com/batoulapps/adhan-swift).

[Download for Mac](https://github.com/mo-shawa/PrayBar/releases/latest/download/PrayBar.dmg) · [Website](https://praybar.com) · [Release notes](https://github.com/mo-shawa/PrayBar/releases/latest)

## Install

Open the DMG, drag **PrayBar** to **Applications**, then launch it. Published downloads are signed with Developer ID and notarized by Apple. To update, quit PrayBar and replace the app in Applications; saved settings remain.

Allow automatic location or enter coordinates and a time zone in Settings. Once prayer times are available, an optional prompt shows the calculation defaults and offers Settings. Launch at login is recommended and starts unchecked.

## Use

- The menu bar shows the next prayer and remaining whole minutes by default. Settings can switch it to clock time.
- Click it to see today's five prayer times, the active location/time zone, and Settings. After Isha, it shows tomorrow's Fajr. Sunrise is excluded.
- Defaults are **Muslim World League** and **Standard Asr** (Shafi, Maliki, Hanbali). Choose your calculation method and Standard or Hanafi Asr explicitly; location does not choose religious preferences.
- Automatic location follows the Mac's time zone. Manual location uses the selected IANA time zone, such as `Asia/Amman` or `America/Toronto`.
- Prayer-time notifications and advance reminders are independently optional, both off initially. The reminder defaults to **10 minutes**. Choose banner/alert style and sound in macOS **System Settings → Notifications → PrayBar**. Focus and sleep can affect delivery.
- Launch at login is optional. Keep PrayBar running to replenish its local notification schedule each day.

PrayBar shows a clear location-needed or unavailable state when it cannot calculate a valid schedule. A failed automatic refresh retains a valid cached fix. There is no fabricated fallback timetable.

## Privacy and offline use

Prayer times, countdowns and notifications work offline with saved coordinates, date/time, time zone and calculation preferences. The app has no backend, analytics, accounts, prayer-time web API, or network entitlement. Preferences and the cached location stay on the Mac.

macOS Location Services can need network access to acquire a new position. Automatic lookups request approximately kilometre-level accuracy and stop after success, failure, or a 30-second timeout. A fix is stale after 24 hours; refreshes happen on relevant launch/wake/time-zone events or explicit request. There is no continuous tracking. Manual location avoids those lookups. When travelling offline, update coordinates/time zone yourself if the cached location is no longer appropriate.

## Build and test

Use **Xcode 16+ / Swift 6+**. Open `PrayBar.xcodeproj`, select the shared **PrayBar** scheme and **My Mac**, or run:

```sh
swift test -c release --force-resolved-versions
xcodebuild -project PrayBar.xcodeproj -scheme PrayBar \
  -configuration Release -derivedDataPath build \
  -clonedSourcePackagesDirPath .build/xcode-packages \
  -onlyUsePackageVersionsFromResolvedFile build
open build/Build/Products/Release/PrayBar.app
```

The source project uses ad-hoc signing, so a paid developer account is unnecessary for a local build. Rebuilding an ad-hoc binary can affect macOS permission grants. Quit any installed copy before running another build. App Sandbox, the location entitlement/usage descriptions, hardened runtime, and menu-bar-only configuration are included.

Both checked-in `Package.resolved` files pin Adhan **1.5.0**. The 32 core tests cover prayer transitions, midnight/tomorrow, DST and time-zone changes, settings changes, unavailable calculations, location failure/cancellation, local notification scheduling and timer replacement. Tests do not replace real permission, login, sleep/wake or notification-delivery checks.

AppKit owns the status item/menu. The SwiftUI Settings form exists only while its window is open. Cached schedules and one cancellable display timer avoid polling: clock mode waits for prayer/day boundaries; countdown mode updates about once per minute. Wake and clock/time-zone changes refresh from the current time. No helper, updater, audio player, or sleep-prevention assertion is used.

## Releases

Pushes to `main` and pull requests run tests and an app build. Official releases use the configured, encrypted `release` environment for Developer ID signing and Apple notarization. Push a new, unused version tag from a tested commit on `main` (increment the example version if it has already been released):

```sh
git tag v1.0.2
git push origin v1.0.2
```

The tag sets the app version automatically. The workflow signs, notarizes, checks Gatekeeper and the DMG's contents, generates a checksum, and publishes the GitHub release. The website follows the latest `PrayBar.dmg`. A manual **Release** workflow run on `main` rehearses the same process without publishing. Existing public releases are never overwritten.

The environment needs secrets `SIGNING_CERTIFICATE_P12` (base64 of the password-protected Developer ID identity), `SIGNING_CERTIFICATE_PASSWORD`, `APPLE_ID`, and `NOTARIZATION_PASSWORD`; variables are `APPLE_TEAM_ID` and `SIGNING_IDENTITY`. Restrict it to `main` and `v*` tags. Only trusted maintainers should be able to change the workflows or release code. Signing secrets are never supplied to pull-request checks.

For a local release, store credentials with `xcrun notarytool store-credentials PrayBarNotary`, run the tests, then set `SIGNING_IDENTITY` and `APPLE_TEAM_ID` when calling `scripts/release.sh VERSION BUILD_NUMBER`. Verified output goes to `build/distribution/`; the script refuses to overwrite an existing DMG. Apple's processing can outlast the 45-minute wait: inspect the saved submission ID and diagnostics before rerunning. Manual installation and feature checks still belong in the release process.

## Performance verification

Measure an optimized **Release build outside the debugger**. With Settings and the menu closed, observe **at least five minutes in each display mode**. Target **0.0% CPU in most idle Activity Monitor samples**, with no sustained background CPU activity. This is an acceptance target, not a guarantee of zero work; countdown redraws take occasional CPU.

Record hardware, OS, build revision/configuration, start/end times and measurement method. Record cumulative CPU, memory footprint/RSS, and wakeups where available. Measure memory before opening Settings, after closing it, and after at least ten open/close cycles. Allow settling and distinguish retained framework pages from a retained view or leak. Earlier automated Settings cycles showed small native accessibility teardown allocations; behavior during ordinary manual use remains to be verified.

The development-only sampler is not part of the app. Run a fresh process for each mode, leave Settings unopened for the baseline, and allow at least 35 seconds for initial location work to settle:

```sh
mkdir -p build/profiling
xcrun clang -O2 -Wall -Wextra scripts/profile-idle.c -o build/profile-idle
pgrep -x PrayBar
# Replace PID and MODE with the process ID and clock/countdown:
build/profile-idle PID 300 > build/profiling/MODE.csv
python3 scripts/summarize-idle.py build/profiling/MODE.csv
pmset -g assertions
```

The sampler reads process counters every five seconds and derives CPU from their deltas; stack samples alone do not measure cumulative CPU. Keep Instruments, heap scans and UI interaction separate from passive baselines, and report any tool overhead. Confirm location updates stop, no sleep assertion belongs to PrayBar, and physical sleep/wake recovers the current prayer. Fresh-account permissions, login launch and actual notification appearance also require manual verification. Label every result as measured or unverified, and keep raw machine/location logs out of commits. When profiling or GUI execution is unavailable, record that limitation rather than claiming these checks passed.

## License

[MIT](LICENSE), copyright © 2026 Mahmoud Shawa. Adhan Swift's separate [MIT notice](Resources/Adhan-LICENSE.txt) is retained. Both notices are bundled with the app.
