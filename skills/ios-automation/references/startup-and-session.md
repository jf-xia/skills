# 启动与 Session

## 目标
在真机或模拟器上把 WebDriverAgent 跑起来，确认服务可用，并创建后续交互所需的 session。

## 启动前检查
- Xcode 与 Command Line Tools 可用。
- 如果依赖 Appium 生态，确认 Node.js、npm 与 Carthage 环境可用。
- 真机场景额外确认 `ios-deploy` 与 `iproxy` 可用。
- 对真机使用唯一 Bundle ID 和有效的开发团队 ID，避免常见的签名冲突。

## 真机标准流程
1. 用 Xcode 原生命令确认设备 ID，例如 `xcrun xctrace list devices`。
2. 已有可用构建时优先 `test-without-building`；没有构建产物时使用完整 `test`。
3. 为 USB 连接建立端口转发：`iproxy 8100 8100 <UDID>`。
4. 用 `GET /status` 或 `GET /wda/healthcheck` 确认 WDA 已经起来。
5. 发送 `POST /session` 创建 session，并保存 `sessionId`。

完整构建示例：

```bash
xcodebuild -project ~/work/WebDriverAgent/WebDriverAgent.xcodeproj \
  -scheme WebDriverAgentRunner \
  -destination "id=<UDID>" \
  test
```

已构建产物的快速启动思路：

```bash
xcodebuild -project ~/work/WebDriverAgent/WebDriverAgent.xcodeproj \
  -scheme WebDriverAgentRunner \
  -destination "id=<UDID>" \
  test-without-building
```

## 模拟器差异
- 设备枚举通常使用 `xcrun simctl list devices`。
- 模拟器不需要真机签名和 `iproxy`。
- 如果需要冷启动或重置环境，优先配合 `simctl` 管理模拟器状态。

## Session 创建示例

```bash
curl -X POST http://localhost:8100/session \
  -H "Content-Type: application/json" \
  -d '{
    "capabilities": {
      "alwaysMatch": {
        "platformName": "iOS",
        "deviceName": "iPhone 12",
        "bundleId": "com.example.app",
        "udid": "<UDID>"
      }
    }
  }'
```

## 常用能力集

| 字段 | 作用 | 何时使用 |
| --- | --- | --- |
| `appium:automationName` | 指定 `XCUITest` | Appium 驱动模式下固定需要 |
| `appium:bundleId` | 冷启动目标应用 | 已知包名且不传 `.app` 路径时 |
| `appium:app` | 安装或启动指定应用包 | 本地有 `.app` 或 `.ipa` 时 |
| `appium:udid` | 绑定具体设备 | 多设备并行或真机场景 |
| `appium:usePreinstalledWDA` | 复用已装好的 WDA | 追求更快启动时 |
| `appium:wdaLocalPort` | 指定本地映射端口 | 多设备并行避免冲突 |
| `appium:autoAcceptAlerts` | 自动接受系统弹窗 | 环境初始化时常用 |

## 健康检查接口

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/status` | 返回 WDA 状态与版本信息 |
| `GET` | `/wda/healthcheck` | 轻量健康检查，无需 session |
| `GET` | `/session` | 查询活动 session |
| `DELETE` | `/session` | 结束当前会话 |

## 启动完成标准
- WDA 的状态接口返回成功。
- 真机场景下，端口转发已经建立且 `curl http://localhost:8100/status` 可访问。
- 创建 session 成功，并保存了 `sessionId`。
- 如果后续需要操作 App，已确认目标 App 的 `bundleId`、安装状态和前台状态。

## 失败时的最短回退路径
1. 先查 `/status`；如果服务不通，回到 WDA 启动步骤。
2. 服务可通但 `POST /session` 失败时，先精简 capabilities，再检查 App 路径或包名。
3. 真机若仍失败，优先检查签名、开发团队 ID、唯一 Bundle ID 与设备信任状态。