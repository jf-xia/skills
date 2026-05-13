# 应用与设备控制

## 应用生命周期

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `POST` | `/wda/apps/launch` | 启动应用，可带参数和环境变量 |
| `POST` | `/wda/apps/activate` | 将应用切到前台 |
| `POST` | `/wda/apps/terminate` | 终止应用，返回布尔值 |
| `POST` | `/wda/apps/state` | 查询应用状态 |
| `GET` | `/wda/apps/list` | 列出活动应用 |
| `POST` | `/url` | 打开 URL，可指定包名 |

应用状态枚举：

| 值 | 常量 | 含义 |
| --- | --- | --- |
| `1` | `XCUIApplicationStateNotRunning` | 未运行 |
| `2` | `XCUIApplicationStateRunningBackgroundSuspended` | 后台挂起 |
| `3` | `XCUIApplicationStateRunningBackground` | 后台运行 |
| `4` | `XCUIApplicationStateRunningForeground` | 前台运行 |

## 系统弹窗

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/alert/text` | 读取当前弹窗文本 |
| `POST` | `/alert/text` | 向弹窗输入文本 |
| `POST` | `/alert/accept` | 接受弹窗，可指定按钮名 |
| `POST` | `/alert/dismiss` | 关闭弹窗，可指定按钮名 |
| `GET` | `/wda/alert/buttons` | 列出弹窗按钮 |

如果权限弹窗是已知场景，可在 session 能力集中启用 `appium:autoAcceptAlerts`。

## 锁屏与方向

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `POST` | `/wda/lock` | 锁定屏幕 |
| `POST` | `/wda/unlock` | 解锁屏幕 |
| `GET` | `/wda/locked` | 查询是否已锁定 |
| `GET` | `/orientation` | 读取方向 |
| `POST` | `/orientation` | 设置方向 |
| `GET` | `/rotation` | 读取三轴旋转信息 |
| `POST` | `/rotation` | 设置三轴旋转 |

## 模拟位置

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `POST` | `/wda/simulatedLocation` | 设置经纬度 |
| `GET` | `/wda/simulatedLocation` | 读取当前模拟位置 |
| `DELETE` | `/wda/simulatedLocation` | 清除模拟位置 |

限制：仅 iOS 可用，且需要 iOS 16.4+ 与 Xcode 14.3+。

## 屏幕与设备信息

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/wda/screen` | 返回屏幕尺寸、状态栏尺寸与缩放比例 |
| `GET` | `/wda/device/info` | 返回 locale、时区、型号、UUID、UI 风格等信息 |
| `GET` | `/wda/activeAppInfo` | 返回当前前台应用信息 |
| `GET` | `/wda/batteryInfo` | 返回电量与电池状态，仅 iOS |
| `GET` | `/wda/device/location` | 返回当前设备地理位置 |

## 系统按键兼容说明
- 某些 WDA 版本提供 `pressButton` 类接口，可用于 Home、音量等系统按键模拟。
- 这类接口的路由在不同版本中可能有差异；使用前先确认当前 WDA 版本暴露的具体路径。

## 使用建议
- 切应用后马上校验前台状态，避免下一步操作还落在旧应用上。
- 系统弹窗优先读按钮列表后再决定 `accept` 或 `dismiss`，不要仅凭截图猜测。
- 设备信息、屏幕信息和应用状态适合做动作后的确认，不要只依赖视觉结果。