# 限制与取舍

## 会话边界
- 除 `POST /session`、`GET /status`、`GET /wda/healthcheck` 外，大多数接口都要求活动 session。
- `GET /screenshot` 通常可在无 session 时使用，但不要把它当作 session 存活的证明。
- 一旦收到 `No Such Driver` 或 session 失效，优先重建 session，而不是继续复用旧元素 ID。

## 平台差异
- 真机需要代码签名、唯一 Bundle ID、开发团队 ID，模拟器通常不需要。
- `iproxy` 只在真机 USB 转发场景需要；模拟器直接访问本机端口即可。
- tvOS 的输入和清空能力弱于 iOS；不要默认假设键盘激活、清空重试或特殊键映射都可用。
- 模拟位置依赖 iOS 16.4+ 与 Xcode 14.3+，且底层使用私有测试守护进程接口。

## 交互语义限制
- WDA 的简单手势坐标相对元素左上角；W3C Actions 常以元素中心点为基准，两者不要混用。
- XPath 在复杂页面上成本高且稳定性差；优先使用 accessibility id、predicate 或 class chain。
- 页面动画、懒加载和不可访问容器会让 `displayed`、`visible` 和点击命中结果不稳定。
- 元素 ID 来自当前快照缓存；页面刷新、滚动重排或弹窗切换后，旧 ID 可能立即失效。

## 输入限制
- `/element/:uuid/value` 依赖元素可聚焦；如果键盘未出现，先触发焦点，再输入。
- `/wda/keys` 只向当前焦点发键盘事件，不做焦点管理。
- PickerWheel、Slider 等控件并不按普通文本框处理，必须使用对应的值调整语义。

## 视觉与结构化策略取舍
- 有稳定无障碍树时优先结构化接口；没有稳定节点时再切换到截图加坐标。
- 视觉驱动适合闭环确认，但不适合替代所有结构化状态读取。
- 频繁全屏截图会显著拉低吞吐；长时任务优先考虑 MJPEG 流或降低截图频率。

## 并发与环境限制
- 多设备并行时必须为每台设备分配独立的 `wdaLocalPort` 与端口转发。
- `waitForQuiescence: false` 可以提速，但会放大动画期误点与状态未稳定的问题。
- `simpleIsVisibleCheck: true` 能加快扫描，但会降低某些复杂可见性判断的保真度。
