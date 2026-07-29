# Source Directory

When writing or editing game code in this directory, follow these standards.

## Engine Version Warning

The LLM's training data predates the pinned engine version.
**Always check `docs/engine-reference/` before using any engine API.**
Do not guess at post-cutoff API signatures — look them up first.

## Coding Standards

- All public APIs require doc comments
- Gameplay values must be **data-driven** (external config files), never hardcoded
- Prefer dependency injection over singletons for testability
- Every new system needs a corresponding ADR in `docs/architecture/`
- Commits must reference the relevant story ID or design document

## File Routing

Match the engine-specialist agent to the file type being written.
See `CLAUDE.md` → Technical Preferences → Engine Specialists → File Extension Routing.

When in doubt, use the primary engine specialist configured in `CLAUDE.md`.

## Tests

**本项目的测试位于 `src/godot/tests/`**，不是仓库根的 `tests/`。

原因：GUT 通过 `-gdir=res://tests` 收集测试，而 `res://` 就是 Godot 项目根
（`src/godot/`）。放在仓库根 `tests/` 下的文件在 `res://` 之外，**GUT 根本
加载不到**——曾有两份 32 个用例的测试因此静默失效数月，期间实现偏离 GDD 也无人察觉。

```bash
cd src/godot
$GODOT_EXE --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

命名 `test_*.gd`。完整规范见 `.claude/docs/coding-standards.md`。
Every gameplay system should have unit tests covering its formulas and edge cases.

## Verification-Driven Development

Write tests first when adding gameplay systems.
For UI changes, verify with screenshots.
Compare expected output to actual output before marking work complete.
