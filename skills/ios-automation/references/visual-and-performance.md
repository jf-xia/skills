# 视觉驱动与性能

## 结构化感知优先级
1. `GET /source`：默认首选，适合获取完整页面树。
2. `GET /wda/accessibleSource`：当页面树过大时，优先获取仅含可访问元素的精简结构。
3. `GET /screenshot`：当无障碍信息不足、坐标必须由视觉判断时使用。

`/source` 常用参数：
- `format=xml|json|description`
- `excluded_attributes=visible,enabled`
- `scope=<value>`

示例：

```bash
curl "http://localhost:8100/session/$SESSION_ID/source?format=xml&excluded_attributes=frame"
```

## 视觉闭环
1. Observe：截图或拉取页面树。
2. Plan：根据文本、结构或视觉结果决定目标位置。
3. Act：调用点击、输入、滚动等接口。
4. Check：再次截图、读取 source 或应用状态，确认动作已生效。

当结构化信息不足时，这个闭环比单次截图加坐标点击更稳。

## 直接 REST 请求
高阶代理可以把 WDA 当作原始 REST 服务直接调用，以减少 SDK 封装带来的额外开销。

```javascript
await agent.runWdaRequest('GET', '/wda/getPasteboard')
```

适用场景：
- 当前 SDK 没有暴露所需接口。
- 需要快速试探某个自定义或版本差异接口。
- 需要把视觉推理结果直接翻译为底层请求。

## 性能调优参数

| 目标 | 参数 | 典型效果 |
| --- | --- | --- |
| 提高扫描速度 | `appium:simpleIsVisibleCheck: true` | 降低可见性计算成本 |
| 规避慢设备超时 | `appium:wdaConnectionTimeout: 240000` | 为低性能真机留足响应时间 |
| 减少动作等待 | `appium:waitForQuiescence: false` | 不等待动画完全静止 |
| 多设备并行 | `appium:wdaLocalPort` | 避免本地端口冲突 |

## MJPEG 与端口转发
- WDA 的 MJPEG 流常用 9100 端口，适合低延迟连续画面分析。
- 真机使用 MJPEG 时，同样需要显式处理端口转发。
- 如果只做离散验证，`/screenshot` 更简单；只有在动态追踪或高频画面分析时才需要 MJPEG。

## 何时切换策略
- 页面树稳定、节点可访问：使用结构化接口。
- 节点不可访问、样式复杂、视觉目标明显：切换到截图加坐标。
- 页面动画频繁：先降低节奏或关闭部分等待，再决定是否改为视觉闭环。

## 完成检查
- 性能参数调整后，确认是否引入误点、漏判或动作抢跑。
- 不要只看吞吐；同时检查成功率和恢复成本。