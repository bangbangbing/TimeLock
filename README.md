# TimeLock — 定时强制锁屏提醒（macOS）

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

菜单栏常驻应用：每隔 N 分钟（默认 25，可设置）强制全屏锁屏 M 秒（默认 10，可设置），
屏幕中央显示你输入的提醒词（支持多行），倒计时不可关闭、不可跳过。

支持 **Intel + Apple Silicon**（Universal Binary），最低 macOS 10.15 Catalina。

## 功能

- **定时提醒**：每 N 分钟触发一次，间隔 1–999 分钟可调
- **强制锁屏**：全屏覆盖层（`NSWindow.level = .screenSaver`）覆盖所有显示器，
  锁屏时长 5–3600 秒可调，期间无任何关闭入口（无按钮/无点击关闭/无快捷键退出）
- **提醒词**：多行文本，锁屏画面居中大字显示；菜单栏面板内可直接快速编辑
- **锁屏结束去向（设置中勾选）**：
  - ✅ 勾选「锁屏完毕后自动熄屏锁定」→ 触发系统级真锁屏（见下文「自动锁屏与辅助功能权限」），输入密码解锁后继续提醒循环；若 6 秒内未检测到锁屏生效，自动提示并继续下一轮
  - ⬜ 不勾选 → 覆盖层自动消失，回到锁屏前状态并开始下一轮
- **开机自启**：macOS 13+ 用 SMAppService，旧版回退 LaunchAgents
- **系统感知**：休眠/锁屏时自动暂停计时，唤醒后恢复；显示器增减时自动重建覆盖层
- **单实例**：flock 文件锁，重复启动会唤起已运行实例

## 自动锁屏与辅助功能权限

勾选「锁屏完毕后自动熄屏锁定」后，应用按以下候选链触发锁屏：

| 优先级 | 方式 | 条件 | 效果 |
|--------|------|------|------|
| 1 | `CGSession -suspend` | 旧版 macOS 存在该工具（macOS 26 已移除） | 真锁屏，无需授权 |
| 2 | 模拟 `Control+Command+Q` 快捷键（CGEvent） | 已授予辅助功能权限 | 真锁屏 |
| 3 | `pmset displaysleepnow` | 兜底 | **仅熄屏不锁屏**，并弹系统授权引导 |

> **为什么需要辅助功能权限**：macOS 26 移除了 CGSession，现代 macOS 的程序化真锁屏
> 只能通过模拟系统快捷键实现，这要求在
> **系统设置 › 隐私与安全性 › 辅助功能** 中添加并勾选 TimeLock。
> 未授权时只能熄屏保底（若系统未开启「退出睡眠后要求密码」，唤醒后不锁屏），
> 应用会通过系统通知提示原因。

- 查看当前权限状态：设置窗口勾选项下方有实时提示；菜单栏面板 footer 显示「真锁屏✅/⚠️未授权」
- 命令行诊断（无副作用）：

```bash
/Applications/TimeLock.app/Contents/MacOS/TimeLock --lock-test       # 打印授权状态与候选工具
/Applications/TimeLock.app/Contents/MacOS/TimeLock --lock-test-go    # 实际触发一次锁屏链
```

## 构建

需要 Xcode 或 Command Line Tools（Swift 5.9+）。

```bash
cd TimeLock
./make_app.sh          # 产出 build/TimeLock.app（x86_64 + arm64 Universal）
```

仅本机架构快速调试：

```bash
swift build
.build/debug/TimeLock
```

## 运行

```bash
open build/TimeLock.app
```

- 菜单栏出现 ⏱ 图标，点击弹出面板；启动即自动开始计时
- 未签名/未公证，首次打开若被 Gatekeeper 拦截：右键 → 打开；或
  `xattr -dr com.apple.quarantine build/TimeLock.app`
- 「开机自启」建议先把 TimeLock.app 拖到 /Applications 再开启

## 自动化测试

```bash
.build/debug/TimeLock --smoke-test   # 验证覆盖层窗口覆盖所有屏幕、层级正确
# 输出 SMOKE_TEST passed=true ...  退出码 0 为通过
```

## 工程结构

```
Sources/TimeLock/
├── main.swift                    # 入口：单实例锁 + NSApplication 启动
├── AppDelegate.swift             # 菜单栏图标/弹窗/系统事件/冒烟测试
├── ReminderEngine.swift          # 状态机 idle→running→resting→paused
├── OverlayController.swift       # 全屏覆盖层（多显示器、.screenSaver 层级）
├── PopoverPanelController.swift  # 菜单栏弹出面板（状态/进度/提醒词快速编辑）
├── SettingsWindowController.swift# 设置窗口（间隔/时长/提醒词/自启/自动熄屏）
├── SettingsStore.swift           # UserDefaults 设置存储
├── SystemLock.swift              # 系统锁屏候选链（CGSession / CGEvent 快捷键 / pmset 兜底）
├── UserNotifier.swift            # 系统通知（锁屏异常提示）
└── LaunchAtLogin.swift           # 开机自启（SMAppService / LaunchAgents）
```

## 技术说明（Intel 兼容）

- 纯 AppKit（非 SwiftUI-only API），macOS 10.15+ 可编译运行
- `make_app.sh` 产出 fat binary；arm64 构建失败时自动回退 Intel-only
- 新 API（SF Symbols / SMAppService / activate()）均带 `#available` 降级路径
- `.app` 以固定 designated requirement（`identifier "com.zhougj.timelock"`）做 ad-hoc 签名，
  重新打包后已授予的辅助功能权限仍然有效

## 后续可扩展（V1.5）

- 提醒词轮播池（多行中每轮随机抽取一条）
- 每日统计（今日锁屏次数 / 累计休息时长）
- 全局快捷键暂停 / 恢复
