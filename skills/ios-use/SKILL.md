---
name: ios-use
description: "操作 iOS / iPhone 真机与模拟器自动化。用于 WebDriverAgent 场景下的设备发现、WDA 启动、Session 创建、页面读取、元素交互、手势、系统控制、故障恢复与性能调优。适用于通过 xcodebuild、simctl、curl 或 WDA REST API 完成移动端自动化任务。"
argument-hint: "描述任务，例如：在真机启动 WDA 并创建 session；读取 source 后点击按钮；处理权限弹窗并截图"
user-invocable: true
---

# 操作 iOS / iPhone 真机与模拟器自动化技能

## 适用场景
- 在真机或模拟器上启动、复用或重启 WebDriverAgent
- 通过 WDA REST API 建立 session、读取页面、执行点击、输入、手势和截图
- 控制应用生命周期、系统弹窗、锁屏、方向、位置等设备能力
- 排查签名、连接、无 session、元素失效、键盘和超时问题

## 开始前准备
- 每次开始使用本技能前，先在项目根目录创建本次操作的临时工作目录：`mkdir -p ./tmp/$(date +%y%m%d%H%M%S)`。
- 将当前操作产生的截图、日志、临时脚本和其他中间文件统一放在该时间戳目录下，避免散落在仓库其他位置。
- 这样做的目的：集中保留调试证据、按时间快速定位一次操作、减少临时文件混乱和遗漏。

## 标准流程
1. 先创建本次操作的 `./tmp/<yymmddhhmmss>/` 临时目录，用于集中保存截图、日志、脚本和其他中间文件。
2. 优先使用真机, 如果找不到使用模拟器，并按 [启动与 Session](./references/startup-and-session.md) 检查依赖、设备 ID、端口和 WDA 健康状态。
3. 如果设备上已有可用 WDA，优先复用已有构建或 `test-without-building` 路径；否则再走完整 `xcodebuild test` 和签名修复流程。
4. 建立 session 后，优先通过 `/source`、`/wda/accessibleSource` 和元素 API 做结构化交互；需要具体路由时查 [命令参考](./references/command-reference.md)。
5. 输入文本时，优先使用元素级 `/element/:uuid/value`；仅在焦点已明确时使用 `/wda/keys`。细节见 [输入与键盘](./references/input-and-keyboard.md)。
6. 需要切应用、处理系统弹窗、锁屏、方向、位置或设备信息时，查 [应用与设备控制](./references/app-and-device-control.md)。
7. 当可访问性信息不足、页面动画频繁或需要视觉闭环时，退回截图/坐标策略，并按 [视觉驱动与性能](./references/visual-and-performance.md) 调优。
8. 任何 404、408、Session Not Created、元素不可见、输入失败等异常，都先按 [故障排查](./references/troubleshooting.md) 执行最短恢复，再查看 [限制与取舍](./references/limitations.md) 判断是否需要切换策略。

## 决策要点
- 真机优先检查签名、`iproxy`、`xcodebuild`；模拟器优先检查 `simctl` 状态和 App 安装。
- 有稳定可访问性节点时优先元素定位；没有稳定节点时退回截图加坐标点击。
- 需要对具体元素输入时用元素级输入；只是向当前焦点发送键盘事件时用 `/wda/keys`。
- 需要复现系统级场景时优先使用 `/wda/apps/*`、`/alert/*`、`/wda/lock`、`/orientation` 等专用接口，不要硬编码坐标。

## 信息不足时的代码库追问
- 当已经提供的信息不足以继续判断，或者需要确认更底层的实现细节、路由来源、异常来源、参数语义时，可以使用 deepwiki 的 CLI 直接询问 WebDriverAgent 代码库。
- 推荐仓库：`appium/WebDriverAgent`。
- 常用命令形式：`dw aq -r "appium/WebDriverAgent" -q "<你的问题>"`

使用示例：

```bash
dw aq -r "appium/WebDriverAgent" -q "raw REST probing 举例说明"
dw aq -r "appium/WebDriverAgent" -q "POST /session 在 WebDriverAgent 里经过哪些 handler 和对象"
dw aq -r "appium/WebDriverAgent" -q "element/:uuid/value 的输入链路和 frequency 参数是怎么生效的"
dw aq -r "appium/WebDriverAgent" -q "No Such Driver 和 Stale Element 在代码里分别从哪里抛出"
dw aq -r "appium/WebDriverAgent" -q "waitForQuiescence 相关逻辑在哪些文件里，具体影响哪些动作"
dw aq -r "appium/WebDriverAgent" -q "accessibleSource 和 source 的生成路径有什么差异"
```

适合追问的内容：
- 某个 REST 路由由哪个 handler、command 或 category 实现。
- 某个异常、HTTP 状态码或错误文本是在什么条件下抛出的。
- 某个 capability、setting 或内部参数在代码里的实际作用范围。
- 某个接口在裸 WDA、上层 driver 封装和 XCTest 底层之间分别由谁负责。

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

