# AGENTS.md — Ironwake

> 项目：基于 Godot 引擎的完整版重置。本文件记录**本机已配置好的开发环境**与**已验证的命令/坑**。
> 写作日期 2026-11-12。文中标「实测」的结论都在本机跑过并核对了退出码；标「未验证」的请自己先验证再依赖。
> 2026-11-12 另有一组 **Linux VM** 实测（Godot 4.7.2 同一官方构建），见第 4 节后半与第 9 节。Windows 条目仍然有效。

## 1. 引擎环境事实

| 项 | 值 |
|---|---|
| 引擎版本 | **Godot 4.7.2 stable official**（commit `ed1daf0bf`） |
| 发行版类型 | **标准版（GDScript）**，不是 .NET/Mono 版 —— 见第 4 节第 5 条 |
| 安装方式 | `winget`（包 id `GodotEngine.GodotEngine`），**已 pin 在 4.7.2** |
| GUI 可执行文件 | `C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe` |
| 控制台可执行文件 | 同目录 `Godot_v4.7.2-stable_win64_console.exe` |
| 命令入口（符号链接） | `%LOCALAPPDATA%\Microsoft\WinGet\Links\godot.exe` → GUI 版<br>`%LOCALAPPDATA%\Microsoft\WinGet\Links\godot_console.exe` → 控制台版 |
| PATH | 已写入**用户级** PATH（`WinGet\Links`）；**机器级 PATH 没有** |
| 显卡 / 渲染 | RTX 4070 Laptop GPU，`Vulkan 1.3.289 - Forward+`（实测） |
| 无头模式 | `--headless` 可用；此时 `RenderingServer.get_video_adapter_name()` 返回空字符串，**属正常** |
| 导出模板 | **未安装**（`%APPDATA%\Godot\export_templates` 为空）→ 现在无法导出可执行文件 |
| 编辑器配置 | `%APPDATA%\Godot\editor_settings-4.7.tres`；用户数据 `%APPDATA%\Godot\app_userdata\` |
| 项目目录 | `C:\Users\Administrator\Desktop\Ironwake`（交接时**只有本文件**，项目骨架未建、无 git 仓库） |
| 系统 | Windows 11 专业版 26200；磁盘剩余约 108 GB |

引擎升级是**被 pin 住**的：`winget upgrade --all` 不会动 Godot。要升版本需先 `winget pin remove --id GodotEngine.GodotEngine`。

2026-11-12 起 git 仓库里已经有 Godot 骨架（不再是空目录）。Windows 本机路径仍以表中「项目目录」为准。

## 2. 开工前自检（30 秒，先跑这个）

```powershell
# 关键：从已存在的进程（IDE/上一次会话）继承来的 PATH 里没有 godot，先刷新
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')

godot_console --version          # 期望输出 4.7.2.stable.official.ed1daf0bf
```

如果 `godot_console` 仍然「不是内部或外部命令」，直接用绝对路径（第 1 节表格里的控制台可执行文件路径），不要折腾环境。

Linux / CI 没有 `godot_console` 这个名字，用第 9 节的二进制。

## 3. 命令配方（均已实测，退出码已核对）

### 3.1 铁律：要读输出就用 `godot_console`，不要用 `godot`

`godot.exe` 是 **GUI 子系统**程序，stdout 不同步：实测 `godot --version` 的输出会**跑到下一条命令的输出之后**，管道里可能整段丢失。凡是需要读输出、拿退出码、进 CI 的场合，一律 `godot_console`。要开编辑器窗口用 `godot`。

这条是 **Windows** 的。Linux 官方包只有一个二进制，stdout 是同步的（第 9 节）。

| 目的 | 命令 | 实测结果 |
|---|---|---|
| 查版本 | `godot_console --version` | `4.7.2.stable.official.ed1daf0bf`，exit 0 |
| 打开编辑器（GUI） | `godot --editor --path .` | 窗口常驻（实测：进程存活 12s+，标题 `Godot Engine (Console)`、Vulkan Forward+） |
| 跑游戏（有窗口） | `godot --path .` ← **注意这不是开编辑器** | `Vulkan 1.3.289 - Forward+` |
| 编辑器冒烟（无交互） | `godot_console --editor --path . --quit` | 正常启动并退出，exit 0（⚠️ 见 3.4：真出错时**也返回 0**） |
| 无头跑主场景 | `godot_console --headless --path .` | 无 GPU，主场景需自己 `get_tree().quit()` |
| 无头固定帧数运行 | `godot_console --headless --path . --quit-after 10` | 跑满 10 帧自动退出，exit 0 |
| 确定性帧步长 | `godot_console --headless --path . --fixed-fps 60` | `get_process_delta_time()` == `0.0166666667`（精确 1/60） |
| 跑测试脚本 | 见 3.2 | exit 0 / exit 1 |

> `--fixed-fps 60` 是确定性模拟的地基：不加它，无头模式会全速跑（实测 `proc_delta ≈ 0.0033`，即约 300 fps），同一份逻辑两次跑出的结果不一致。
>
> 模拟层自己不读帧时间，只认 `SimClock.DT`（`1.0/60.0`）。表现层用 `game/fixed_step.gd` 把帧间隔收成 tick 数。回放时仍然加上 `--fixed-fps 60`。

### 3.2 无头测试脚本（推荐的 CI 形态，已实测）

测试入口脚本**必须 `extends SceneTree`（或 `MainLoop`）**，用 `_initialize()`：

```gdscript
# res://tests/run_tests.gd
extends SceneTree

func _initialize() -> void:
	var failed := 0
	# ... 你的断言，例如 SimTest.check_eq(...) 
	print("TESTS: %d failed" % failed)
	quit(0 if failed == 0 else 1)
```

```powershell
godot_console --headless --path . --script res://tests/run_tests.gd
$LASTEXITCODE   # 0 = 全通过，1 = 有失败（可直接当 CI 闸门）
```

实测：`quit(0)` → exit 0；`quit(1)` → exit 1。
实测：若脚本 `extends Node`，会报 `Can't load the script ... as it doesn't inherit from SceneTree or MainLoop.` 并 exit 1。

基准（空世界步进，不是战斗性能）：

```powershell
godot_console --headless --path . --script res://tools/bench.gd
```

### 3.3 关于 stderr 的红字

`push_error()` 等写 stderr 的内容在 PowerShell 里会显示成红色的 `NativeCommandError`，**看着像崩溃其实只是 stderr**。判断成败永远看 `$LASTEXITCODE`。想让日志干净，用 cmd 包一层：

```powershell
cmd /c "godot_console --headless --path . --script res://tests/run_tests.gd 2>&1"
```

### 3.4 退出码不可全信：编辑器模式下出错仍返回 0

实测：`.tscn` 有解析错误时，`godot_console --editor --path . --quit` **依然 exit 0**，错误只出现在 stderr。所以「编辑器冒烟通过」不能只看退出码，要同时扫日志：

```powershell
$out = godot_console --editor --path . --quit 2>&1 | Out-String
if ($out -match 'Parse Error|ERROR:|SCRIPT ERROR') { throw "Godot 报错了:`n$out" }
```

`--script` 测试脚本走的是 `quit(1)`，退出码是可靠的（见 3.2）；**场景/资源的加载错误要靠扫日志**。

## 4. 已知坑（按踩到概率排序）

1. **`godot` 读不到输出** —— 见 3.1。这是最容易浪费半小时的一条。

2. **PATH 只在用户级，且已运行的进程不会刷新** —— 新开的终端能直接 `godot`；但本会话、已打开的 VS Code / 终端 / IDE 里的子进程看不到，必须重启进程或用绝对路径。别把「命令找不到」误判成「没装」。

3. **UTF-8 BOM 会让编辑器解析场景失败** —— `.tscn` / `.tres` 若带 BOM（`EF BB BF`），编辑器报 `Parse Error: Expected '['`。
   - 更阴的是：**同一个带 BOM 的 `.tscn`，`--headless` 跑游戏反而能读**（实测），于是「命令行能跑、编辑器打不开」，极易误判成编辑器坏了。
   - 而且这种情况下**编辑器仍 exit 0**，只有 stderr 里有 `Parse Error: Expected '['`（实测）——见 3.4。
   - 生成文本资源一律无 BOM：
     ```powershell
     [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
     ```
     （Windows PowerShell 5.1 的 `Set-Content -Encoding utf8` **会加 BOM**；PowerShell 7 用 `-Encoding utf8NoBOM`。）

4. **版本被 pin** —— 见第 1 节。反过来，如果引擎行为「莫名没变化」，先确认是不是 pin 在旧版本。

5. **这是标准版，不是 .NET 版** —— 本机虽装了 .NET SDK 10.0.401，但 Godot 是 GDScript 版，**写 C# 脚本不可用**。要 C# 必须另装 `GodotEngine.GodotEngine.Mono` 并重建项目语言栈。

6. **导出模板缺失** —— 一旦要打包会报 `No export template found`。装法：编辑器 *Editor → Manage Export Templates → Download and Install*，或把官方 `Godot_v4.7.2-stable_export_templates.tpz`（约 1.2 GB）解到 `%APPDATA%\Godot\export_templates\4.7.2.stable\`。

7. **`.godot/` 是导入缓存** —— 编辑器打开项目、或项目里有需导入的资源（png/ttf/ogg…）时生成，**必须 gitignore**。实测：纯脚本项目用 `--headless` 跑不会生成它，别以为项目坏了。`.gitignore` 至少要有：
   ```gitignore
   # Godot 4
   .godot/
   ```
   补充（Linux，2026-11-12 实测）：`--headless --editor --quit` **会**生成 `.godot/`，同时在每个 `.gd` 旁边写出 `.uid`。`.uid` 要提交，`.godot/` 不要。见第 18 条。

8. **手写 `.tscn` 的 `uid://`** —— Godot 4 用 uid 引用资源，uid 写错或乱编会导致解析失败。手写场景时干脆不写 `uid` 属性，交给编辑器补；跨文件引用优先用 `path=` 形式。

9. **首次启动慢** —— 首次启动要做渲染初始化 + 173 MB exe 被杀软扫描，可能卡十几秒，别当死机杀掉。

10. **多 GPU** —— 本机同时有 Intel UHD 和 RTX 4070，实测默认选中 `Device #0: NVIDIA`。若换机器后落到核显，用 `--rendering-driver vulkan` 或项目设置里指定适配器，别改业务代码。

11. **项目要新建，`config_version=5`** —— Godot 4.x 的 `project.godot` 格式。实测可用的最小项目：
    ```ini
    config_version=5

    [application]

    config/name="Ironwake"
    run/main_scene="res://scenes/main.tscn"
    config/features=PackedStringArray("4.7")
    ```
    当前仓库主场景是 `res://game/main.tscn`（场景放在 `game/`，不放在 `scenes/`）。

12. **Linux 没有单独的 console exe**（2026-11-12 实测）
    - 现象：Windows 必须用 `godot_console` 才能读到 stdout。Linux 官方 zip 里只有 `Godot_v4.7.2-stable_linux.x86_64`。
    - 根因：GUI 子系统丢 stdout 是 Windows 的事。
    - 做法：Linux / CI 直接跑这个二进制。`--version` 立即打印 `4.7.2.stable.official.ed1daf0bf`，exit 0。下载在 `godotengine/godot-builds` 的 tag `4.7.2-stable`，文件 `Godot_v4.7.2-stable_linux.x86_64.zip`（SHA512 写在 `.github/workflows/tests.yml`）。`godotengine/godot` 的 release 附件里没有这个 zip。
    - `Engine.get_version_info().hash` 是完整提交 `ed1daf0bf001b61586d9930840f2f1394092c079`。`--version` 只显示前 9 位 `ed1daf0bf`。是同一个构建。

13. **没有显示器时的编辑器冒烟**（2026-11-12 实测）
    - 现象：Linux VM 没有桌面，不能照搬 Windows 的 `godot_console --editor --path . --quit`。
    - 做法：`godot --headless --editor --path . --quit`。本次 exit 0，日志里没有 `Parse Error`、`ERROR:`、`SCRIPT ERROR`。退出码仍然不能单独当通过（见 3.4），要扫日志。

14. **`--script` 在 `quit()` 之前出错会卡死**（2026-11-12 实测）
    - 现象：`_initialize()` 里一次调用失败、没执行到 `quit()` 时，进程不退出，空转超过 10 分钟，也没有非 0 退出码。
    - 根因：这是 SceneTree 主循环，脚本错误不会替你结束进程。
    - 做法：`tests/run_tests.gd` 在 `_process` 里检查；测试没跑完就 `quit(1)`。别假设报错会自己退出。

15. **干净树上，跨文件 `class_name` 类型标注会解析失败**（2026-11-12 实测）
    - 现象：还没有 `.godot/global_script_class_cache.cfg` 时，`--headless --script` 报 `Could not find type "Rng"`，调用方再报 `Could not resolve external class member`。
    - 根因：全局类缓存要等编辑器扫描才写入，而 `.godot/` 不进 git。只跑 `--script` 时，别的文件的 `class_name` 还不能当类型用。
    - 做法：sim 之间用 `preload`。变量和返回值不要标注另一个脚本的 `class_name`。`class_name` 本身留着，编辑器扫描后会注册（本次注册了 `SimRng`、`Sfc32`、`SimWorld` 等）。
    - 另一条同类解析错误：`var rng := from_words(...)` 在返回值没有静态类型时会 `Cannot infer the type`。这种地方写成 `var rng = from_words(...)`。

16. **64 位乘法的打印值不是 `Math.imul`**（2026-11-12 实测）
    - 现象：`0xFFFFFFFF * 0xFFFFFFFF` 打印 `-8589934591`，不是 JS `Math.imul` 的 `1`。
    - 根因：GDScript `int` 是有符号 64 位，乘积超出 `2^63-1` 后按 2^64 环绕。再 `& 0xFFFFFFFF` 时，4.7.2 上低 32 位仍然是 `1`，和 `Math.imul` 一致。
    - 做法：`sim/bits.gd` 把乘法拆成 16 位，不依赖有符号溢出。对结果看 `tests/rng_test.gd` 的黄金向量，不要拿十进制乘积去对 JS。

17. **这个环境读不到 `Game_test`**（2026-11-12 实测）
    - 现象：`gh api repos/Mrzandb/Game_test` 和 `git ls-remote https://github.com/Mrzandb/Game_test.git` 都是 404。
    - 根因：仓库是私有的，当前凭证访问不到。提交 `33f4be8` 的 `src/core/rng.ts` 和 `tests/unit/rng.test.ts` 都没读到。
    - 做法：RNG 按公开的 sfc32 与改进版 splitmix32（`Math.imul` 常量 `0x21f0aaad` / `0x735a2d97`）实现，播种和 `spread` / `ai` / `map` 分流写在 `sim/rng.gd` 文件头。移植射击、散布数值之前，用原型测试向量对一下。对不上就改 `sim/rng.gd` 和黄金向量，不要在玩法里打补丁。

18. **`.uid` 要提交**（2026-11-12 实测）
    - 现象：`godot --headless --editor --path . --quit` 在每个 `.gd` 旁生成一行 `uid://...` 的 `.uid`，并创建 `.godot/`。手写的 `game/main.tscn` 没有被改写，里面仍然只有 `path=`。
    - 做法：提交 `.uid`，继续 gitignore `.godot/`。手写场景仍然不要自己编 `uid` 属性（第 8 条）。

## 5. 本机其它可用工具（均已核对）

- .NET SDK `10.0.401`（当前用不上：标准版 Godot 不支持 C#）
- Python `3.13.14` 可用（走 WindowsApps 别名，`python.exe` 显示为 0 字节存根但实际能跑）
- Node.js `v26.13.0`（若要做数据表生成 / 工具链脚本）
- Git、VS Code 均已安装，`code` 在 PATH
- VS Code 已装 7 个扩展：`anthropic.claude-code`、Python 三件套（`ms-python.*`）、中文语言包、wordcount
- **没有** Godot / GDScript 的 VS Code 扩展，也没有任何 MCP 桥接插件（若希望 VS Code 里补全 GDScript，需自行装 `geequlim.godot-tools`）

## 6. 接手清单

- [x] 建项目骨架：`project.godot`（主场景 `res://game/main.tscn`）、`sim/` `data/` `game/` `tests/` `tools/`、`.gitignore`、`.editorconfig`、`.gitattributes`（2026-11-12）
- [x] 定分层并写进本文件：第 10 节
- [x] 定确定性基线：`SimClock.DT` + 具名种子 RNG；同种子哈希在 `tests/determinism_test.gd`（2026-11-12 实测 exit 0）
- [ ] 装导出模板（等要打包时）
- [ ] 视觉基线（玩法还没移植）

## 7. 与前作（TypeScript + PixiJS 版）的关系

上一代工程在 `C:\Users\Administrator\Desktop\Game`，设计依据：`docs/设计文档.md`（v2.6/v1.8）、`docs/射击与损伤机制_v2.md`、`docs/技术架构.md`、`docs/规则空白清单.md`。上一代有 188 项测试与数值批跑报告，**规则逻辑和数值可复用，代码不可直接移植**（TS → GDScript 重写）。文档与代码矛盾时以 Game_test@33f4be8 代码为准；未实现部分按设计文档。

数值冻结在 `33f4be8`。未开工的 EMP 玩法、长枪、铁砧、雷等，暂按原设计文档。不追求和 JS 原型录像哈希逐字节一致，只要求同一 Godot 构建、同一种子、同一输入得到同一结果。

几何约定与 Game_test@33f4be8、Godot 2D 屏幕坐标一致：**+X 向右、+Y 向下、0 弧度朝右、顺时针为正角**。`SimAngle.direction(PI/2)` 是 `(0, 1)`（向下）；负角朝上。`SimVec.rotated` 用 `x' = x cos - y sin`、`y' = x sin + y cos`，正叉积表示第二向量在第一向量的顺时针侧。这套约定锁在 `tests/math_test.gd`（含屏幕坐标参考哈希）。RNG 黄金向量这次没有改，仍等能读到原型 `rng.ts` 再对。

## 8. 维护本文件

新增坑或命令时，标明「实测 / 未验证」与日期；一条坑至少写清：现象、根因、正确做法。别把猜测写成结论。

## 9. Linux 与 CI（2026-11-12 实测）

二进制：`Godot_v4.7.2-stable_linux.x86_64`（标准版，不是 mono）。版本字符串与 Windows 相同。

```bash
godot --version
# 4.7.2.stable.official.ed1daf0bf

godot --headless --path . --script res://tests/run_tests.gd
echo $?    # 0 通过，1 失败

godot --headless --path . --script res://tools/bench.gd

# 编辑器冒烟。无桌面时必须带 --headless。退出码不够，还要扫日志。
godot --headless --editor --path . --quit

# 主场景占位。无头时 main.gd 自己 quit，exit 0。
godot --headless --path .
```

2026-11-12 这台 Linux VM 上，空 `SimWorld.step` 20000 tick（先热身 1000），三次约 **0.098–0.108 微秒/tick**（大约每秒 900 万到 1000 万次空步进）。这只是空循环基线。战斗逻辑进来之后用同一条命令重测，不要拿这个数当战斗性能。

GitHub Actions：`.github/workflows/tests.yml`，在 `ubuntu-latest` 上下载同一 zip、核对 SHA512、跑上面的测试脚本。

## 10. 分层铁律

| 目录 | 放什么 |
|---|---|
| `res://sim/` | 纯 `RefCounted`。战斗、移动、RNG、定步长时钟。可以无头、可以快进、可以多开 |
| `res://data/` | 静态表。本步只有占位 |
| `res://game/` | Node、场景、视图、输入、HUD、帧时间累加（`FixedStepDriver`） |
| `res://tests/` | `extends SceneTree` 的测试入口和套件 |
| `res://tools/` | 基准。计时可以用 `Time`，因为不在 sim 里 |

- `sim/` 和 `data/` **不得** `preload` / `load` `res://game/`，不得 `extends Node`（含 Node2D 等），不得用物理服务器做判定（`PhysicsServer`、`move_and_slide`）。
- 模拟层禁止 `randf()` / `randi()` / `randfn()` / `randomize()` / `RandomNumberGenerator`，也禁止读 `Time` 或 `OS.get_*` 当随机或时钟。随机只走 `sim/rng.gd`。时间只走 `SimClock.DT`（60 Hz，`1.0/60.0`），`step()` 不接收帧间隔。
- 不要 Autoload，不要把世界放进进程全局变量。训练时一个进程里 `SimWorld.new(seed)` 多份；`duplicate()` 复制 tick 和已创建的 RNG 流。
- 表现层可以把真实帧时间交给 `FixedStepDriver.consume()`，再调用相应次数的 `world.step()`。模拟结果不得依赖调用 `step()` 时的墙钟。
- `tests/layer_test.gd` 会扫 `sim/` 里的这些禁令，并检查文本资源没有 BOM、没有 CR。
- 坐标是屏幕坐标：+X 向右、+Y 向下、0 弧度朝右、顺时针为正。详见第 7 节。表现层不要再把 Y 翻一次。

局内经济（本步不实现）：战斗结算以后由 sim 广播事件；属性修正集中走 StatResolver，修正来源包括装备、改装和局内状态；换车前由经济层检查费用，sim 不直接扣钱。

RNG 约定（未对照原型，见第 17 条）：改进版 splitmix32 把一个种子展开成 sfc32 的四个状态字，再丢掉 12 个输出（PractRand 的 64 位播种也是丢 12 个）。`spread`、`ai`、`map` 由「名字的 FNV-1a 异或根种子，再取一次 splitmix32」各自派生，互不消耗。黄金向量在 `tests/rng_test.gd`，同种子 1000 tick 的序列哈希在 `tests/determinism_test.gd`。
