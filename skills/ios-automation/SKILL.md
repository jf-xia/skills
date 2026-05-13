---
name: ios-automation
description: "执行 iOS 真机与模拟器自动化。用于 WebDriverAgent 场景下的设备发现、WDA 启动、Session 创建、页面读取、元素交互、手势、系统控制、故障恢复与性能调优。适用于通过 xcodebuild、simctl、curl 或 WDA REST API 完成移动端自动化任务。"
argument-hint: "描述任务，例如：在真机启动 WDA 并创建 session；读取 source 后点击按钮；处理权限弹窗并截图"
user-invocable: true
---

# iOS 自动化技能

## 适用场景
- 在真机或模拟器上启动、复用或重启 WebDriverAgent
- 通过 WDA REST API 建立 session、读取页面、执行点击、输入、手势和截图
- 控制应用生命周期、系统弹窗、锁屏、方向、位置等设备能力
- 排查签名、连接、无 session、元素失效、键盘和超时问题

## 标准流程
1. 优先使用真机, 如果找不到使用模拟器，并按 [启动与 Session](./references/startup-and-session.md) 检查依赖、设备 ID、端口和 WDA 健康状态。
2. 如果设备上已有可用 WDA，优先复用已有构建或 `test-without-building` 路径；否则再走完整 `xcodebuild test` 和签名修复流程。
3. 建立 session 后，优先通过 `/source`、`/wda/accessibleSource` 和元素 API 做结构化交互；需要具体路由时查 [命令参考](./references/command-reference.md)。
4. 输入文本时，优先使用元素级 `/element/:uuid/value`；仅在焦点已明确时使用 `/wda/keys`。细节见 [输入与键盘](./references/input-and-keyboard.md)。
5. 需要切应用、处理系统弹窗、锁屏、方向、位置或设备信息时，查 [应用与设备控制](./references/app-and-device-control.md)。
6. 当可访问性信息不足、页面动画频繁或需要视觉闭环时，退回截图/坐标策略，并按 [视觉驱动与性能](./references/visual-and-performance.md) 调优。
7. 任何 404、408、Session Not Created、元素不可见、输入失败等异常，都先按 [故障排查](./references/troubleshooting.md) 执行最短恢复，再查看 [限制与取舍](./references/limitations.md) 判断是否需要切换策略。

## 决策要点
- 真机优先检查签名、`iproxy`、`xcodebuild`；模拟器优先检查 `simctl` 状态和 App 安装。
- 有稳定可访问性节点时优先元素定位；没有稳定节点时退回截图加坐标点击。
- 需要对具体元素输入时用元素级输入；只是向当前焦点发送键盘事件时用 `/wda/keys`。
- 需要复现系统级场景时优先使用 `/wda/apps/*`、`/alert/*`、`/wda/lock`、`/orientation` 等专用接口，不要硬编码坐标。

## 完成标准
- WDA 的 `GET /status` 或 `GET /wda/healthcheck` 可用。
- 需要 session 的操作之前，已确认 session 创建成功或会话仍然有效。
- 每次交互后至少通过元素状态、页面源码、截图或应用状态之一验证结果。
- 出现失败时，已记录错误类型，并执行对应的最短恢复路径，而不是盲目重试。

## 参考资料
- [启动与 Session](./references/startup-and-session.md)
- [命令参考](./references/command-reference.md)
- [输入与键盘](./references/input-and-keyboard.md)
- [应用与设备控制](./references/app-and-device-control.md)
- [视觉驱动与性能](./references/visual-and-performance.md)
- [故障排查](./references/troubleshooting.md)
- [限制与取舍](./references/limitations.md)

