# Parity with the Android app

What the iPhone app has, compared with [Rotato for Android](https://github.com/Alvis1337/rotato).
Update this when either app gains a feature.

## Ported

- Discover: masonry and square grids, source chips (with per-source NSFW), search with pinned
  searches, Refresh, For you ranking, tag tiers, Discover Settings sheet, source health
- Viewer: info pills, bottom card (Save, Set, Library, Share, Skip), collections, open post,
  save to Photos, screen preview, tags with search, rank and block
- Collections: smart collections, lock behind Face ID, merge, reorder, mosaic covers, fill from
  sources with undo, device photos, multi-select move/copy/remove, per-collection screens,
  interval and NSFW blur skip
- Library: rotation status, colour filters and rainbow order, ratings, duplicates, history,
  stats, Back / Set Now / Add Photos / Save to collection
- Rotation: shuffle with ratings, per-screen pools, night pause, time of day, NSFW home-only,
  content filter, stealth mode, blur and dim effects, smart crop
- Sources and plugin store, custom stores, install from URL, API keys, Reddit subreddits
- Backups in the Android format, both directions
- Widget (current wallpaper with Previous, Save, Next)

## iPhone differences

- Rotation runs through a Shortcuts automation ("Get Rotato Wallpaper" → Set Wallpaper), since
  iOS apps can't set the wallpaper. "Set now" runs the user's shortcut.
- Stealth mode is a Control Center control (iOS 18) and a Shortcuts action instead of a Quick
  Settings tile.
- Locked collections use Face ID or the passcode.

## Not ported yet

- Taste tab (interest profiles; tag tiers can be set from a tag's menu)
- MyAnimeList integration and the anime collection builder
- Schedules (switch collections on days and times)
- Sharing a collection as a file, automatic daily backups
- Hands-free slideshow in Discover

## Android only

Live wallpaper, the screen saver, Quick Settings tiles, foldable features (fold pairs, fold-aware
crops, unfold triggers), Tasker and Routines actions, notification actions, APK updates.
