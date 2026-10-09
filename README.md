# Rotato for iOS

A SwiftUI port of [Rotato for Android](https://github.com/Alvis1337/rotato). iOS 17+, iPhone.

## Layout

| Path | What |
| --- | --- |
| `RotatoKit/Sources/RotatoKit` | Platform-neutral core: models, source engines (Gelbooru family, Danbooru, Moebooru, Wallhaven, Reddit, Zerochan), storage, Discover feed, rotation, rendering, backups |
| `RotatoKit/Sources/RotatoUI` | SwiftUI screens: Discover, Library, Collections, Settings, Sources, Plugin Store, Setup, Shortcuts setup |
| `RotatoKit/Sources/RotatoIntents` | Shortcuts actions, compiled into the app and widget by the Xcode project |
| `RotatoKit/Sources/RotatoChecks` | Checks for the core that run without Xcode |
| `App/`, `Widget/` | App entry point, App Shortcuts, home-screen widget |
| `project.yml` | XcodeGen spec for `Rotato.xcodeproj` |

## Install a build

Every push builds an unsigned `Rotato.ipa` in GitHub Actions (Actions → iOS build → the run's
artifacts). Install it with [Sideloadly](https://sideloadly.io) or AltStore, which sign it with
your Apple ID. Free Apple IDs need a re-sign every 7 days.

## Build locally

Current Xcode needs an Apple silicon Mac.

1. Install Xcode 26 from the App Store (it needs about 20 GB including the iOS platform).
2. `brew install xcodegen`, then in this folder run `xcodegen`.
3. Open `Rotato.xcodeproj`. For both the **Rotato** and **RotatoWidget** targets, under
   *Signing & Capabilities* pick your team.
4. Plug in your iPhone, choose it as the run destination and press Run. On the phone, allow
   the developer profile under Settings → General → VPN & Device Management, and turn on
   Developer Mode if asked.

Free Apple IDs need a re-install every 7 days. If Xcode says your team doesn't support
**App Groups**, remove that capability from both targets and delete the RotatoWidget target;
the app falls back to its own storage and everything except the widget works.

If a bundle ID is taken, change `com.chrisalvis.rotato` (and `.widget`) in `project.yml` and
rerun `xcodegen`.

## How rotation works on iPhone

iOS doesn't let apps set the wallpaper. Rotato's **Get Rotato Wallpaper** action picks the next
image (shuffle with ratings, per-screen collections, NSFW rules, night pause, time of day),
crops it for the screen and hands it to Apple's **Set Wallpaper** action in a shortcut you make.
A Shortcuts *Time of Day* automation runs it on your schedule. Settings → Shortcuts Setup in
the app walks through it. "Set now" buttons queue the image and run that shortcut.

There's no iOS equivalent for live wallpaper, the screen saver, Quick Settings tiles, foldable
features or Tasker hooks, so those weren't ported.

## Trying it on a Mac

```sh
cd RotatoKit && swift run RotatoPreview
```

Opens the iPhone screens in a phone-sized Mac window, with no Xcode needed (Command Line Tools
are enough, Intel or Apple silicon). Discover, collections, the Library, sources and settings all
work against real data. Shortcuts, the widget and Face ID are iOS-only, controls take macOS
styling, and "Set now" can't change the Mac's wallpaper. Its data lives in
`~/Library/Application Support/Rotato`.

## Checking the core without Xcode

```sh
cd RotatoKit
swift build                        # type-checks everything, UI included (built for macOS)
swift run RotatoChecks             # offline checks
swift run RotatoChecks --network   # also fetches from the live sources
```

## Not ported yet

Taste screen (tag tiers can already be set from a tag's menu), MyAnimeList and the anime
collection builder, schedules, interest profiles, sharing a collection as a file.
