# 启动与 Session

## 目标
在真机或模拟器上把 WebDriverAgent 跑起来，确认服务可用，并创建后续交互所需的 session。

## 启动前检查
- Xcode 与 Command Line Tools 可用。
- 真机场景额外确认 `ios-deploy` 与 `iproxy` 可用。
- 对真机使用唯一 Bundle ID 和有效的开发团队 ID，避免常见的签名冲突。
- 真机场景先对齐设备 ID：以 `xcrun xctrace list devices` 和 `xcodebuild` 可用 destination 中实际在线的设备为准，不直接复用 `xcodebuildmcp`、`go-ios` 或旧日志里的历史 UDID。
- 真机场景在重建端口转发前先检查 `8100` 是否已有监听，避免旧 `iproxy` 仍把本机端口绑到别的设备。

## 真机标准流程
1. 用 Xcode 原生命令 `xcrun xctrace list devices` 确认 Xcode 实际可见且在线的设备 ID；如果其他工具显示不同 UDID，以这里和 `xcodebuild` destination 可用列表为准。
2. 启动前检查本机 `8100` 端口：`lsof -nP -iTCP:8100 -sTCP:LISTEN`；如果已有旧监听，先用 `ps` 确认它是否仍指向目标设备，不是则先清理。
3. 已有可用构建时优先 `test-without-building`；没有构建产物时使用完整 `test`。
4. 为 USB 连接建立端口转发：`iproxy -u <UDID> 8100:8100`。
5. 用 `GET /status` 或 `GET /wda/healthcheck` 确认 WDA 已经起来；如果 TCP 已连通但被对端 `connection reset by peer`，优先怀疑转发目标错误或目标设备上没有对应 WDA。
6. 发送 `POST /session` 创建 session，并保存 `sessionId`。

## 设备 ID 对齐与端口转发检查

推荐最短检查顺序：

1. `xcrun xctrace list devices`：确认 Xcode 当前能操作的真机。
2. `xcodebuild` 或 `xcodebuildmcp device test` 的 destination 列表：确认 WDA 实际能启动到哪台设备。
3. `lsof -nP -iTCP:8100 -sTCP:LISTEN` 与 `ps -p <PID> -o pid=,comm=,args=`：确认本机 `8100` 是否被旧 `iproxy` 占用，以及它到底转发到哪台设备。

如果三者不一致，处理原则：
- 以 Xcode 可见且能出现在 destination 里的在线设备为准。
- 不沿用历史命令中的 UDID，哪怕它在别的工具里还能列出来。
- 发现旧 `iproxy` 指向错误设备时，先清掉旧监听，再建立新的 `iproxy -u <UDID> 8100:8100`。

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

## 常见参数与归属

| 字段 | 归属 | 作用 | 何时使用 |
| --- | --- | --- | --- |
| `platformName` | 裸 WDA 通用 | 指定平台 | 创建 session 时通常都会传 |
| `deviceName` | 裸 WDA 通用 | 标记目标设备名称 | 需要补充设备描述时 |
| `bundleId` | 裸 WDA 直连常用 | 冷启动目标应用 | 已知包名且不传 `.app` 路径时 |
| `app` | 裸 WDA 直连常用 | 安装或启动指定应用包 | 本地有 `.app` 或 `.ipa` 时 |
| `udid` | 裸 WDA 直连常用 | 绑定具体设备 | 多设备并行或真机场景 |

如果你是直接对 WDA 的 `POST /session` 发请求，参考上面的示例使用无前缀字段

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
2. 如果 `curl` 已连接 `8100` 但被 `connection reset by peer`，先检查本机端口监听和 `iproxy` 目标设备，而不是直接重跑更多 WDA 命令。
3. 服务可通但 `POST /session` 失败时，先精简 capabilities，再检查 App 路径或包名。
4. 真机若仍失败，优先检查签名、开发团队 ID、唯一 Bundle ID 与设备信任状态。
