# Rotato iOS

iOS port of [Rotato](https://github.com/Alvis1337/rotato) — wallpaper discovery & collection app.

Built with **Swift + SwiftUI + SwiftData**, targeting **iOS 17+**.

## Features

- Browse wallpapers from **Gelbooru, Danbooru, Wallhaven, Reddit, Rule34**
- Fullscreen preview with **pinch-to-zoom**, **double-tap zoom**, **swipe-down dismiss**
- **Collections** — save wallpapers, manage with SwiftData
- **Save to Photos** — save any wallpaper to your photo library to set as wallpaper
- **MyAnimeList** integration — OAuth2 PKCE, anime list as search tags
- Per-source configuration (API keys, tags, NSFW purity)

## Build

Uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project:

```bash
brew install xcodegen
xcodegen generate
open Rotato.xcodeproj
```

## CI / Releases

Every push to `main` triggers a GitHub Actions build on macOS 15 that produces an **unsigned IPA** attached to a GitHub Release.

Since the IPA is unsigned, you'll need to sign it before installing:
- **Sideloadly** (easiest) — drag & drop + your Apple ID
- **AltStore** — via AltServer
- **Xcode / Apple Configurator 2** — after signing with `codesign`

## Architecture

```
Rotato/
├── App/                  # Entry point + tab nav
├── Data/
│   ├── Models/           # WallpaperItem, SwiftData models
│   ├── Settings/         # AppSettings (@Observable, UserDefaults)
│   ├── Plugins/          # Source plugin protocol + per-source implementations
│   └── MAL/              # OAuth2 PKCE + anime list API
└── UI/
    ├── Common/           # CachedImageView, ZoomableImageView, FullscreenPreviewView
    ├── Discover/         # Browse + search wallpapers
    ├── Library/          # Collections management
    └── Settings/         # Source config, MAL, NSFW
```
