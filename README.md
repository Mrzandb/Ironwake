# Ironwake

2D 俯视硬核甲弹对抗（多炮塔陆行战舰）。Godot **4.7.2 stable** 标准版（GDScript，非 .NET）重写。

模拟层在 `res://sim/`，不依赖场景树，定步长 60 Hz（只使用 `SimClock.DT = 1/60`），随机只走带种子的 sfc32 / splitmix32。表现、输入和 HUD 在 `res://game/`。

## 命令

Linux / CI（二进制见 `AGENTS.md`）：

```bash
godot --version
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tools/bench.gd
```

Windows 使用 `godot_console`，见 `AGENTS.md`。

## 目录

| 路径 | 内容 |
|---|---|
| `res://sim/` | 纯 `RefCounted` 模拟。禁止 Node、引擎物理、非种子随机 |
| `res://data/` | 静态 JSON。数值冻结在 Game_test@33f4be8，由 `tools/bake_data.mjs` 烘焙 |
| `res://sim/data/` | 数据加载（纯 `RefCounted`，不依赖场景） |
| `res://game/` | 场景、视图、输入、帧时间累加 |
| `res://tests/` | 无头测试入口 `run_tests.gd` |
| `res://tools/` | 基准 `bench.gd`（空世界，以及 6 辆车在丘陵上的移动） |
