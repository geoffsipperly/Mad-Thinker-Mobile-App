---
description: Build the app on the iPhone 17 Pro simulator using the SkeenaSystem scheme
---

Build the workspace and report any errors.

Run this command:

```bash
xcodebuild -workspace SkeenaSystem.xcworkspace \
  -scheme SkeenaSystem \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

Note: `SkeenaSystem` is the scheme, `DevTEST` is a build configuration that the scheme already selects. Do NOT pass `-scheme DevTEST` — xcodebuild will fail.

If the build fails:
1. Surface the first error (not the last — later errors are usually cascades).
2. If it's a CocoaPods / MediaPipe link error, check whether `libz.tbd` is still on both the SkeenaSystem and SkeenaSystemTests targets (see `.claude/CLAUDE.md` rules).
3. Do not attempt to "fix" warnings unless the user asks.

$ARGUMENTS
