# WDA 命令参考

## 使用原则
- 先确认 `GET /status` 可用，再调用需要 session 的接口。
- 优先使用元素级接口，只有在没有稳定元素时才退回坐标点击。
- 简单手势和元素坐标使用元素左上角为基准；与 W3C Actions 的中心点语义不同。

## 坐标参考系

### 屏幕绝对坐标
- 原点在屏幕左上角 `(0, 0)`。
- `x` 向右递增，`y` 向下递增。
- 适用于 `/wda/tap`、`/wda/swipe`、`/wda/dragfromtoforduration` 这类直接传坐标的操作。

### 元素相对坐标
- 当请求同时绑定元素和偏移量时，偏移基准是元素边界左上角。
- 这与部分 W3C Actions 实现使用元素中心点为基准的语义不同。
- 如果视觉模型输出的是元素中心点，换算到 WDA 简单手势前，先减去元素左上角坐标再作为偏移量使用。

### 常见误区
- 不要把截图中的绝对坐标直接当作元素相对偏移。
- 不要把 W3C Actions 的中心点语义直接套到 `/wda/tap` 一类简单手势上。
- 如果点击稳定偏移半个元素宽高，优先排查是否把中心点误当成左上角偏移。

## Session 与健康检查

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| `POST` | `/session` | 创建会话，返回 `sessionId` 与能力集 |
| `DELETE` | `/session` | 结束当前会话 |
| `GET` | `/session` | 查询当前活动会话 |
| `GET` | `/status` | 查询 WDA 服务状态，无需 session |
| `GET` | `/wda/healthcheck` | 轻量健康检查，无需 session |

## 元素属性与基础动作

| 类别 | 方法 | 路径 | 说明 |
| --- | --- | --- | --- |
| 属性 | `GET` | `/element/:uuid/text` | 获取文本；常用于读取 label 或 value |
| 属性 | `GET` | `/element/:uuid/rect` | 获取位置与尺寸 |
| 属性 | `GET` | `/element/:uuid/enabled` | 获取可用状态 |
| 属性 | `GET` | `/element/:uuid/displayed` | 获取可见状态 |
| 属性 | `GET` | `/element/:uuid/selected` | 获取选中状态 |
| 属性 | `GET` | `/element/:uuid/attribute/:name` | 读取任意 WebDriver 属性 |
| 动作 | `POST` | `/element/:uuid/click` | 点击元素 |
| 动作 | `POST` | `/element/:uuid/clear` | 清空文本 |
| 动作 | `POST` | `/element/:uuid/value` | 输入文本或设置可调元素值 |

元素输入示例：

```bash
curl -X POST http://localhost:8100/session/$SESSION_ID/element/$ELEMENT_ID/value \
	-H "Content-Type: application/json" \
	-d '{"value": ["hello"], "frequency": 30}'
```

## 简单手势接口

| 方法 | 路径 | 关键参数 | 说明 |
| --- | --- | --- | --- |
| `POST` | `/wda/tap` | `x`, `y` 可选 | 点击坐标或目标元素 |
| `POST` | `/wda/doubleTap` | `x`, `y` 可选 | 双击 |
| `POST` | `/wda/twoFingerTap` | 元素或坐标 | 双指点击 |
| `POST` | `/wda/tapWithNumberOfTaps` | `numberOfTaps`, `numberOfTouches` | 自定义点击次数 |
| `POST` | `/wda/touchAndHold` | `duration`, `x`, `y` | 长按 |
| `POST` | `/wda/swipe` | `direction`, `velocity` | 滑动 |
| `POST` | `/wda/pinch` | `scale`, `velocity` | 捏合 |
| `POST` | `/wda/rotate` | `rotation`, `velocity` | 旋转 |
| `POST` | `/wda/dragfromtoforduration` | `fromX`, `fromY`, `toX`, `toY`, `duration` | 拖拽 |
| `POST` | `/wda/forceTouch` | `pressure`, `duration`, `x`, `y` | 压感触控 |
| `POST` | `/wda/scroll` | `direction`, `distance` 或 `name` / `predicateString` | 滚动或滚到目标 |

滑动示例：

```bash
curl -X POST http://localhost:8100/session/$SESSION_ID/wda/swipe \
	-H "Content-Type: application/json" \
	-d '{"direction": "up", "velocity": 1200}'
```

滚动示例：

```bash
curl -X POST http://localhost:8100/session/$SESSION_ID/wda/scroll \
	-H "Content-Type: application/json" \
	-d '{"predicateString": "label BEGINSWITH \"Item\""}'
```

## 页面与调试接口

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/source` | 获取页面树，支持 `format=xml|json|description` |
| `GET` | `/wda/accessibleSource` | 获取仅包含可访问元素的简化树 |
| `GET` | `/screenshot` | 获取 Base64 全屏截图；可在无 session 时使用 |

页面源码示例：

```bash
curl "http://localhost:8100/session/$SESSION_ID/source?format=json"
```

## 应用与设备控制索引
- 应用生命周期、弹窗、锁屏、方向、位置和设备信息，见 `./app-and-device-control.md`。
- 文本输入、键盘策略和频率参数，见 `./input-and-keyboard.md`。
- 性能参数与视觉闭环策略，见 `./visual-and-performance.md`。
