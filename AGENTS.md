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

17. **云端代理无法直接访问 `Game_test`**（2026-11-12 实测）
    - 现象：`gh api repos/Mrzandb/Game_test`、`gh api repos/Mrzandb/Game_test/commits/33f4be8`、`git ls-remote https://github.com/Mrzandb/Game_test.git HEAD`、以及 `git clone` 到 `/tmp/game_test_probe` 都是 404 / `Repository not found`。给 Cursor GitHub App 开过权限之后仍然如此。
    - 根因：云端用的是 GitHub App 安装令牌。看不到这个私有仓库时，GitHub 返回 404，而不是 403。
    - 做法：云端不要反复 clone。原型源码以附件快照提供（`Game_test@33f4be8b19df7fe4137550e1da8ee38bf41aa94e`，139 个文本文件，字节与 git blob 一致；不含 lockfile 和图片）。快照解到工作区外的临时目录，不要提交进本仓库。已按该快照对齐 RNG 播种（splitmix32 四个状态字，不丢弃预热输出）、分流（`seed ^ 0x5f3759df` / `0x1b873593` / `0x27d4eb2f`）、`wrapAngle` 的 `[-π, π)`，以及定步长单帧封顶 0.25 秒。

18. **`.uid` 要提交**（2026-11-12 实测）
    - 现象：`godot --headless --editor --path . --quit` 在每个 `.gd` 旁生成一行 `uid://...` 的 `.uid`，并创建 `.godot/`。手写的 `game/main.tscn` 没有被改写，里面仍然只有 `path=`。
    - 做法：提交 `.uid`，继续 gitignore `.godot/`。手写场景仍然不要自己编 `uid` 属性（第 8 条）。

19. **JSON 数字全是 float，`Vector2` 会丢掉烘焙精度**（2026-11-12 实测）
    - 现象：`JSON.parse_string` 读到的 `8`，`typeof` 是 float 不是 int。蜂群动力舱六角顶点的 y 是 `-9.000000000000002`；放进 `Vector2` 再读出来，和这个值不相等。`tests/data_test.gd` 锁着这两件事。
    - 根因：Godot 4.7.2 把 JSON 数字一律解析成 64 位 float。`Vector2` 的分量是 32 位。原型多边形来自 JS `Math.sin` / `Math.cos`，差一截就和快照对不上。
    - 做法：点保持 `{x, y}` 字典。`DataSchema.px` / `py` 只做 `float()`。用 `.size()` 算出来的个数是 int，和 JSON 叶子比 `typeof` 时先转成 float。`==` 对 int 和 float 仍然成立，不要拿 `typeof` 当数值相等。

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
- [x] 数据层：`Game_test@33f4be8` 的 `src/data/` 烘焙成 JSON，由 `sim/data/` 加载（2026-11-12，无头测试 1051 通过、0 失败）
- [x] 战斗：穿深、模块状态、武器、导弹、属性修正、最小战斗驱动（2026-11-13，见第 14 节）
- [x] 世界循环、对局、回放、AI（2026-11-13，见第 15 节）。`SimFight.step` 仍是唯一战斗步进
- [ ] 装导出模板（等要打包时）
- [ ] 视觉基线（玩法还没移植）

## 7. 与前作（TypeScript + PixiJS 版）的关系

上一代工程在 `C:\Users\Administrator\Desktop\Game`，设计依据：`docs/设计文档.md`（v2.6/v1.8）、`docs/射击与损伤机制_v2.md`、`docs/技术架构.md`、`docs/规则空白清单.md`。上一代有 188 项测试与数值批跑报告，**规则逻辑和数值可复用，代码不可直接移植**（TS → GDScript 重写）。文档与代码矛盾时以 Game_test@33f4be8 代码为准；未实现部分按设计文档。

数值冻结在 `33f4be8`。未开工的 EMP 玩法、长枪、铁砧、雷等，暂按原设计文档。不追求和 JS 原型录像哈希逐字节一致，只要求同一 Godot 构建、同一种子、同一输入得到同一结果。数据表的烘焙和加载见第 11 节。

几何约定与 Game_test@33f4be8、Godot 2D 屏幕坐标一致：**+X 向右、+Y 向下、0 弧度朝右、顺时针为正角**。`SimAngle.direction(PI/2)` 是 `(0, 1)`（向下）；负角朝上。`wrap_signed` 与原型 `wrapAngle` 一样落到 **[-π, π)**，所以 `+π` 和 `-π` 都是 `-π`。`SimVec.rotated` 用 `x' = x cos - y sin`、`y' = x sin + y cos`，正叉积表示第二向量在第一向量的顺时针侧。单位向量阈值是长度 `1e-9`。定步长在 `sim/loop.gd`：单帧真实时间先夹到 `[0, 0.25]` 秒，再按 `DT` 消耗，返回插值系数 `acc/DT`。

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

2026-11-12 这台 Linux VM 上，空 `SimWorld.step` 20000 tick（先热身 1000），三次约 **0.098–0.108 微秒/tick**（大约每秒 900 万到 1000 万次空步进）。这只是空循环基线。

同一天晚些时候，在已经载入数据表的进程里又测了三次空步进，约 **0.186–0.189 微秒/tick**。空循环会跟着机器负载变，不要把这两次差看成逻辑变慢。运动基准见第 12 节。

GitHub Actions：`.github/workflows/tests.yml`，在 `ubuntu-latest` 上下载同一 zip、核对 SHA512、跑上面的测试脚本。

## 10. 分层铁律

| 目录 | 放什么 |
|---|---|
| `res://sim/` | 纯 `RefCounted`。战斗、移动、RNG、定步长时钟。可以无头、可以快进、可以多开 |
| `res://sim/data/` | 读静态表的纯 `RefCounted`（`DataCatalog`、`DataSchema`）。不依赖 Node、场景、`res://game/` |
| `res://data/` | 静态表。`Game_test@33f4be8` 烘焙后的 JSON，见第 11 节 |
| `res://game/` | Node、场景、视图、输入、HUD、帧时间累加（`FixedStepDriver`） |
| `res://tests/` | `extends SceneTree` 的测试入口和套件 |
| `res://tools/` | 基准，以及 `bake_data.mjs`。计时可以用 `Time`，因为不在 sim 里 |

- `sim/` 和 `data/` **不得** `preload` / `load` `res://game/`，不得 `extends Node`（含 Node2D 等），不得用物理服务器做判定（`PhysicsServer`、`move_and_slide`）。
- 模拟层禁止 `randf()` / `randi()` / `randfn()` / `randomize()` / `RandomNumberGenerator`，也禁止读 `Time` 或 `OS.get_*` 当随机或时钟。随机只走 `sim/rng.gd`。时间只走 `SimClock.DT`（60 Hz，`1.0/60.0`），`step()` 不接收帧间隔。
- 不要 Autoload，不要把世界放进进程全局变量。训练时一个进程里 `SimWorld.new(seed)` 多份；`duplicate()` 复制 tick 和已创建的 RNG 流。
- 表现层把真实帧时间交给 `sim/loop.gd` 的 `advance()`（`game/fixed_step.gd` 只是薄封装）。单帧先夹到 0.25 秒。模拟结果不得依赖调用 `step()` 时的墙钟。
- `tests/layer_test.gd` 会扫 `sim/` 里的这些禁令，并检查文本资源没有 BOM、没有 CR。
- 坐标是屏幕坐标：+X 向右、+Y 向下、0 弧度朝右、顺时针为正。详见第 7 节。表现层不要再把 Y 翻一次。

局内经济（本步不实现）：战斗结算以后由 sim 广播事件；属性修正集中走 StatResolver，修正来源包括装备、改装和局内状态；换车前由经济层检查费用，sim 不直接扣钱。载具蓝图上的 `cost`（费用）留给这一层。原型没有这个字段，烘焙时写成 `0`。当前没有任何逻辑读取它：不进配额、复活、伤害或移动。`tests/data_test.gd` 会扫 `sim/` 和 `game/` 的代码，出现 `cost` 即失败。经济系统落地前保持 0，并先改这道扫描。

RNG 与 `Game_test@33f4be8` 的 `src/core/rng.ts` 一致：splitmix32 展开四个状态字，**不丢弃**输出。`spread` / `ai` / `map` 是三个独立的 `Rng`，种子分别为 `seed ^ 0x5f3759df`、`seed ^ 0x1b873593`、`seed ^ 0x27d4eb2f`。公开操作是 `next_u32`、`next`、`range`、`truncated_gauss`、`state`、`make_streams`。期望值在 `tests/rng_test.gd`，同种子 1000 tick 的序列哈希在 `tests/determinism_test.gd`（种子 42 为 `1947717684`）。

## 11. 数据层（2026-11-12）

原型 `src/data/` 的求值结果在 `res://data/`。加载器是 `res://sim/data/catalog.gd`（`DataCatalog`）和 `schema.gd`（`DataSchema`）。几何、pose、腿 IK、校验、移动、步态和地形在第 12 节。战斗还没移植。

### 为什么是 JSON，不是 `.tres`

烘焙在 Node 里执行原型。JSON 是那次求值直接写出的字节，仓库里没有第二套序列化。GDScript 的 `float` 是 64 位，`JSON.parse_string` 读回来仍是 64 位（见第 19 条：整数也会变成 float）。`.tres` 里的 `Vector2` 会收成 32 位，编辑器还可能重写资源；带 BOM 的 `.tres` 会让编辑器报 `Parse Error`（第 4 节第 3 条）。加载只用 `FileAccess`，不经过场景。

`Infinity` 写不成 JSON。规则上下限里的正无穷存成 `{"$":"inf"}`，目录加载后变成 `INF`。

### 烘焙

快照是 `Mrzandb/Game_test` 的 `33f4be8b19df7fe4137550e1da8ee38bf41aa94e`，解在仓库外面，不要提交。Node `>= 22.18`。脚本会自己加上类型剥离，并用 `tools/register_ts.mjs` 给原型里不带扩展名的 import 补 `.ts`。

```bash
node tools/bake_data.mjs --snapshot /path/to/Game_test
```

它 import 原型的 `shapes.ts` 和 `sim/vehicle/legs.ts`，把多边形和导弹射程算完再写文件。静止模块的多边形继续用烘焙结果，不要在 GDScript 里重算 `regular` / `chamferRect`。腿动起来之后用 `sim/vehicle/legs.gd` 的 `leg_parts`；`lift = 0` 已对上烘焙顶点（第 12 节）。`camera.ts` 含参数属性，类型剥离跑不了，脚本只核对源码里的 `lookRange: 2400 * RANGE_SCALE`，把结果 `7200` 写入 `data/index.json` 的 `sight.lookRange`。相机本身不在这次移植里。

脚本核对一组 33f4be8 指纹（`RANGE_SCALE = 3`、鱼雷和 EMP、`wallHp: 1800`、`MIN_PASSAGE = 520`、主炮 `350/560/120`、基地边长 480）。对不上就退出。同一快照重复运行，输出字节不变（2026-11-12 实测，`tests/golden/sha256.json` 的 SHA256 保持 `83012f1faac02d3ab757cf406adb771700f8dd933545499faca62cd344205843`）。

`shapes.ts` 的静止输出已经在各模块的 `parts` 里。`sim/vehicle/shapes.gd` 只给移动中的腿用。壁垒腿的静止碰撞体仍是烘焙结果；`legSpec` / `legRest` 留在 JSON 里，IK 用模块上的 `leg` 字段。

### 表里有什么

- `rules.json`：全局规则。
- `weapons.json`：全部武器，含未装备的 `torpedo_ap` 和 `emp_missile`。`RANGE_SCALE`、缺省 `sigmaRatio`、壁垒 / 蜂群的未缩放穿深常数也在这里。
- `vehicles/*.json`：壁垒、蜂群、隼，以及存档用的隼 B / C，和双方基地。每份蓝图有 `cost: 0`。
- `structures.json`：`BASE_SIZE` 480 和基地装甲 / 结构 / 回复。
- `maps/hills.json`：丘陵，以及 `minPassage` 520。
- `tests/golden/scalars.json`：除多边形顶点以外的全部叶子，供无头测试逐项对比。顶点由文件哈希锁住。

阵容（约束 C3 / C5 / C6 用的三辆）是 `index.lineup`：壁垒、蜂群、隼。隼 B / C 不进阵容。

### 单位和结构，下一步别改

- 载具局部坐标：+x 车头、+y 车体右侧。航向 0 时与世界坐标同向，不要翻 Y。
- 车体射界、转速、散布是**度**。地图出生点 `heading` 是**弧度**（丘陵里是 `-PI/4` 和 `3*PI/4`）。
- 缺省的 `sigmaRatio` 不写进武器；读取时用 `0.5`。只有壁垒主炮显式写成 `0.3`。`salvo` 也没写，缺省规则属于战斗逻辑，不要补进表。
- `BULWARK_AP.range` / `SWARM_AP.range` 仍是缩放前的 1600 / 1400。装到武器上的射程已经乘过 `RANGE_SCALE`。
- 基地只有一个 `core` 模块，没有动力舱。原型的 `validateVehicle` 要求恰好一个动力舱，但 C1 没把基地算进去。`sim/vehicle/validate.gd` 对 `locomotion == static` 跳过这一条。不要对基地跑 D29 包覆：整座建筑就是核心舱，扇形一定会打到它。
- 隼有三个 `primary`（导弹和两门激光）。原型 C6 的「主武器射程」会跳过导弹，取第一门激光。

## 12. 几何、移动、地形（2026-11-12）

这一节是第 3 步的记录。冠冕、武器和模块状态见第 14 节。`sim/motion.gd` 仍是只有移动的那一段。

移植自 `Game_test@33f4be8`，点仍是 `{x, y}` 字典。`sim/motion.gd` 的顺序与原型的移动段相同：指令 → `step_body` → 车与车 / 地形推出 / 场地夹紧 → 步态。它不跑冠冕瞄准、武器、导弹或模块计时。没有修正时速度和转向的倍率是 1，所以健康载具的轨迹和原型运动学一致。

| 文件 | 原型 |
|---|---|
| `sim/point.gd` | `src/core/math/vec2.ts` 的 64 位版本。不要改用 `Vector2` |
| `sim/geometry/poly.gd` | `src/sim/geometry/poly.ts` |
| `sim/vehicle/shapes.gd` | `shapes.ts` 里腿会用到的 `regular` / `strut` / `chamferRect` |
| `sim/vehicle/legs.gd` | `solveKnee` / `legParts` |
| `sim/vehicle/pose.gd` | 冠冕 / 炮塔变换、`firstHit`。没有脚姿态时用烘焙 `parts` |
| `sim/vehicle/validate.gd` | 凸性、宿主、D29。静态建筑不查「恰好一个动力舱」 |
| `sim/command.gd` | `command.ts`。这一步只读油门、转向、平移 |
| `sim/movement/kinematics.gd` | 足式 / 悬浮 / 履带。转速是度/秒，航向是弧度，且不把航向折回 `[-π, π)` |
| `sim/movement/mobility.gd` | `mobilityOf` 的公式。`down` 里的 id 当作不工作。`SimFight` 用模块状态填这个集合 |
| `sim/movement/gait.gd` | 程序化步态。`down` 里的腿定格在底盘坐标，之后跟着车体走 |
| `sim/terrain/terrain.gd` | 岩体永久阻挡，墙 HP 来自 `rules.terrain.wallHp`（1800） |
| `tests/motion_golden.json` | `tools/golden_motion.mjs` 用原型函数生成。绝对误差 **1e-9** |

再生黄金值（快照不要提交）：

```bash
node tools/golden_motion.mjs --snapshot /path/to/Game_test
```

`src/sim/world.ts` 的构造函数用了参数属性，Node 的类型剥离导入不了（第 21 条）。黄金脚本直接导入运动学、步态、地形和 pose，碰撞段按 `world.ts` 抄。

无头套件这次 **12852** 通过、**0** 失败，约 45 秒。C1 的包覆射线是大头：单独校验壁垒大约 13 秒。编辑器冒烟 `godot --headless --editor --path . --quit` 退出码 0，日志里没有 `Parse Error`、`ERROR:`、`SCRIPT ERROR`。

丘陵上 6 辆车（两种各两辆，出生点、固定油门和转向，含步态和地形推出），热身 200 tick 后跑 4000 tick，三次约 **287–322 微秒/tick**（大约每秒 3100–3500 步）。这是带碰撞的第一组数，不是战斗性能。

### 和原型行为的差别

- 第 3 步的 `SimMotion` 仍不跑模块状态机。调用方把 id 放进 `down`。速度惩罚和定格公式与 `mobilityOf` / `stepGait` 一致。宿主连坐、瘫痪倒计时和修复在第 14 节的 `SimFight` 里。
- 绕圈只用了 `thinkSimple` 里悬浮车的油门分解，并固定「导弹未就绪」，所以车头保持目标方位加 50°。完整 `World` 会在导弹能发射时把车头扭向目标。平均距离仍落在原型测试的 ±120 里，并且和这条简化公式的 Node 结果差在 1e-9 内。
- 确定性哈希是移动状态（位置、速度、航向、脚、墙 HP）按 1e-9 量化后的 FNV，不是 `World.hash()`。后者还含装甲、炮弹和冠冕角。
- 悬浮的 `speed` 是沿车头的标量。纯平移时它是 0，侧向速度在 `vel` 里。

### 只记录的文档矛盾

- `设计文档.md` 的移动方式表仍是悬浮 220、履带 160（蜂群 150）。代码是隼 400、蜂群 180、壁垒 110。`数值平衡交接.md` 的测试索引也还写着蜂群极速 150。
- 同文仍写路面材质影响履带和足式。`terrain.ts` 只有岩和墙，没有材质速度系数。清单 #38 里「材质只影响速度」没有进 33f4be8 的地形代码。
- `swarm.test.ts` 的标题写后向 2 门，断言是 `mainGun`、`sec3`、`sec4` 共 3 个 id。设计文档 D46 写后向 3 门，和断言一致。射界测试留给战斗。
- 清单 #2 建议悬浮转速 20–30 °/s。隼现在是 50 °/s。#59 之后转速已是普通平衡值，清单该项仍未勾。

## 13. 本步新坑

接第 4 节往下数。

19. **JSON 里的整数是 float，不能当 int 字典键**（2026-11-12 实测）
    - 现象：`JSON.parse_string('{"group":0}')` 的 `group`，`typeof` 是 `TYPE_FLOAT`（3）。`{0: "int", 0.0: "float"}` 的 `size()` 是 2。
    - 根因：Godot 4.7 把 JSON 数字都解析成 64 位 float。字典键看类型，`int` 0 和 `float` 0.0 不是同一条。
    - 做法：步态组在 `init_gait` 里 `int()` 一次。查找时用同一个类型。不要假设 `==` 成立的两个数做键也相等。

20. **分层扫描的 `Time` 会命中 `stepTime`**（2026-11-12 实测）
    - 现象：禁令表里的子串 `Time` 能匹配烘焙步态字段 `stepTime`。
    - 根因：扫描是去掉注释后的 `contains`，不是标识符。
    - 做法：`tests/layer_test.gd` 改成匹配 `Time.`，仍然挡住 `Time.get_ticks_*`。不要把子串改回 `Time`。

21. **类型剥离导入不了带参数属性的原型文件**（2026-11-12 实测）
    - 现象：`node --experimental-strip-types` 导入 `src/sim/world.ts` 报 `ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX`，指到 `constructor(readonly arena: ...)`。
    - 根因：Node 22 的 strip-only 模式不支持 TypeScript 参数属性。`camera.ts` 同样过不了（第 11 节）。
    - 做法：不需要整棵 `World` 时，导入没有参数属性的模块。`tools/golden_combat.mjs` 和 `tools/golden_world.mjs` 要跑 `World` 时，先把构造函数上的 `readonly` 参数改写成普通字段再导入（只改快照副本，不提交）。2026-11-13 实测：`match.ts` 的 `constructor(readonly world, readonly map, readonly defs)`、`nav.ts` 的 `private readonly world` / `readonly clearance`、`replay.ts` 里 `ReplayPlayer` 的 `readonly replay` 同样会被 strip-only 拒绝。黄金脚本在导入前改这三处。

22. **`:=` 推不出类型时，编译直接失败**（2026-11-13 实测）
    - 现象：`var x := callable.call(...)`，或 `var flag := 未标注类型的比较 or 另一个比较`，报 `The variable type is being inferred from a Variant value`，并写着 Warning treated as error。脚本加载失败。
    - 根因：Godot 4.7.2 把这种推断当成错误。`Callable.call` 和未标注字典的比较结果是 Variant。
    - 做法：写成 `var x: float = ...` 或 `var flag: bool = ...`。返回值没有静态类型、又只是存一下时，用 `var x = ...`，不要用 `:=`（第 15 条）。

23. **`JSON.stringify` 会把无穷写成 `null`**（2026-11-13 实测）
    - 现象：原型模块的 `lastStunAt` 初值是 `-Infinity`。直接 `JSON.stringify` 后这个字段变成 `null`，和「没写过」分不开。
    - 根因：JSON 没有无穷。`JSON.stringify(-Infinity)` 的结果是 `null`。
    - 做法：写黄金文件之前把非有限数换成字符串 `"-inf"` / `"inf"`。GDScript 读回来再还原成 `-INF` / `INF`。

24. **无头 `--script` 加载失败时会卡住 `xmessage`**（2026-11-13 实测）
    - 现象：`--script` 指向的脚本不是 `SceneTree` / `MainLoop`，或者依赖脚本有解析错误时，进程停在 `do_wait`，子进程是 `xmessage`，没有退出码。空等超过数分钟。
    - 根因：第 14 条的主循环不会自己结束；这台 VM 上 Godot 还会弹出 `xmessage` 等用户点掉。
    - 做法：测试入口必须 `extends SceneTree`，并在 `_process` 里兜底 `quit(1)`。排查时先看 `app_userdata/Ironwake/logs/godot.log`，不要等那个对话框。

25. **`match` 是 GDScript 关键字**（2026-11-13 实测）
    - 现象：`var match = SimMatch.new(...)` 或单独一行 `match.step()` 报 `Expected expression to test after "match"`，脚本加载失败。
    - 根因：`match` 是模式匹配语句，不能当变量名。文件名 `sim/match/match.gd` 和字符串 `"match"` 不受影响。
    - 做法：对局对象用别的名字（这里是 `fixture`）。类名用 `SimMatch`。

26. **`//` 是注释，不是整数除法**（2026-11-13 实测）
    - 现象：`rounded // scale_i` 报 `Expected expression after "/" operator`。
    - 根因：GDScript 用 `//` 开始注释。Godot 4 的 `/` 即使两边都是 int 也做浮点除法。
    - 做法：正数用 `int(float(a) / float(b))`。余数仍用 `%`。

27. **`JSON.stringify` 默认会缩短浮点**（2026-11-13 实测）
    - 现象：回放在内存里重放一致，`JSON.stringify` 再 `parse_string` 之后第一个失步哈希在 tick 660。
    - 根因：Godot 4 的 `JSON.stringify` 第四个参数 `full_precision` 默认是 false，写出的小数比 64 位短。
    - 做法：回放往返用 `JSON.stringify(data, "", false, true)`。载具 id 解析回来仍是 float，放进指令表之前要 `int()`，否则对不上 int 键（第 19 条）。

## 14. 战斗（2026-11-13）

`sim/fight.gd`（`SimFight`）按 `World.step` 的顺序接在第 12 节的移动段上：指令和锁定 → 车体（`mobilityOf` 之后乘 `stat()` 的 `maxSpeed` / `turnRate`）→ 碰撞 → 冠冕 / 炮塔 → 步态 → 武器 → 弹丸 → 导弹 → 模块计时和修正器计时。`SimMotion` 没有改这个顺序，移动测试仍走它。

| 文件 | 原型 |
|---|---|
| `sim/combat/penetration.gd` | `penetration.ts`。C4 用的就是这条 `penetrationAtDistance` |
| `sim/combat/modules.gd` | 损伤、瘫痪、重启、修复、宿主连坐、`isWorking` |
| `sim/combat/slots.gd` | 主武器槽。齐射 / 逐发。`RIPPLE = 0.3` |
| `sim/combat/turret.gd` | 射界内回转，贴边不换边 |
| `sim/combat/targeting.gd` | 锁定距离、外露模块选择 |
| `sim/combat/impact.gd` | AP / HE / EMP。墙的 HE ×1.5 在这里乘完再交给 `terrain.damage` |
| `sim/combat/weapons.gd` | 装填、散布、炮弹、激光。激光打墙先乘 `laserMul` 0.5 |
| `sim/combat/missiles.gd` | 助推摆动和巡航转向。鱼雷、EMP 弹按原型里已有的数据飞，没有另补玩法 |
| `sim/combat/sweep.gd` | 线段上最近的实体模块。同阵营透明 |
| `sim/stats/resolver.gd` | `stat` / `addModifier` / 计时。`purchase` 数组默认空，来源名是 `"purchase"` |
| `sim/movement/separate.gd` | `World.collide`，移动和战斗共用 |

点仍然是字典。腿的命中把 `feet_pose` 放进 pose。不每 tick 跑 D29。

事件在 `SimFight.events`，每 tick 开头清空。`hit` 带结构和失能，`moduleState` 转到 `DISABLED` 是瘫痪，`vehicleDestroyed` 是击毁。`sinks` 里的 `Callable` 在这一 tick 的事件组装完之后收到每一条，给以后的记分用。战斗不读蓝图上的 `cost`。

黄金值：

```bash
node tools/golden_combat.mjs --snapshot /path/to/Game_test
```

`tests/combat_golden.json` 与原型对比的绝对误差是 **1e-9**（文件里的数先按 1e-12 四舍五入）。同一对局种子 42 跑两次，`state_hash()` 相同；种子 43 不同。

无头套件 **14192** 通过、**0** 失败，约 40 秒（2026-11-13 实测，exit 0）。编辑器冒烟 `godot --headless --editor --path . --quit` 退出码 0，日志里没有 `Parse Error`、`ERROR:`、`SCRIPT ERROR`。

丘陵上同一组 6 辆车，固定油门和转向，并对对面出生点瞄准、主炮和副炮都开火。热身 200 tick，再跑 4000 tick。同一次进程里的仅移动基准约 **226 微秒/tick**。开火基准两次：

- **5484 微秒/tick**（约 182 步/秒）
- **5415 微秒/tick**（约 185 步/秒）

相对 PR #3 的仅移动 287–322 微秒/tick，大约 17–19 倍。大头是每门自动炮每 tick 的外露模块选择，以及弹丸对每辆车的 `first_hit`。这是第一组带开火的数，不是对局性能。

### 和原型行为的差别

- 没有移植 `World` 的 `place` 以外的对局层：`despawn`、回放、`thinkSimple`、配额和复活都不在这一步。`place` 留着，因为炮塔绕圈和锁定测试要每 tick 把目标放到新位置。
- 确定性哈希是位置、速度、航向、冠冕、炮塔角、模块装甲 / 结构 / 失能 / 状态、炮弹、导弹和墙 HP，按 1e-9 量化。不是 `World.hash()` 那条 `toFixed(6)` 字符串。180 tick 对射的模块和弹道数值与原型差在 1e-9 内，所以两条哈希不相等只是格式不同。
- 自动炮的提前量用挂载原点 `{0, 0}`，不是炮口。`world.ts` 的 `aim` 就是这样调用 `updateAutoAim` 的；文件头注释写的是炮口。
- 导弹发射的同一 tick 就会走一步助推，航向里已经有摆动。原型测试对扇面角用 `toBeCloseTo(..., 1)`，大约 0.05 弧度，装得下这一步。
- EMP、鱼雷按 `weapons.ts` 里已有的定义飞和结算。没有补原型里没写的发射器或额外规则。

### 只记录的文档矛盾

- `docs/射击与损伤机制_v2.md` §4.2 写 HE 系数 `max(0, (HE穿深 − armorCurrent) / HE穿深)`。`penetration.ts` 和 `rules.heMinFactor` 是 `max(0.15, ...)`。2026-11-11 的代码注释把保底写成已定规则。数值保持 0.15。
- 第 12 节记下的射界标题矛盾没有改。蜂群射界测试和代码一致：正后是 `mainGun`、`sec3`、`sec4` 三门，不是标题里的两门。

### 给下一步（World、对局、回放、AI）

- 把 `SimFight.step` 收成对局循环即可，不要把步态挪到碰撞前面，也不要每 tick 跑 D29。
- 回放要记的是每 tick 的 `Command`，外加种子和地图 id。校验用同一套 `step`。带拆墙的回放测试现在仍标着 DEFER。
- AI 只产生命令。`thinkSimple` 在导弹能发射时会把车头扭向目标；跟踪测试仍固定当成导弹未就绪。
- 记分订阅 `sinks`，读 `hit`、`moduleState`、`vehicleDestroyed`。购买修正走 `add_purchase`，默认是空数组。换车费用仍不要读 `cost`。
- 开火基准大约 5.4 毫秒/tick。对局层如果要无头跑很多局长，先看自动瞄准里的 `first_hit` 次数，不要先改公式。

## 15. 世界、对局、回放、AI（2026-11-13）

对局、回放和 AI 都调用 `SimFight.step`，没有第二套步进。顺序仍是第 14 节那一条。`SimWorld` 继续只做空步进和具名 RNG，确定性黄金哈希 `1947717684` 不变。D29 包覆不在 tick 里跑。

| 文件 | 原型 |
|---|---|
| `sim/fight.gd` | 补上 `despawn`、`replay_hash`、`gun_angle`、`tracking_error`。`replay_hash` 对齐 `World.hash()` 的 `toFixed(6)` 字段，供回放自检 |
| `sim/match/match.gd` | 开局名单、出生点、残骸、复活、换车配额、基地胜负和计时胜负 |
| `sim/replay.gd`、`sim/replay_player.gd` | 记指令差量、`place`、每 60 tick 的哈希；重放走同一个 `step` |
| `sim/ai/simple.gd` | `thinkSimple`。导弹装填完成且在 0.8 倍射程内时，车头对准目标再发射 |
| `sim/ai/nav.gd` | 100 单位格子的 A*，墙炸开后该格可走 |
| `sim/ai/team.gd` | `thinkTeam`。只产生 `Command` |

换车和复活前走 `departure_allowed`。`quoted_fee` 固定返回 0，不读蓝图上的费用字段。`depart_gate` 默认空，此时允许出场。开局名单在构造时生成，不经过这道门；之后的 `choose` 和复活会问它。拒绝时残骸留着，选择不变。`tests/data_test.gd` 对 `sim/` 和 `game/` 的 `cost` 子串扫描没有改。

黄金值：

```bash
node tools/golden_world.mjs --snapshot /path/to/Game_test
```

`tests/world_golden.json` 对比的绝对误差是 **1e-9**（文件里的数先按 1e-12 四舍五入）。锁住的是：隼绕圈 30 秒的平均距离和终态、导弹未就绪 / 就绪时的第一条指令、种子 11 的壁垒对射 180 tick、丘陵每个出生点到敌方基地的路径、默认名单在丘陵上跑 180 tick 的位置和模块。同一种子再跑一次，`state_hash()` 相同。

导弹装填初值是 34 秒，30 秒绕圈里它还没就绪，所以车头仍是目标方位加 50°。这条平均距离是 `598.927694225565`，和上一节简化公式的运动黄金值差在 1e-9 内。就绪之后的指令是另一组数：`turn` 为 0，武器槽是导弹槽。

无头套件 **14742** 通过、**0** 失败（2026-11-13 实测，exit 0）。上一节是 14192。编辑器冒烟 `godot --headless --editor --path . --quit` 退出码 0，日志里没有 `Parse Error`、`ERROR:`、`SCRIPT ERROR`。

默认套件里有原型的对局单测、回放（含 45 秒对射和丘陵拆墙）、寻路、180 tick 黄金，以及壁垒 / 隼 / 蜂群的对战断言。6 分钟 3v3 和 8 场平衡跑局不在 `run_tests.gd` 里，避免 CI 超时。

```bash
godot --headless --path . --script res://tools/scenario.gd
godot --headless --path . --script res://tools/balance.gd
```

`scenario.gd` 是原型「丘陵全 AI、360 秒」那条：双方推进、开火、阵亡、基地掉血，再跑一次哈希相同。`balance.gd` 对齐 `npm run balance`：8 场对称 3v3（上限 600 秒，奇数局换边）加上每对载具 6 场单挑（上限 180 秒）。报告写到 `reports/balance-report.md`。环境变量 `BAL_MATCHES`、`BAL_DUELS`、`BAL_SECONDS`、`BAL_HOLD_DIST`、`BAL_KEEP_DIST`、`BAL_ORBIT`、`BAL_STALEMATE`、`BAL_PUSH_TIME`、`BAL_DUEL_KEEP` 与原型同名。

`scenario.gd` 这次实测（exit 0，两遍 360 秒）：开火 2026 次，双方离敌方基地最近 **984** 和 **348**，阵亡 7，基地有掉血，第二次 `state_hash` 相同，结果是红方因时间获胜。这只说明流程和推进成立，不是 8 场平衡口径。

同一进程里的基准（2026-11-13）：

- 空 `SimWorld.step`：20000 tick，**0.153 微秒/tick**
- 丘陵 6 车只移动：4000 tick，**231 微秒/tick**（约 4321 步/秒）
- 同一组车瞄准并开火：4000 tick，**5401 微秒/tick**（约 185 步/秒）
- 丘陵 3v3，含寻路、`thinkTeam`、`SimFight.step`、`SimMatch.step`：热身 60 tick，再量 240 tick，**13549 微秒/tick**（约 74 步/秒）

### 和原型行为的差别

- 回放字符串按同一套 `toFixed` 规则自己比自己。不要求和 JS `World.hash()` 的文本逐字节相同。
- 激光热量迟滞和队伍 AI 的路径记在载具上（`heat_hold`、`brain`），不进 `state_hash` / `replay_hash`。`place` 不清这两项，和原型 `WeakMap` 挂在同一个对象上一样。复活会 `despawn` 再 `spawn`，新车没有旧脑。
- 购买来源修正仍在 `SimFight.step` 里单独计时。数组为空时和原型 `tickModifiers` 的结果一致。
- EMP、鱼雷仍只按原型里已经写了的武器数据飞和结算。

### 只记录的文档矛盾

本步没有新的、需要改冻结数值的矛盾。第 14 节的 HE 保底 0.15 和蜂群后向射界标题仍然只记录、不改表。

### 给下一步（可玩桌面壳、占位贴图）

- 表现层每帧把真实时间交给 `sim/loop.gd` 的 `advance`，回放和游玩都加 `--fixed-fps 60`。模拟只认 `SimFight.step` 和之后的 `SimMatch.step`。
- 输入收成 `Command`。AI 已经是同一条入口。玩家载具用 `default_roster` 里 `ai: false` 的那一格，不要在 sim 里分支。
- 画面读 `pose`、`events`、`beams`。`sinks` 留给记分。购买修正走 `add_purchase`。换车费用接 `depart_gate`，现在的报价是 0。
- 贴图可以先按模块多边形画占位色。不要把判定改成物理服务器。
- 完整对局大约 13.5 毫秒/tick。桌面壳先做一局，自动瞄准里的 `first_hit` 仍然是大头。
