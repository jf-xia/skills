# 启动与 Session

## 脚本化快速路径

```bash
# 最简（推荐）
bash skills/ios-use/scripts/ios_wda_session.sh --bundle-id com.apple.Preferences

# 分步
bash skills/ios-use/scripts/ios_wda_init.sh                    # 初始化
bash skills/ios-use/scripts/ios_wda_session.sh --bundle-id com.apple.Preferences  # session
bash skills/ios-use/scripts/ios_wda_snapshot.sh                 # 页面信息
```

## ios_wda_init.sh

检查设备 → 启动/复用 iproxy → 启动/复用 WDA → 更新缓存。

**参数：** `--udid` `--host`(默认127.0.0.1) `--port`(默认8100) `--project-path` `--scheme` `--max-wait`(默认60s)

**输出字段：** `ok`、`device.{name,udid,ip}`、`connection.{host,port,listenerPid}`、`wda.{ready,runDir}`

## ios_wda_session.sh

创建或复用 session，激活应用。

**参数：** `--bundle-id` `--udid` `--host` `--port` `--force-new` `--delete` `--session-id`

**输出字段：** `ok`、`action`(created|reused)、`sessionId`、`bundleId`、`activeApp`

## 缓存文件

路径固定：`./tmp/ios-use-cache.json`

字段：`device.{udid,name,osVersion}`、`connection.{listenerPid,listenerTargetUdid,port,deviceIp}`、`wda.{ready,projectPath,scheme}`、`session.{id,bundleId,activeApp}`、`artifacts.lastRunDir`

**复用策略：** 缓存前必须校验——UDID 在线、iproxy 存活且目标一致、`GET /status` 返回 ready。任一不成立则先修复。

## WiFi 连接

脚本自动从 WDA 状态响应提取设备 IP，缓存后供后续使用。手动指定：
```bash
bash skills/ios-use/scripts/ios_wda_init.sh --host 192.168.1.107
```

## 启动前检查

- Xcode + Command Line Tools 可用
- 真机：`ios-deploy` + `iproxy` 可用、签名有效、Bundle ID 唯一、开发团队 ID 正确
- 用 `xcrun xctrace list devices` 确认 Xcode 可见的在线设备

## 模拟器差异

- 枚举用 `xcrun simctl list devices`
- 不需要签名和 `iproxy`
- 冷启动/重置用 `simctl` 管理器状态

## 健康检查

| 接口 | 说明 |
|------|------|
| `GET /status` | WDA 状态，无需 session |
| `GET /wda/healthcheck` | 轻量健康检查 |
| `GET /session` | 查询活动 session |
| `DELETE /session` | 结束会话 |

## 启动完成标准

- `/status` 返回 ready
- `curl http://localhost:8100/status` 可访问（真机需端口转发）
- session 创建成功并保存 `sessionId`
- 目标 App 的 bundleId、安装状态、前台状态已确认

## 失败回退路径

1. `/status` 不通 → 回到 WDA 启动步骤
2. `connection reset by peer` → 检查本机端口监听和 iproxy 目标
3. `POST /session` 失败 → 精简 capabilities，检查 App 路径/包名
4. 真机仍失败 → 检查签名、团队 ID、设备信任
5. 缓存存在但脚本 `ok != true` → 信任实时检查结论
