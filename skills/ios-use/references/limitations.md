# 限制与取舍

## 会话边界

- 大多数接口要求活动 session；`/status`、`/wda/healthcheck`、`/screenshot` 可无 session 使用
- `/screenshot` 无 session 可用但不能证明 session 存活
- 收到 `No Such Driver` → 重建 session，不复用旧元素 ID

## 平台差异

| 方面 | 真机 | 模拟器 | tvOS |
|------|------|--------|------|
| 代码签名 | 需要（唯一 Bundle ID + 团队 ID） | 不需要 | — |
| iproxy | USB 转发需要 | 不需要 | — |
| 输入/清空 | 完整 | 完整 | 较弱 |
| 模拟位置 | iOS 16.4+ / Xcode 14.3+ | 支持 | — |

## 交互语义

- WDA 简单手势坐标相对**元素左上角**；W3C Actions 以**元素中心**为基准，不混用
- 优先 accessibility id / predicate / class chain；XPath 成本高、稳定性差
- 页面动画、懒加载、不可访问容器会让 `displayed`/`visible`/点击命中不稳定
- 元素 ID 来自快照缓存；页面刷新/滚动/弹窗切换后旧 ID 可能立即失效

## 输入限制

- `/element/:uuid/value` 依赖元素可聚焦；键盘未出现时先触发焦点
- `/wda/keys` 只发键盘事件，不做焦点管理
- PickerWheel/Slider 不按普通文本框处理，必须使用专用值调整语义

## 视觉与结构化取舍

- 有稳定无障碍树 → 结构化接口；无稳定节点 → 截图+坐标
- 视觉适合闭环确认，不适合替代所有结构化状态读取
- 频繁全屏截图拉低吞吐；长时任务优先 MJPEG 流或降低截图频率

## 并发限制

- 多设备并行 → 每台分配独立 `wdaLocalPort` 与端口转发
- `waitForQuiescence: false` 提速但放大动画期误点
- `simpleIsVisibleCheck: true` 加速但降低可见性判断保真度
