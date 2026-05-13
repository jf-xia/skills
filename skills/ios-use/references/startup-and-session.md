# 启动与 Session

## 目标
在真机或模拟器上把 WebDriverAgent 跑起来，确认服务可用，并创建后续交互所需的 session。

## 脚本化快速路径

### 最简流程（推荐）

```bash
# 1. 创建 session 并启动应用（自动处理所有初始化）
bash skills/ios-use/scripts/ios_wda_session.sh --bundle-id com.apple.Preferences

# 2. 获取页面源码
curl -s http://<DEVICE_IP>:8100/session/<SESSION_ID>/source | jq '.value'
```

### 分步流程

```bash
# 1. 初始化（检查设备、启动 iproxy、启动 WDA）
bash skills/ios-use/scripts/ios_wda_init.sh

# 2. 创建 session
bash skills/ios-use/scripts/ios_wda_session.sh --bundle-id com.apple.Preferences

# 3. 获取页面信息
bash skills/ios-use/scripts/ios_wda_snapshot.sh
```

## 脚本说明

### ios_wda_init.sh

负责初始化所有组件：
- 检查设备连接状态
- 启动或复用 iproxy
- 启动或复用 WDA
- 等待 WDA ready
- 更新缓存文件

**用法：**
```bash
bash skills/ios-use/scripts/ios_wda_init.sh [OPTIONS]
```

**选项：**
- `--udid <UDID>`: 指定设备 UDID
- `--host <HOST>`: 指定 WDA 主机（默认 127.0.0.1）
- `--port <PORT>`: 指定 WDA 端口（默认 8100）
- `--project-path <PATH>`: 指定 WebDriverAgent 项目路径
- `--scheme <SCHEME>`: 指定 scheme（默认 WebDriverAgentRunner）
- `--max-wait <SECONDS>`: 等待 WDA ready 的最大秒数（默认 60）

**输出示例：**
```json
{
  "ok": true,
  "device": {
    "name": "iPhone",
    "udid": "00008140-001465202E10801C",
    "ip": "192.168.1.107"
  },
  "connection": {
    "host": "192.168.1.107",
    "port": 8100,
    "listenerPid": 55289
  },
  "wda": {
    "ready": true,
    "runDir": "./tmp/260513210741"
  }
}
```

### ios_wda_session.sh

负责创建或复用 session，并激活应用。

**用法：**
```bash
bash skills/ios-use/scripts/ios_wda_session.sh [OPTIONS]
```

**选项：**
- `--bundle-id <BUNDLE_ID>`: 要启动的应用 bundle ID
- `--udid <UDID>`: 指定设备 UDID
- `--host <HOST>`: 指定 WDA 主机
- `--port <PORT>`: 指定 WDA 端口
- `--force-new`: 强制创建新 session
- `--delete`: 删除现有 session
- `--session-id <SESSION_ID>`: 使用指定的 session ID

**输出示例：**
```json
{
  "ok": true,
  "action": "created",
  "sessionId": "90F28444-A1FC-4FA6-BAF1-F0584F2B9E14",
  "bundleId": "com.apple.Preferences",
  "activeApp": {
    "value": {
      "bundleId": "com.apple.Preferences"
    }
  }
}
```

## 缓存文件约定

- 缓存文件路径固定为 `./tmp/ios-use-cache.json`
- 缓存字段：
  - `device.udid`、`device.name`、`device.osVersion`
  - `connection.listenerPid`、`connection.listenerTargetUdid`、`connection.port`、`connection.deviceIp`
  - `wda.ready`、`wda.projectPath`、`wda.scheme`
  - `session.id`、`session.bundleId`、`session.activeApp`
  - `artifacts.lastRunDir`

## 缓存复用策略

缓存至少记录：最近一次可用的真机 UDID、本机 `8100` 监听信息、设备 IP、WDA 状态、最近一次 session、最近一次截图输出目录。

复用缓存前必须通过脚本校验，不直接相信缓存本身：
- 缓存里的 UDID 仍然出现在 `xcrun xctrace list devices` 的在线设备里
- 本机 `8100` 的监听进程仍然存在，且目标 UDID 与缓存一致
- `GET /status` 仍返回 `ready=true`

只要上述三项有一项不成立，就认为缓存不可直接复用，先修复转发，再决定是否重新拉起 WDA。

## WiFi 连接场景

当设备通过 WiFi 连接时：

1. **自动检测设备 IP**：脚本会从 WDA 状态响应中提取设备 IP
2. **直接连接设备 IP**：如果 iproxy 不可用，会尝试直接连接设备 IP
3. **缓存设备 IP**：设备 IP 会保存到缓存中，以便后续使用

**手动指定设备 IP：**
```bash
bash skills/ios-use/scripts/ios_wda_init.sh --host 192.168.1.107
```

## 启动前检查

- Xcode 与 Command Line Tools 可用
- 真机场景额外确认 `ios-deploy` 与 `iproxy` 可用
- 对真机使用唯一 Bundle ID 和有效的开发团队 ID，避免常见的签名冲突
- 真机场景先对齐设备 ID：以 `xcrun xctrace list devices` 和 `xcodebuild` 可用 destination 中实际在线的设备为准

## 真机标准流程

1. 用 Xcode 原生命令 `xcrun xctrace list devices` 确认 Xcode 实际可见且在线的设备 ID
2. 运行 `ios_wda_init.sh` 进行初始化
3. 运行 `ios_wda_session.sh` 创建 session
4. 使用 `ios_wda_snapshot.sh` 获取页面信息
5. 通过 WDA API 进行元素交互

## 模拟器差异

- 设备枚举通常使用 `xcrun simctl list devices`
- 模拟器不需要真机签名和 `iproxy`
- 如果需要冷启动或重置环境，优先配合 `simctl` 管理器状态

## Session 创建示例

```bash
# 创建 session 并启动 Settings 应用
bash skills/ios-use/scripts/ios_wda_session.sh --bundle-id com.apple.Preferences

# 创建 session 并启动 Safari
bash skills/ios-use/scripts/ios_wda_session.sh --bundle-id com.apple.mobilesafari

# 强制创建新 session
bash skills/ios-use/scripts/ios_wda_session.sh --bundle-id com.apple.Preferences --force-new
```

## 健康检查接口

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/status` | 返回 WDA 状态与版本信息 |
| `GET` | `/wda/healthcheck` | 轻量健康检查，无需 session |
| `GET` | `/session` | 查询活动 session |
| `DELETE` | `/session` | 结束当前会话 |

## 启动完成标准

- WDA 的状态接口返回成功
- 真机场景下，端口转发已经建立且 `curl http://localhost:8100/status` 可访问
- 创建 session 成功，并保存了 `sessionId`
- 如果后续需要操作 App，已确认目标 App 的 `bundleId`、安装状态和前台状态

## 失败时的最短回退路径

1. 先查 `/status`；如果服务不通，回到 WDA 启动步骤
2. 如果 `curl` 已连接 `8100` 但被 `connection reset by peer`，先检查本机端口监听和 `iproxy` 目标设备
3. 服务可通但 `POST /session` 失败时，先精简 capabilities，再检查 App 路径或包名
4. 真机若仍失败，优先检查签名、开发团队 ID、唯一 Bundle ID 与设备信任状态
5. 如果缓存文件存在，但脚本输出 `ok != true`，优先信任实时检查结论

## 常用命令

```bash
# 检查设备
xcrun xctrace list devices

# 检查 WDA 状态
curl -s http://<DEVICE_IP>:8100/status | jq '.value.ready'

# 检查 session
curl -s http://<DEVICE_IP>:8100/session | jq '.'

# 获取页面源码
curl -s http://<DEVICE_IP>:8100/session/<SESSION_ID>/source | jq '.value'

# 获取截图
curl -s http://<DEVICE_IP>:8100/session/<SESSION_ID>/screenshot | jq -r '.value' | base64 --decode > screenshot.png

# 清理进程
pkill -f "xcodebuild.*WebDriverAgent"
pkill -f "iproxy.*8100"
```
