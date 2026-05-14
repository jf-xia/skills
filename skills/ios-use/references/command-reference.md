# WDA 命令参考

## 使用原则

- 先确认 `GET /status` 可用，再调需要 session 的接口
- 优先元素级接口，无稳定元素时退回坐标点击
- 简单手势坐标基准是元素左上角；W3C Actions 以中心点为基准，两者不混用

## 坐标系

- **屏幕绝对坐标**：原点 `(0,0)` 左上角，x 右增，y 下增。用于 `/wda/tap`、`/wda/swipe`、`/wda/dragfromtoforduration`
- **元素相对坐标**：偏移基准是元素边界左上角（非中心）。视觉模型输出中心点时需先换算
- **常见误区**：不要把截图绝对坐标当元素偏移；不要把 W3C 中心点语义套到 `/wda/tap`

## Session 与健康检查

| 方法 | 路径 | 用途 |
|------|------|------|
| `POST` | `/session` | 创建会话 |
| `DELETE` | `/session` | 结束会话 |
| `GET` | `/session` | 查询活动会话 |
| `GET` | `/status` | 服务状态，无需 session |
| `GET` | `/wda/healthcheck` | 轻量健康检查 |

## 元素属性与动作

| 类别 | 方法 | 路径 | 说明 |
|------|------|------|------|
| 属性 | `GET` | `/element/:uuid/text` | 获取文本 |
| 属性 | `GET` | `/element/:uuid/rect` | 位置与尺寸 |
| 属性 | `GET` | `/element/:uuid/enabled` | 可用状态 |
| 属性 | `GET` | `/element/:uuid/displayed` | 可见状态 |
| 属性 | `GET` | `/element/:uuid/selected` | 选中状态 |
| 属性 | `GET` | `/element/:uuid/attribute/:name` | 任意属性 |
| 动作 | `POST` | `/element/:uuid/click` | 点击 |
| 动作 | `POST` | `/element/:uuid/clear` | 清空文本 |
| 动作 | `POST` | `/element/:uuid/value` | 输入文本 |

```bash
# 输入示例
curl -X POST http://localhost:8100/session/$SESSION_ID/element/$ELEMENT_ID/value \
  -H "Content-Type: application/json" -d '{"value": ["hello"], "frequency": 30}'
```

## PickerWheel

```bash
curl -X POST http://localhost:8100/session/$SESSION_ID/wda/pickerwheel/$ELEMENT_ID/select \
  -H "Content-Type: application/json" \
  -d '{"order": "next", "value": "11 o'clock", "maxAttempts": 8}'
```

- 优先用专用路由，不走 `/element/:uuid/value`
- 语义：每次调用先移动一格再判断是否达到目标值
- 已在目标值时继续调用可能拨离目标
- 多轮控件（如时间选择器）一次只改一个 wheel，关闭弹层后重新读取

## 简单手势

| 方法 | 路径 | 关键参数 | 说明 |
|------|------|----------|------|
| `POST` | `/wda/tap` | `x`, `y` | 点击坐标或元素 |
| `POST` | `/wda/doubleTap` | `x`, `y` | 双击 |
| `POST` | `/wda/twoFingerTap` | 元素或坐标 | 双指点击 |
| `POST` | `/wda/tapWithNumberOfTaps` | `numberOfTaps`, `numberOfTouches` | 自定义点击次数 |
| `POST` | `/wda/touchAndHold` | `duration`, `x`, `y` | 长按 |
| `POST` | `/wda/swipe` | `direction`, `velocity` | 滑动 |
| `POST` | `/wda/pinch` | `scale`, `velocity` | 捏合 |
| `POST` | `/wda/rotate` | `rotation`, `velocity` | 旋转 |
| `POST` | `/wda/dragfromtoforduration` | `fromX`, `fromY`, `toX`, `toY`, `duration` | 拖拽 |
| `POST` | `/wda/forceTouch` | `pressure`, `duration`, `x`, `y` | 压感触控 |
| `POST` | `/wda/scroll` | `direction`/`distance`/`name`/`predicateString` | 滚动 |

```bash
# 滑动
curl -X POST http://localhost:8100/session/$SESSION_ID/wda/swipe \
  -H "Content-Type: application/json" -d '{"direction": "up", "velocity": 1200}'

# 滚动到目标
curl -X POST http://localhost:8100/session/$SESSION_ID/wda/scroll \
  -H "Content-Type: application/json" -d '{"predicateString": "label BEGINSWITH \"Item\""}'
```

## 页面与调试

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/source` | 页面树，支持 `format=xml\|json\|description` |
| `GET` | `/wda/accessibleSource` | 精简可访问元素树 |
| `GET` | `/screenshot` | Base64 截图，可在无 session 时使用 |

```bash
curl "http://localhost:8100/session/$SESSION_ID/source?format=json"
```

## 应用与设备控制

| 类别 | 方法 | 路径 | 说明 |
|------|------|------|------|
| 应用 | `POST` | `/wda/apps/launch` | 启动应用 |
| 应用 | `POST` | `/wda/apps/activate` | 切到前台 |
| 应用 | `POST` | `/wda/apps/terminate` | 终止应用 |
| 应用 | `POST` | `/wda/apps/state` | 查询状态（1=未运行,4=前台） |
| 应用 | `POST` | `/wda/homescreen` | 返回主屏 |
| 应用 | `POST` | `/wda/pressButton` | 系统按键（home、音量等） |
| 弹窗 | `GET` | `/alert/text` | 读取弹窗文本 |
| 弹窗 | `POST` | `/alert/accept` | 接受弹窗 |
| 弹窗 | `POST` | `/alert/dismiss` | 关闭弹窗 |
| 弹窗 | `GET` | `/wda/alert/buttons` | 列出弹窗按钮 |
| 设备 | `POST` | `/wda/lock` | 锁屏 |
| 设备 | `POST` | `/wda/unlock` | 解锁 |
| 设备 | `GET/POST` | `/orientation` | 读取/设置方向 |
| 设备 | `POST` | `/wda/simulatedLocation` | 模拟位置（iOS 16.4+） |
| 设备 | `GET` | `/wda/screen` | 屏幕尺寸 |
| 设备 | `GET` | `/wda/device/info` | 设备信息 |
| 设备 | `GET` | `/wda/activeAppInfo` | 前台应用信息 |
| 设备 | `GET` | `/wda/batteryInfo` | 电量信息 |
| 设备 | `GET` | `/wda/device/location` | 设备地理位置 |

### 应用控制要点

- `/wda/apps/activate` 适合把已运行应用切回前台
- 回主屏优先 `/wda/homescreen`；`activate com.apple.springboard` 不可靠
- 激活后用 `/wda/activeAppInfo` 确认前台是否真正切换
- 截图出现 shield/blocked 覆盖层 → 系统策略拦截，非点击失败
