# Build Guide

## Overview

This document provides instructions for building the game on different platforms.

## Prerequisites

### All Platforms
- Godot 4.3 installed and available in PATH
- Git for version control
- Python 3.x for build scripts

### Android
- Android SDK installed (required for signing and deployment)
- Java Development Kit (JDK) 17 or higher
- Android NDK (if needed for native extensions)
- Godot Android export templates installed

## Platform Builds

### Android

#### Setup

1. **Install Android SDK**
   - Download Android Studio or standalone SDK tools
   - Set `ANDROID_HOME` environment variable
   - Ensure `adb` is available in PATH

2. **Configure Godot Export Template**
   - Open Godot Editor
   - Go to Editor → Manage Export Templates
   - Install Android export templates for Godot 4.3

3. **Generate Debug Keystore** (for development builds)
   ```bash
   keytool -genkey -v -keystore debug.keystore -alias androiddebugkey \
           -keyalg RSA -keysize 2048 -validity 10000 \
           -storepass android -keypass android
   ```

4. **Configure Export Preset**
   - Open project in Godot Editor
   - Project → Export
   - Add Android export preset
   - Configure keystore path and credentials in export preset

#### Build Commands

**Development Build (Debug)**
```bash
python tools/build.py android debug
```
- Output: `builds/android/debug/game-debug.apk`
- Includes debug symbols
- Connects to Godot remote debugger
- Not optimized for performance

**Release Build**
```bash
python tools/build.py android release
```
- Output: `builds/android/release/game-release.apk`
- Optimized for performance
- Requires release keystore for signing
- No debug symbols

**QA Build**
```bash
python tools/build.py android qa
```
- Output: `builds/android/qa/game-qa.apk`
- Debug symbols included
- Performance optimizations enabled
- Best for testing

#### Installation & Testing

1. **Connect Android Device**
   ```bash
   adb devices
   ```

2. **Install APK**
   ```bash
   adb install -r builds/android/qa/game-qa.apk
   ```

3. **Launch Application**
   ```bash
   adb shell am start -n com.gamestudio.game/.GodotApp
   ```

4. **View Logs**
   ```bash
   adb logcat -s godot:*
   ```

5. **Capture Screenshots**
   ```bash
   adb exec-out screencap -p > screenshot.png
   ```

#### QA Verification

After building, run basic QA checks:
- Launch application and verify splash screen
- Test navigation (start game, settings, back button)
- Verify audio/music controls
- Check for crashes or freezes
- Test on multiple Android versions if possible

Screenshots should be saved to `builds/android/qa/` for documentation.

### Windows

#### Build Commands

**Development Build**
```bash
python tools/build.py windows debug
```

**Release Build**
```bash
python tools/build.py windows release
```

### Linux

#### Build Commands

**Development Build**
```bash
python tools/build.py linux debug
```

**Release Build**
```bash
python tools/build.py linux release
```

### macOS

#### Build Commands

**Development Build**
```bash
python tools/build.py macos debug
```

**Release Build**
```bash
python tools/build.py macos release
```

## Build Script Reference

The `tools/build.py` script provides a unified interface for all platform builds.

### Usage
```bash
python tools/build.py <platform> <build_type> [options]
```

### Platforms
- `android` - Android APK
- `windows` - Windows executable
- `linux` - Linux executable
- `macos` - macOS app bundle

### Build Types
- `debug` - Development build with debugging enabled
- `release` - Production build with optimizations
- `qa` - Testing build with debug symbols and optimizations

### Options
- `--clean` - Clean build directory before building
- `--verbose` - Show detailed build output

## Troubleshooting

### Android Build Issues

**Problem: "ANDROID_HOME not set"**
- Solution: Set the `ANDROID_HOME` environment variable to your Android SDK path

**Problem: "adb not found"**
- Solution: Add Android SDK platform-tools to your PATH

**Problem: "Export template not found"**
- Solution: Install Godot Android export templates via Editor → Manage Export Templates

**Problem: Build succeeds but APK won't install**
- Solution: Check that debug keystore is properly configured
- Try uninstalling existing version first: `adb uninstall com.gamestudio.game`

**Problem: App crashes on launch**
- Solution: Check logcat for errors: `adb logcat -s godot:*`
- Verify all required permissions are in AndroidManifest.xml

## CI/CD Integration

The build system is designed to work in CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Build Android
  run: python tools/build.py android release --clean
  
- name: Upload APK
  uses: actions/upload-artifact@v3
  with:
    name: game-android
    path: builds/android/release/*.apk
```

## Version Information

- **Godot Version**: 4.3
- **Minimum Android API**: 21 (Android 5.0)
- **Target Android API**: 34 (Android 14)

## Related Documentation

- [Architecture Decision Records](architecture/) - Technical decisions
- [Engine Reference](engine-reference/godot/) - Godot 4.3 API reference
- [QA Plan](.claude/docs/templates/qa-plan.md) - Testing procedures
