# DeepSeek Harness — Desktop App

[English](README.md) | 中文

一个原生 macOS 外壳，把 DeepSeek Harness 的 Web UI 变成桌面应用，可与 OpenAI 的 Codex 应用类比：单窗口、Dock 图标、菜单，以及由应用管理的本地 agent server。Intel 与 Apple Silicon 均可运行。

```
desktop/
├── PROJECT_MEMORY.md          durable project memory — read this first
├── agent-memory/              per-session agent notes (append-only)
├── shell/
│   ├── Sources/               Swift sources (AppKit + WKWebView)
│   ├── Tools/make-icon.swift  icon generator
│   └── Info.plist├── scripts/
│   ├── build.sh               harness build + universal .app assembly
│   ├── run.sh                 launch the built app
│   ├── sync-origin.sh         keep this branch current with origin/master
│   ├── log-session.sh         append to agent memory
│   └── make-icon.sh           cached icns generation
└── dist/                      build output (ignored)
```

## 快速开始

```sh
pnpm install                    # once, from the repo root
desktop/scripts/build.sh        # builds the harness and dist/"DeepSeek Harness.app"
open "desktop/dist/DeepSeek Harness.app"
```

环境要求：Node ^22.19 || >=24 · pnpm 11 · Xcode 命令行工具（`swiftc`）。

## 架构

`shell/Sources/` 下每个模块只负责一件事；AppKit 胶水代码与纯逻辑分离，使棘手部分可做单元测试（`test-shell.sh`）：

| 模块 | 职责 |
|---|---|
| `AppMain` / `SingleInstanceGuard` | 入口；再次启动会激活正在运行的实例 |
| `AppDelegate` | 组装根：连接各协作者，路由 `ServerState` |
| `AppMenuBuilder` | 菜单栏结构（动作实现在 AppDelegate 上） |
| `WindowManager` / `WindowController` | 窗口集合；每个窗口一个 webview |
| `LifecyclePages` | 启动中/错误页 HTML——纯函数，输入经 HTML 转义 |
| `ServerController` | 启动/探测/停止 harness server 进程 |
| `RepoLocator` / `NodeLocator` / `FreePortPicker` | 检出定位、经引擎校验的 node 探测、临时端口 |
| `ServerLogStore` / `ReadinessProbe` | 日志文件与 tail 缓冲；HTTP 就绪轮询 |
| `SessionListWire` | `POST /api/session.list` 的请求/响应编解码（宽松解码） |
| `SessionMonitor` + `SystemPresenceReporter` | 对比运行中/已结束 → 角标、通知、弹跳 |

## 用手机访问（LAN 配对，t3code 风格）

1. Server 菜单 ▸ **Enable Remote Access (LAN)**——应用会启动一个绑定到所有网络接口的 token 网关，并在重新启动后保持运行，直到被关闭。
2. Server 菜单 ▸ **Pair Mobile Device…**——一个二维码编码了 `http://<mac-ip>:<port>/pair/<one-time-code>`。
3. 用手机相机扫码（需在同一 Wi-Fi 下）。打开该链接一次即可用一次性码换取长期 cookie，并进入完整 Web UI：全部会话、审批和实时的 agent 流。

该网关（`desktop/gate/gate.mjs`）在把请求代理到 loopback server 之前，会针对配对密钥校验每一个 HTTP 请求和 WebSocket 升级——harness 本身绝不会在未认证状态下暴露。流量只在你自己的 LAN 内流转，没有云端中继。若要在家之外访问，请加入 Tailscale（或同类）网络，并针对 tailnet IP 重新配对。

## 两种打包模式

| 模式 | 构建 | 行为 |
|---|---|---|
| 基于检出（默认） | `build.sh` | 从 bundle 向上逐级查找以定位实时检出；对仓库的改动会在下次启动时生效。要求本机装有 Node ^22.19\|\|>=24。 |
| 自包含 | `make-standalone.sh` | 把仓库快照与经校验的 node 二进制嵌入 `Contents/Resources/runtime`（约 1.6 GB）。可在既无检出也无 Node 的机器上运行。 |

定位器依次尝试：`DSH_DESKTOP_REPO` → `DSHDesktopRepoPath` 默认值 → 从可执行文件向上查找 → 内嵌快照。因此，放在检出目录内的独立版应用仍会针对该检出开发；挪到别处的应用则使用自己的快照。内嵌 server 在打包时由 `pick-node.sh` 验证，它镜像了 `NodeLocator` 中由新到旧的 engines 扫描。

## 工作原理

1. `build.sh` 先运行常规的 `pnpm run build`（tsc + tsdown + Web 前端），再把 Swift 外壳编译两次（arm64、x86_64），并用 `lipo` 合并进 `dist/DeepSeek Harness.app`——一个通用二进制。
2. **每台机器一个后端**：启动时应用会探测 harness 默认端口（3080）——以及它自己上次启动所用的端口——查找存活的 harness server（通过其 `session.list` RPC 指纹识别）。已存在的 server 会被**接管**，绝不重复启动或终止；在浏览器标签页中运行的 agent，会和在原生环境中启动的 agent 一样出现在原生应用的角标上。只有在没有任何服务响应时，应用才会从当前检出启动一个自有 server（`node --import tsx/esm apps/cli/src/bin.ts web --no-open`）。以 `DSH_DESKTOP_SPAWN_OWN=1` 启动可跳过接管、始终启动自有 server——适用于在默认端口上已有另一个 harness server 运行时，针对一个全新检出测试本应用。
3. 它等待 HTTP 就绪，捕获带 token 的 `dsh web` URL，用它换取 Web Host cookie，在 `WKWebView` 中加载已认证的 UI，并把导航限制在 loopback——外部链接会在你的默认浏览器中打开。
4. 退出应用只会终止*自有* server。server 输出写入 `~/Library/Application Support/DeepSeek Harness/server.log`。

## 桌面端特性（Codex/bb/t3code 模式）

- **单实例**——启动第二份副本会激活正在运行的应用。
- **会话在场状态**——`SessionMonitor` 每 3s 轮询 `POST /api/session.list`：Dock 角标显示有多少 agent 正在运行；当应用位于后台时某个 agent 完成会发出通知（通知不可用时改为 Dock 弹跳）。由于应用会接管本机正在运行的 server，这也包含从浏览器标签页启动的 agent。
- **多窗口**——File ▸ New Window（⌘N）会为同一个本地 server 打开另一个视图；窗口框架在多次启动之间保持。
- **原生菜单**——Edit 角色让撤销/复制/粘贴在 webview 内可用；View 提供 Reload 与 Zoom In/Out/Actual Size；Server 提供 Restart/Open in Browser/Copy URL/Reveal Log。

## 分发

```sh
desktop/scripts/make-dmg.sh     # dist/"DeepSeek Harness.dmg"
```

该 DMG 为 ad-hoc 签名：在你用 Developer ID 签名并做公证之前，其他机器都会看到 Gatekeeper 警告（相关命令由该脚本打印）。

## 与上游保持同步

该分支跟踪 `origin/master`；它所拥有的一切都位于 `desktop/` 中，因此 rebase 几乎总是干净：

```sh
desktop/scripts/sync-origin.sh          # fetch + rebase onto origin/master
desktop/scripts/sync-origin.sh --check  # report drift only
```

## Agent 记忆

在本分支上工作的 agent：改动任何内容之前，先读 `PROJECT_MEMORY.md`，再读 `agent-memory/sessions/` 中最新的文件。用以下命令记录有意义的工作单元：

```sh
desktop/scripts/log-session.sh "<what was done / learned / decided>"
```