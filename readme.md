
# SkeenaSystem — Developer Setup

## Prerequisites

- macOS with Xcode installed
- CocoaPods (`brew install cocoapods` or `sudo gem install cocoapods`)
- Git LFS (`brew install git-lfs && git lfs install`)

## Clone and Build

```bash
git clone <repo-url>
cd Mad-Thinker-Mobile-App
pod install
open SkeenaSystem.xcworkspace
```

**Open `.xcworkspace`, not `.xcodeproj`.** The xcodeproj will fail — it doesn't include CocoaPods dependencies.

## First Build

1. Set signing: SkeenaSystem target → Signing & Capabilities → select your development team
2. Select an iOS simulator
3. Cmd+B to build

## Known Issues

- **"Media" folder reference:** The project navigator may contain a red "Media" folder reference. This is a stale entry — the folder was never committed. Right-click → Delete to remove it. Does not affect the build.
- **MediaPipe on Apple Silicon:** If you hit MediaPipe build errors, comment out MediaPipe in the `Podfile`, run `pod install`, and rebuild. The codebase handles its absence via `#if canImport(MediaPipeTasksVision)`.
- **Secrets.xcconfig:** If the build complains about a missing `Secrets.xcconfig`, create `Config/Secrets.xcconfig` with:
  ```
  MAPBOX_ACCESS_TOKEN = <ask team for token>
  ```

## Dependencies

This project uses both CocoaPods and Swift Package Manager. SPM dependencies resolve automatically in Xcode. CocoaPods dependencies require `pod install` after cloning.

## Environment

- DevTEST config: `Config/DevTEST.xcconfig`
- Supabase project and credentials are set in the xcconfig files
