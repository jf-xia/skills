# 启动与 Session

## 目标
在真机或模拟器上把 WebDriverAgent 跑起来，确认服务可用，并创建后续交互所需的 session。

## 脚本化快速路径
如果目标是尽快开始操作，而不是手动拼接所有检查命令，优先按下面执行：

```bash
bash skills/ios-use/scripts/ios_wda_preflight.sh --ensure-forward --run-dir ./tmp/<timestamp>
bash skills/ios-use/scripts/ios_wda_session.sh --bundle-id com.apple.mobilenotes --run-dir ./tmp/<timestamp>
```

说明：
- 第一条命令会优先读取 `./tmp/ios-use-cache.json`，验证缓存里的 UDID、`8100` 监听和 WDA 健康状态。
- 只有缓存不可直接复用时，它才会把 `nextAction` 标成 `rebuild-forward`、`launch-wda` 或 `inspect-wda-log`。
- 当 WDA 不可用时，脚本会先自动尝试 `xcodebuild -project <project> -scheme <scheme> -destination "id=<UDID>" test-without-building`；只有这一步失败时才回退到完整 `xcodebuild ... test`。
- 对 `test-without-building` 和 `test` 这两条长命令，脚本不会等待 `xcodebuild` 自行退出，而是后台拉起后轮询 `/status`；只要 WDA 已 ready，就立刻返回给后续步骤继续使用。
- 第二条命令优先复用已经校验过的 session；复用失败时再创建新的 session。
- 同一个 `--run-dir` 下的落盘文件会按动作顺序自动编号，方便回看完整时间线。

## 缓存文件约定
- 缓存文件路径固定为 `./tmp/ios-use-cache.json`。
- 建议缓存字段：
  - `device.udid`、`device.name`、`device.osVersion`
  - `connection.listenerPid`、`connection.listenerTargetUdid`、`connection.port`
  - `wda.ready`、`wda.status`
  - `session.id`、`session.bundleId`
  - `artifacts.lastRunDir`
- 缓存命中不等于可复用；是否可复用以脚本实时验证结果为准。

## 缓存复用策略
- 缓存至少记录：最近一次可用的真机 UDID、本机 `8100` 监听信息、WDA 状态、最近一次 session、最近一次截图输出目录。
- 复用缓存前必须通过脚本校验，不直接相信缓存本身：
	- 缓存里的 UDID 仍然出现在 `xcrun xctrace list devices` 的在线设备里。
	- 本机 `8100` 的监听进程仍然存在，且目标 UDID 与缓存一致。
	- `GET /status` 仍返回 `ready=true`。
- 只要上述三项有一项不成立，就认为缓存不可直接复用，先修复转发，再决定是否重新拉起 WDA。
- 不要把一次失败后的 `sessionId` 当成长期可信数据；session 只能校验后复用，不能盲用。

## 启动前检查
- Xcode 与 Command Line Tools 可用。
- 真机场景额外确认 `ios-deploy` 与 `iproxy` 可用。
- 对真机使用唯一 Bundle ID 和有效的开发团队 ID，避免常见的签名冲突。
- 真机场景先对齐设备 ID：以 `xcrun xctrace list devices` 和 `xcodebuild` 可用 destination 中实际在线的设备为准，不直接复用 `xcodebuildmcp`、`go-ios` 或旧日志里的历史 UDID。
- 真机场景在重建端口转发前先检查 `8100` 是否已有监听，避免旧 `iproxy` 仍把本机端口绑到别的设备。

## 真机标准流程
1. 用 Xcode 原生命令 `xcrun xctrace list devices` 确认 Xcode 实际可见且在线的设备 ID；如果其他工具显示不同 UDID，以这里和 `xcodebuild` destination 可用列表为准。
2. 启动前优先运行 `ios_wda_preflight.sh`；只有在脚本判定缓存失效时，才手动检查本机 `8100` 端口和 `ps`。
3. 已有可用构建时优先 `test-without-building`；没有构建产物时使用完整 `test`。
4. 为 USB 连接建立端口转发：`iproxy -u <UDID> 8100:8100`。
5. 用 `GET /status` 或 `GET /wda/healthcheck` 确认 WDA 已经起来；如果 TCP 已连通但被对端 `connection reset by peer`，优先怀疑转发目标错误或目标设备上没有对应 WDA。
6. 发送 `POST /session` 创建 session，并保存 `sessionId`。

补充说明：
- `iproxy` 日志里连续出现 `New connection for 8100->8100` 和 `Requesting connection to USB device handle ...`，通常只是本机在连续请求 `/status`、`/screenshot`、`/source` 等接口。
- 如果这些日志同时伴随 `curl /status` 成功返回 200，说明转发本身在工作，不要因为日志频繁就误判为 `iproxy` 异常。
- 只有在本机 `8100` 不再监听、请求超时，或请求结果明确失败时，才把问题归类为需要重建转发。

## 设备 ID 对齐与端口转发检查

推荐最短检查顺序：

1. `xcrun xctrace list devices`：确认 Xcode 当前能操作的真机。
2. `xcodebuild` 或 `xcodebuildmcp device test` 的 destination 列表：确认 WDA 实际能启动到哪台设备。
3. `lsof -nP -iTCP:8100 -sTCP:LISTEN` 与 `ps -p <PID> -o pid=,comm=,args=`：确认本机 `8100` 是否被旧 `iproxy` 占用，以及它到底转发到哪台设备。

如果三者不一致，处理原则：
- 以 Xcode 可见且能出现在 destination 里的在线设备为准。
- 不沿用历史命令中的 UDID，哪怕它在别的工具里还能列出来。
- 发现旧 `iproxy` 指向错误设备时，先清掉旧监听，再建立新的 `iproxy -u <UDID> 8100:8100`。
- 如果 `./tmp/ios-use-cache.json` 中记录的 `listenerTargetUdid` 与当前在线目标设备不一致，直接判定缓存不可复用。

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
5. 如果缓存文件存在，但脚本输出 `nextAction != reuse`，优先信任实时检查结论，而不是强行沿用缓存里的旧 `sessionId` 或旧 UDID。
6. 如果自动 `test-without-building` 和完整 `test` 都失败，优先看 `tmp/<timestamp>/wda-test-without-building.log` 和 `tmp/<timestamp>/wda-test.log`，不要只看终端最后一行报错。
