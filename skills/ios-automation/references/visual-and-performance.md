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

## 扩展能力

以下能力适合作为可选增强，不应替代主路径中的结构化交互：

| 能力 | 典型场景 | 注意事项 |
| --- | --- | --- |
| 生物识别模拟 | 登录、支付、权限确认等 Face ID / Touch ID 流程 | 通常依赖模拟器或上层驱动扩展，不属于所有 WDA REST 实现的固定能力 |
| `viewportScreenshot` | 需要排除状态栏、导航栏等干扰区域时 | 常由上层驱动提供，不保证是裸 WDA 的标准 REST 接口 |
| 原始 REST 请求 | SDK 未封装的路由、版本差异接口、快速试探 | 先确认当前服务版本支持对应端点，避免把试探性请求误当成固定能力 |

使用原则：
- 先走 `/source`、元素 API 和 `/screenshot` 主路径，只有主路径信息不足时再启用扩展能力。
- 扩展能力一旦失败，优先回退到稳定主路径，而不是继续堆叠实验性接口。

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

配置示例：

```bash
# 真机控制端口
iproxy 8100 8100 <UDID>

# MJPEG 画面流端口
iproxy 9100 9100 <UDID>
```

使用建议：
- 只有在需要连续画面分析时才开启 9100 端口转发，避免引入额外进程和资源占用。
- 如果只需要动作后的离散确认，优先使用 `/screenshot`，恢复成本更低。

## 何时切换策略
- 页面树稳定、节点可访问：使用结构化接口。
- 节点不可访问、样式复杂、视觉目标明显：切换到截图加坐标。
- 页面动画频繁：先降低节奏或关闭部分等待，再决定是否改为视觉闭环。

## 完成检查
- 性能参数调整后，确认是否引入误点、漏判或动作抢跑。
- 不要只看吞吐；同时检查成功率和恢复成本。