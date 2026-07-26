# Audio System — 音频系统设计

**状态**: 📋 Planned (延后至 Polish 阶段)  
**优先级**: Medium  
**依赖**: 无  
**实现阶段**: Polish (M4+)

---

## 1. Overview

音频系统为游戏提供背景音乐、音效反馈和氛围营造。本系统采用分层架构，支持独立的音乐/音效音量控制、配置持久化和跨场景播放。

**设计原则**:
- 音乐和音效分离控制
- 配置持久化（用户偏好保存）
- 跨场景无缝播放（autoload 单例）
- 资源延迟加载（按需加载，减少启动时间）

---

## 2. Player Fantasy

玩家期望：
- 舒缓的背景音乐营造休闲氛围
- 出牌/得分时有清晰的音效反馈
- 可以独立控制音乐/音效音量或静音
- 设置在游戏重启后保持

---

## 3. Detailed Rules

### 3.1 音频分类

| 类型 | 用途 | 音频格式 | 循环播放 |
|------|------|----------|----------|
| **背景音乐 (BGM)** | 主菜单、对局中的氛围音乐 | .ogg (Vorbis) | ✅ 循环 |
| **UI 音效 (SFX)** | 按钮点击、选项切换 | .wav (短音效) | ❌ 单次 |
| **游戏音效 (SFX)** | 发牌、出牌、得分、结算 | .wav (短音效) | ❌ 单次 |

### 3.2 音频资源规划

```
src/godot/audio/
├── bgm/
│   ├── menu_theme.ogg        # 主菜单背景音乐 (1-2 分钟循环)
│   └── game_theme.ogg         # 对局中背景音乐 (2-3 分钟循环)
├── sfx/
│   ├── ui_click.wav           # 按钮点击音效
│   ├── ui_toggle.wav          # 开关切换音效
│   ├── card_deal.wav          # 发牌音效
│   ├── card_play.wav          # 出牌音效
│   ├── trick_win.wav          # 赢墩音效
│   └── score_gain.wav         # 得分音效
└── .gitkeep
```

**资源要求**:
- BGM: 采样率 44.1kHz，立体声，Ogg Vorbis 编码（文件大小 < 3MB）
- SFX: 采样率 22.05kHz，单声道，WAV 格式（文件大小 < 100KB）
- 总音频资源预算: < 10MB

### 3.3 音频管理器 (Autoload)

```gdscript
# src/godot/autoload/audio_manager.gd
extends Node

var bgm_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer

var music_enabled: bool = true
var sfx_enabled: bool = true
var music_volume: float = 0.7  # 0.0 - 1.0
var sfx_volume: float = 0.8

func _ready() -> void:
	_setup_players()
	_load_settings()

func play_bgm(stream: AudioStream) -> void:
	if not music_enabled:
		return
	bgm_player.stream = stream
	bgm_player.play()

func play_sfx(stream: AudioStream) -> void:
	if not sfx_enabled:
		return
	sfx_player.stream = stream
	sfx_player.play()

func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	if not enabled:
		bgm_player.stop()
	_save_settings()

func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled
	_save_settings()
```

### 3.4 配置持久化

使用 `ConfigFile` 保存用户偏好:

```gdscript
func _save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("audio", "music_enabled", music_enabled)
	config.set_value("audio", "sfx_enabled", sfx_enabled)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.save("user://audio_settings.cfg")

func _load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load("user://audio_settings.cfg")
	if err != OK:
		return  # 使用默认值
	music_enabled = config.get_value("audio", "music_enabled", true)
	sfx_enabled = config.get_value("audio", "sfx_enabled", true)
	music_volume = config.get_value("audio", "music_volume", 0.7)
	sfx_volume = config.get_value("audio", "sfx_volume", 0.8)
```

---

## 4. Formulas

### 4.1 音量转换 (线性 → dB)

Godot 的 `volume_db` 使用分贝单位，需要从线性音量 (0.0-1.0) 转换:

```gdscript
func linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0  # 静音
	return 20.0 * log(linear) / log(10.0)

# 使用示例:
bgm_player.volume_db = linear_to_db(music_volume)
```

---

## 5. Edge Cases

| 场景 | 处理方式 |
|------|----------|
| **音频文件缺失** | 静默失败（不播放，不报错），记录警告日志 |
| **跨场景切换** | BGM 持续播放（autoload 单例），不重新开始 |
| **同时播放多个 SFX** | 使用多个 `AudioStreamPlayer` 节点池（最多 8 个并发） |
| **用户在播放中切换音乐开关** | 立即生效（停止播放或恢复播放） |
| **音频资源未加载完成** | 使用 `preload()` 预加载常用音效，BGM 按需加载 |

---

## 6. Dependencies

- **无 GDD 依赖** — 独立系统
- **技术依赖**:
  - Godot `AudioStreamPlayer` 节点
  - `ConfigFile` API（配置持久化）
  - Autoload 单例机制

---

## 7. Tuning Knobs

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `music_enabled` | `true` | 背景音乐开关 |
| `sfx_enabled` | `true` | 音效开关 |
| `music_volume` | `0.7` | 音乐音量 (0.0-1.0) |
| `sfx_volume` | `0.8` | 音效音量 (0.0-1.0) |
| `bgm_fade_duration` | `1.0` | BGM 淡入淡出时长（秒） |
| `max_concurrent_sfx` | `8` | 最大并发音效数 |

---

## 8. Acceptance Criteria

- [ ] `AudioManager` autoload 正确加载并跨场景持久化
- [ ] 主菜单和对局中分别播放不同的 BGM
- [ ] 出牌/得分等操作有对应音效反馈
- [ ] 设置界面的音乐/音效开关可以控制播放
- [ ] 音频配置在游戏重启后正确恢复
- [ ] 音频资源总大小 < 10MB
- [ ] 音频播放不影响帧率（< 0.5ms CPU 开销）

---

## 9. Implementation Notes

### 9.1 当前状态 (Sprint 3)

- ✅ 主菜单"设置"中已有音乐开关 UI 占位符
- ❌ 无实际音频播放逻辑
- ❌ 项目中无音频资源文件

### 9.2 实现顺序 (Polish 阶段)

1. **资源准备** (0.5d)
   - 获取/制作 2 首 BGM（Creative Commons 或自制）
   - 获取/制作 6 个 SFX 音效
   - 导入到 `src/godot/audio/` 并验证格式

2. **AudioManager 实现** (0.5d)
   - 创建 autoload 单例
   - 实现 BGM/SFX 播放逻辑
   - 实现配置持久化

3. **UI 集成** (0.5d)
   - 连接主菜单音乐开关到 `AudioManager`
   - 在对局场景中添加音效触发点
   - 测试跨场景播放

4. **测试和优化** (0.5d)
   - 验证音频配置持久化
   - 性能测试（CPU/内存占用）
   - 音量平衡调整

**总预估**: 2 天

---

## 10. Open Questions

| # | 问题 | 优先级 | 建议 |
|---|------|--------|------|
| Q1 | 是否需要音效音量滑块？还是只提供开/关？ | 低 | 先实现开/关，滑块可在后续迭代添加 |
| Q2 | 是否需要独立的"主音量"控制？ | 低 | 不需要，音乐/音效独立控制已足够 |
| Q3 | 音频资源来源？自制还是购买/使用免费资源？ | 高 | 建议使用 Creative Commons 资源（如 freesound.org）降低成本 |

---

## 11. Related Documents

- **实现**: 延后至 Sprint 4+ (Polish 阶段)
- **测试**: 无需自动化测试，手动验证即可
- **ADR**: 待创建 `docs/architecture/adr-008-audio-system.md`
