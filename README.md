# PrayBar

Prayer times in your Mac's menu bar. PrayBar shows the next prayer and the time left, or its clock time, and lists today's five prayers when you click it. Times are calculated on your Mac with [Adhan Swift](https://github.com/batoulapps/adhan-swift).

Requires macOS 13 or later on an Apple Silicon Mac.

[Download for Mac](https://github.com/mo-shawa/PrayBar/releases/latest/download/PrayBar.dmg) · [Website](https://praybar.com) · [Release notes](https://github.com/mo-shawa/PrayBar/releases/latest)

## Install

Open the DMG, drag **PrayBar** to **Applications**, and open it. Allow location access, or enter coordinates and a time zone in Settings. Downloads are signed with Developer ID and notarized by Apple.

To update, quit PrayBar and replace the app in Applications. Your settings are kept.

## Using it

- The menu bar shows the next prayer and the minutes left, like `Asr · 42m`. Settings can switch it to the prayer's time instead.
- Click it for today's five prayers, your location and time zone, and Settings. After Isha it shows tomorrow's Fajr. Sunrise isn't listed.
- The defaults are **Muslim World League** and **Standard Asr** (Shafi, Maliki, Hanbali). Pick the method and Asr you follow in Settings; Hanafi Asr is there too.
- With automatic location, PrayBar follows your Mac's time zone. With a manual location, choose a time zone such as `Asia/Amman` or `America/Toronto`.
- Notifications at prayer time and reminders before it (10 minutes by default) are both optional and start off. Choose banners or alerts, and the sound, in **System Settings → Notifications → PrayBar**. Focus and sleep can affect delivery.
- Launch at login is optional. PrayBar tops up its notification schedule each day while it's running, so keep it open if you rely on reminders.

If PrayBar can't work out your prayer times, the menu bar says so instead of guessing. If a location refresh fails, it keeps using the last good location.

## Privacy and offline use

PrayBar has no account, server or analytics, and no permission to use the network, so it can't go online at all. Prayer times, the countdown and notifications all work offline. Your settings and location stay on your Mac.

Finding your location is up to macOS Location Services, which may use the network. PrayBar asks for an approximate, kilometre-level position and stops once it has one, fails, or 30 seconds pass. It looks again when it launches, when your time zone changes, when you choose **Refresh Location**, or after waking if its last position is more than a day old. It never tracks you in the background. To avoid location lookups entirely, enter your location in Settings, and update it yourself if you travel without a connection.

## Performance

PrayBar averages about 0.01% CPU while idle and uses about 11.5 MiB of memory until Settings is opened. [praybar.com/performance](https://praybar.com/performance/) explains how this was measured and has every run and the raw data.

To measure it yourself, leave PrayBar running with its menu closed, then:

```sh
mkdir -p build
xcrun clang -O2 scripts/profile-idle.c -o build/profile-idle
build/profile-idle $(pgrep -x PrayBar) 300 > run.csv
python3 scripts/summarize-idle.py run.csv
```

The sampler isn't part of the app. It reads PrayBar's process counters every five seconds and reports CPU, memory, wakeups and disk I/O.

## Building

Use Xcode 16 or later (Swift 6). Open `PrayBar.xcodeproj` and run the **PrayBar** scheme on **My Mac**, or from the command line:

```sh
swift test -c release --force-resolved-versions
xcodebuild -project PrayBar.xcodeproj -scheme PrayBar \
  -configuration Release -derivedDataPath build \
  -clonedSourcePackagesDirPath .build/xcode-packages \
  -onlyUsePackageVersionsFromResolvedFile build
open build/Build/Products/Release/PrayBar.app
```

Local builds are ad-hoc signed, so you don't need a paid developer account. macOS may ask for location permission again after a rebuild. Quit any installed copy before running your own.

Adhan is pinned to 1.5.0 in both `Package.resolved` files. The 32 tests cover prayer transitions, midnight and tomorrow's Fajr, DST and time-zone changes, settings changes, unavailable calculations, location failures and cancellation, notification scheduling, and timers.

How it fits together: AppKit runs the menu bar item and its menu, and the SwiftUI Settings window exists only while it's open. One timer drives the display. In countdown mode it fires about once a minute; in clock mode, only at the next prayer or midnight. Waking from sleep and clock or time-zone changes refresh from the current time. The app is sandboxed with only the location entitlement, and there's no helper process, updater, audio or sleep prevention.

## Releasing

Pushes and pull requests to `main` run the tests and build the app. To publish a release, push the next unused version tag from a tested commit on `main`:

```sh
git tag v1.0.2
git push origin v1.0.2
```

The tag sets the app's version. The release workflow signs and notarizes the app, checks it with Gatekeeper, builds the DMG and its checksum, and publishes the GitHub release. praybar.com always links to the latest `PrayBar.dmg`. Running the **Release** workflow by hand on `main` does a dry run without publishing, and existing releases are never overwritten.

The workflow uses a `release` environment, limited to `main` and `v*` tags, with these secrets: `SIGNING_CERTIFICATE_P12` (the password-protected Developer ID certificate, base64-encoded), `SIGNING_CERTIFICATE_PASSWORD`, `APPLE_ID` and `NOTARIZATION_PASSWORD`. Its variables are `APPLE_TEAM_ID` and `SIGNING_IDENTITY`. Pull request checks never get the signing secrets.

To release from your own Mac instead, store notarization credentials with `xcrun notarytool store-credentials PrayBarNotary`, run the tests, then run `scripts/release.sh VERSION BUILD_NUMBER` with `SIGNING_IDENTITY` and `APPLE_TEAM_ID` set. The verified DMG goes to `build/distribution/`, and the script won't overwrite an existing one. If notarization takes longer than the script's 45-minute wait, check the saved submission ID before running it again.

## License

[MIT](LICENSE), copyright © 2026 Mahmoud Shawa. Adhan Swift's MIT notice is in [Resources/Adhan-LICENSE.txt](Resources/Adhan-LICENSE.txt). Both are included in the app.
