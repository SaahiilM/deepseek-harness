# Agent Note: `--directory-picker` pins the directory-picker interaction from the launch flags

Status: implemented

[English](2026-08-23-directory-picker-pin-flag.md) | 中文

> 范围：`dsh --profile web` 的 flag 家族与 `dsh-host-directory-picker-auto` 的组合 config。能力接缝本身、两个后端、以及 `-auto` 的解析函数均未改变；本文记录的是[自适应默认](2026-07-29-directory-picker-adaptive-default.zh.md)中作为"部署需要强制后端时再引入"而预留的 pin 通道的落地。

## 问题

`-auto` 从启动事实（回环绑定、无 SSH、有显示会话）解析交互，这对"操作者在宿主机前"的部署是正确的。但一种新部署形态出现了：同一个服务器同时服务本机浏览器与通过配对门进来的远程手机。启动事实看不到客户端表面，于是 `native` 被解析并挂载——远程表面上的"新建工作区"驱动 `host.pickDirectory`，把 OS 对话框开在了无人看到的宿主机屏幕上，远程操作者只能面对一个永远忙碌的流程。[按连接自适应](../architecture/2026-07-28-directory-picker-capability-seam.zh.md)仍是明确的 deferred 项；部署需要的是现在就能强制后端而不改 yml。

## 决策

一句话：**web 启动家族新增 `--directory-picker <auto|native|browse>`；该值经 `webStartup.directoryPicker` 服务进入 chooser 行的 `pin` config，chooser 在被 pin 时跳过事实采样、直接挂载对应的后端+客户端表面对。**

具体而言：

- `directory-picker-auto` 获得 schemastery 校验的可选 `Config.pin`；缺省时行为逐位不变。
- bundle 的 chooser 行以 `inject: [webStartup]` + 惰性 `!!js ctx.webStartup.directoryPicker` 喂入 pin——与其他 flag 驱动的行相同的通道；行级 inject 与插件声明的 inject 合并（`Inject.resolve` 填充名字映射），不覆盖。
- `auto` 在 provider 中即被吸收为缺省，因此服务值只在显式 pin 时携带该字段。

## Alternatives considered

- 直接在本部署的 overlay 里组合 `-browse` 行：可行，但把选择烧进了静态组合；flag 让同一棵树在不同启动参数下回答不同部署，且这正是自适应默认 note 预留的重引入形态。
- 复活 wire 能力通告让两端各自分支（按连接自适应）：仍需双流挂载与 `single` hole 语义重设计；本次部署用 pin 即已可用。

## 后果

- 桌面 shell 以 `--directory-picker browse` 启动其拥有的服务器：每个表面上的工作区创建都走应用内宿主机文件系统浏览器；OS 对话框部署继续依赖 auto 或直接组合 `-native`。
- 解析仍然每次启动恰好一次，能力稳定性契约不变。
