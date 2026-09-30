# Agent Note: 原生 Shell 使用带令牌的 Web URL

Status: implemented

[English](2026-09-18-native-shell-browser-auth.md) | 中文

## 问题

Web Host 要求先交换启动令牌，才会提供应用文档和 API。原生 shell 等待回环监听器就绪后加载不带令牌的端口 URL，因此独立应用虽然已经收到服务器打印的认证 URL，仍会显示 Host 的 401 消息。

## 决策

原生 shell 自有的服务器会捕获 `dsh web` 打印的带令牌 URL，在 HTTP 就绪后等待该 URL，并将其作为运行 URL 提供给应用。`WKWebView` 跟随重定向、保存按 authority 绑定的 Cookie，然后加载已认证的应用。缺少或不带令牌的启动 URL 会在启动阶段被拒绝，而不是显示容易误解的 401 页面。

Web Host 的浏览器认证策略保持不变。shell 继续使用服务器已有的进程输出，不增加未认证的回环例外，也不增加第二套认证协议。

## 考虑过的替代方案

**加载不带令牌的回环 URL。** Web Host 会正确拒绝该请求，这正是本决策修复的故障。

**为原生回环客户端关闭浏览器认证。** 这会削弱共享 Web Host 策略，并创建只对原生客户端适用的例外。

**增加单独的令牌 IPC 端点。** 第二个凭据传递通道会重复 Web runner 已经输出的启动 URL，并扩大原生协议。

## 后果

独立应用和基于 checkout 的原生启动现在都会完成与 `dsh web` 相同的浏览器认证交换。shell 测试固定带令牌 URL 的提取行为，并拒绝不带令牌的 URL。如果服务器没有报告带令牌的 URL，shell 会使用捕获的诊断信息明确失败。
