# 故障排查

## 最短检查

1. `GET /status` 返回 200？
2. 需要 session 时，`POST /session` 成功？
3. 元素操作失败 → 页面是否已刷新/滚动/弹窗切换？
4. 输入失败 → 键盘是否可见？控件类型是否正确？

## 故障矩阵

| 症状 | 原因 | 动作 |
|------|------|------|
| `xcodebuild` Code 65 | 签名错误/Bundle ID 冲突/团队 ID 缺失 | 修复签名、改唯一 Bundle ID、确认开发团队 |
| `/status` 无响应 | WDA 未启动/端口未转发 | 重启 WDA，检查 `iproxy 8100 8100 <UDID>` |
| `connection reset by peer` | 端口被旧转发占用/iproxy 指向错误设备 | `lsof` + `ps` 确认 8100 监听者与目标设备 |
| `iproxy` 打印 `New connection` | 正常流量日志 | 先看 `/status` 是否 200 |
| 设备不存在（其他工具可列） | 工具枚举口径不同 | 回到 `xcrun xctrace list devices` 取 Xcode 可见设备 |
| `Session Not Created` | 能力集错误/App 路径无效 | 精简 capabilities，确认 bundleId/app/udid |
| `No Such Driver` / 404 | Session 失效 | 重建 session，不复用旧 ID |
| `Element Not Visible` | 元素在屏外/被遮挡/动画未结束 | 先滚动或等待稳定 |
| `Stale Element Reference` | 页面树变化 | 重新获取 source 并重新查找 |
| `Timeout` / 408 | 页面过慢/等待条件不合理 | 拉长超时、拆分动作、减少全树扫描 |
| 输入无效 | 未聚焦/键盘未起/控件特殊 | 先点击聚焦，再用正确接口 |
| PickerWheel 值越调越偏 | 当成普通输入框处理 | 改用专用路由，一次只改一个 wheel |
| `activate` 返回成功但前台是 SpringBoard | App 未运行/系统 App 激活链路问题 | 查 `/wda/activeAppInfo`，必要时 `ios launch` |
| 截图出现 shield/blocked | 系统策略拦截 | 读页面树确认遮罩内容 |
| 缓存存在但无法继续 | UDID/iproxy/sessionId 失效 | 跑 `ios_wda_init.sh`，按输出重建 |
| 输入成功但内容不一致 | App 自动格式化 | 先区分是否应用层改写 |

## 错误码

| HTTP | 异常 | 动作 |
|------|------|------|
| 400 | `FBInvalidArgumentException` | 检查 JSON 结构、字段名/类型/取值范围 |
| 404 | `FBSessionDoesNotExistException` | 重建 session |
| 408 | `FBTimeoutException` | 确认页面状态，延长等待或拆分动作 |
| 500 | `FBSessionCreationException` | 精简 capabilities，检查 bundleId/app/udid |
| 500 | `FBApplicationCrashedException` | 重新拉起应用，保留日志与截图 |
| 400 | `FBElementNotVisibleException` | 滚动、等待稳定或切换定位策略 |
| 404 | `FBStaleElementException` | 重读 `/source`，重新定位 |

优先按 HTTP 状态码判断恢复路径，再结合错误文本细化。

## 自愈顺序

1. 原位重试一次（仅偶发点击/输入失败）
2. 重拉 `/source` 或截图，确认页面是否变化
3. 重建元素定位，不复用旧 UUID
4. 重建 session
5. 重启 WDA（真机同时检查签名、端口转发、设备信任）
6. 缓存失效 → 清理 `./tmp/ios-use-cache.json`，重新走脚本预检

## 真机专项

- 先用 `xcrun xctrace list devices` 确认设备在线
- UDID 以 Xcode 当前可见 destination 为准
- 已构建过 WDA → 优先 `test-without-building`，失败再 `test`
- 并行任务确认端口和 iproxy 无冲突
- 单设备也要检查本机 8100 是否残留旧 iproxy

## 诊断命令

```bash
xcrun xctrace list devices                        # 设备在线
lsof -i :8100                                      # 端口监听
ps aux | grep iproxy                               # iproxy 进程
curl -s http://127.0.0.1:8100/status               # WDA 状态（本地）
curl -s http://<DEVICE_IP>:8100/status             # WDA 状态（设备 IP）
cat ./tmp/ios-use-cache.json | jq '.'              # 缓存内容
cat ./tmp/*/wda-background.log                     # WDA 日志
```

## 代码库追问

深度问题可用 `dw` CLI 问 WebDriverAgent 代码库：

```bash
dw aq -r "appium/WebDriverAgent" -q "POST /session 经过哪些 handler"
dw aq -r "appium/WebDriverAgent" -q "element/:uuid/value 的 frequency 参数如何生效"
dw aq -r "appium/WebDriverAgent" -q "No Such Driver 从哪里抛出"
dw aq -r "appium/WebDriverAgent" -q "accessibleSource 和 source 的生成路径差异"
```

## 诊断信息保留

设备 UDID、平台类型、WDA 端口、sessionId、最近一次错误文本、失败前后 source/截图、使用的 capabilities。
