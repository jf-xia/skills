# 故障排查

## 先做最短检查
1. `GET /status` 是否返回 200。
2. 如果需要 session，确认 `POST /session` 是否成功并保留了新的 `sessionId`。
3. 如果元素操作失败，确认页面是否已刷新、滚动或弹窗切换，避免复用旧元素 ID。
4. 如果输入失败，先判断键盘是否真的可见，再选择元素级输入还是 `/wda/keys`。

## 常见故障矩阵

| 症状 | 常见原因 | 优先动作 |
| --- | --- | --- |
| `xcodebuild` 启动失败或 Code 65 | 签名错误、Bundle ID 冲突、团队 ID 缺失 | 修复签名、改唯一 Bundle ID、确认开发团队 |
| `curl /status` 无响应 | WDA 未启动、端口未转发、`iproxy` 中断 | 重启 WDA，检查 `iproxy 8100 8100 <UDID>` |
| `Session Not Created` | 能力集错误、App 路径无效、设备未准备好 | 精简 capabilities，确认 `bundleId` / `app` / `udid` |
| `No Such Driver` / 404 | session 已失效 | 重建 session，不要继续用旧 `sessionId` |
| `Element Not Visible` | 元素在屏外、被遮挡、动画未结束 | 先滚动或等待稳定，再重试 |
| `Stale Element Reference` | 页面树变化，元素缓存失效 | 重新获取 source 并重新查找元素 |
| `Timeout` / 408 | 页面过慢、等待条件不合理 | 拉长连接超时，拆分动作，减少全树扫描 |
| 输入无效 | 未聚焦、键盘未起、控件类型特殊 | 先点击聚焦，再用正确输入接口 |

## 自愈顺序
1. 原位重试一次，仅适用于偶发点击或输入失败。
2. 重新拉取 `/source` 或截图，确认页面是否已变化。
3. 重建当前元素定位，不复用旧 UUID。
4. 重新创建 session。
5. 仍失败时，重启 WDA；真机同时检查签名、端口转发和设备信任状态。

## 真机专项问题
- 先用 Xcode 原生命令确认设备仍在线。
- 如果已构建过 WDA，优先 `test-without-building`；只有启动失败时再回退到完整 `test`。
- 对真机并行任务，确认本地端口和 `iproxy` 没有冲突。

## 输入与键盘专项问题
- 文本框无响应时，先确认元素是否已经成为第一响应者。
- 清空失败时，不要盲目循环；检查是否是 `PickerWheel`、`Slider` 或只读控件。
- 已有焦点但元素定位不稳定时，用 `/wda/keys` 代替元素级输入。

## 建议保留的诊断信息
- 设备 UDID、平台类型、WDA 端口和 `sessionId`
- 最近一次 `xcodebuild` 或 `curl` 的错误文本
- 失败前后的 `/source` 或截图
- 使用的关键 capabilities 与 settings
