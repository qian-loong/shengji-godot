# Claude Code Game Studios -- Game Studio Agent Architecture

Indie game development managed through 49 coordinated Claude Code subagents.
Each agent owns a specific domain, enforcing separation of concerns and quality.

## Technology Stack

- **Engine**: Godot 4.6
- **Language**: GDScript (primary), C++ via GDExtension (performance-critical)
- **Version Control**: Git with trunk-based development
- **Build System**: SCons (engine), Godot Export Templates
- **Asset Pipeline**: Godot Import System + custom resource pipeline

> **Note**: Engine-specialist agents exist for Godot, Unity, and Unreal with
> dedicated sub-specialists. Use the set matching your engine.

## Project Structure

@.claude/docs/directory-structure.md

## Engine Version Reference

@docs/engine-reference/godot/VERSION.md

## Technical Preferences

@.claude/docs/technical-preferences.md

## Coordination Rules

@.claude/docs/coordination-rules.md

## Collaboration Protocol

**User-driven collaboration, not autonomous execution.**
Every task follows: **Question -> Options -> Decision -> Draft -> Approval**

- Agents MUST ask "May I write this to [filepath]?" before using Write/Edit tools when operating under the original project collaboration protocol.
- Agents MUST show drafts or summaries before requesting approval when the task is design-heavy or ambiguous.
- Multi-file changes require explicit approval for the full changeset when not already requested by the user.
- No commits without user instruction.

See `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md` for full protocol and examples.

> **First session?** If the project has no engine configured and no game concept,
> run `/start` to begin the guided onboarding flow.

## Coding Standards

@.claude/docs/coding-standards.md

## Context Management

@.claude/docs/context-management.md

## Android APK Export

Use Godot export preset `Android` from `src/godot/export_presets.cfg`.

Recommended environment variable:

```powershell
$env:GODOT_EXE="path\to\Godot_v4.6.2-stable_win64_console.exe"
```

Debug APK command (real device, Vulkan/mobile renderer):

```powershell
New-Item -ItemType Directory -Force "builds\android" | Out-Null

& $env:GODOT_EXE `
  --headless `
  --path "src\godot" `
  --export-debug "Android" `
  "builds\android\shengji-debug.apk"
```

Emulator UI test APK (temporarily switches mobile renderer to `gl_compatibility`, then restores `project.godot`):

```powershell
.\tools\export_android_emulator.ps1
```

Output: `builds/android/shengji-debug-emulator.apk`

### GUI change verification (required)

After modifying GUI code (`src/godot/scripts/ui/`, scenes, layout, or visual assets used in-game), **export and install on the Android emulator before marking the task done**:

```powershell
$env:GODOT_EXE = "path\to\Godot_v4.6.2-stable_win64_console.exe"
# optional: $env:ADB_EXE = "path\to\platform-tools\adb.exe"

.\tools\verify_ui_emulator.ps1
# optional screenshot to builds/android/qa/
.\tools\verify_ui_emulator.ps1 -Screenshot
```

Use the **emulator** APK (`gl_compatibility`), not the device Vulkan build, for UI checks on PC emulator. Confirm layout on a running AVD (e.g. `Pixel_6_API_36`).

Do not commit generated APKs, `.idsig` files, keystores, or signing secrets.

## Local Machine Notes

If `AGENTS.local.md` exists, read it for local paths and machine-specific build notes.
`AGENTS.local.md` is private local context and must not be committed.
