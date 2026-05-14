# 应用与设备控制

## 应用生命周期

| 方法 | 路径 | 说明 |
|------|------|------|
| `POST` | `/wda/apps/launch` | 启动应用，可带参数和环境变量 |
| `POST` | `/wda/apps/activate` | 切到前台 |
| `POST` | `/wda/apps/terminate` | 终止应用 |
| `POST` | `/wda/apps/state` | 查询状态 |
| `POST` | `/wda/homescreen` | 返回主屏 |
| `POST` | `/wda/pressButton` | 系统按键（home、音量等） |

获取已安装应用：`xcrun devicectl device info apps --device <UDID>`

### 应用状态枚举

| 值 | 常量 | 含义 |
|----|------|------|
| 1 | `XCUIApplicationStateNotRunning` | 未运行 |
| 2 | `XCUIApplicationStateRunningBackgroundSuspended` | 后台挂起 |
| 3 | `XCUIApplicationStateRunningBackground` | 后台运行 |
| 4 | `XCUIApplicationStateRunningForeground` | 前台运行 |

### 使用要点

- `activate` 适合已运行应用切回前台
- 回主屏优先 `/wda/homescreen`；`activate com.apple.springboard` 不可靠
- 激活后用 `/wda/activeAppInfo` 确认前台是否真正切换
- 系统 App 或首次拉起 → `/wda/activeAppInfo` 判断是否仍停在 SpringBoard
- WDA 激活未切前台 → 系统级 CLI 直接启动（如 `ios launch <bundleId>`）
- 截图出现 shield/blocked → 系统策略拦截，非点击失败

## 系统弹窗

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/alert/text` | 读取弹窗文本 |
| `POST` | `/alert/text` | 向弹窗输入文本 |
| `POST` | `/alert/accept` | 接受弹窗 |
| `POST` | `/alert/dismiss` | 关闭弹窗 |
| `GET` | `/wda/alert/buttons` | 列出弹窗按钮 |

优先读按钮列表再决定 accept/dismiss，不要仅凭截图猜测。

## 锁屏与方向

| 方法 | 路径 | 说明 |
|------|------|------|
| `POST` | `/wda/lock` | 锁屏 |
| `POST` | `/wda/unlock` | 解锁 |
| `GET` | `/wda/locked` | 查询锁定状态 |
| `GET/POST` | `/orientation` | 读取/设置方向 |
| `GET/POST` | `/rotation` | 三轴旋转 |

## 模拟位置

| 方法 | 路径 | 说明 |
|------|------|------|
| `POST` | `/wda/simulatedLocation` | 设置经纬度 |
| `GET` | `/wda/simulatedLocation` | 读取当前模拟位置 |
| `DELETE` | `/wda/simulatedLocation` | 清除模拟位置 |

限制：仅 iOS，需 iOS 16.4+ 与 Xcode 14.3+。

## 屏幕与设备信息

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/wda/screen` | 屏幕尺寸、状态栏尺寸、缩放比例 |
| `GET` | `/wda/device/info` | locale、时区、型号、UUID、UI 风格 |
| `GET` | `/wda/activeAppInfo` | 前台应用信息 |
| `GET` | `/wda/batteryInfo` | 电量与电池状态 |
| `GET` | `/wda/device/location` | 设备地理位置 |

## 剪贴板

```bash
# 读取剪贴板（需确认 WDA 版本支持）
curl -X GET http://localhost:8100/wda/getPasteboard
```

接口可能不在所有版本暴露。没有时退回 UI 读取或上层驱动 API。

## 使用建议

- 切应用后立即校验前台状态
- 设备/屏幕/应用状态适合做动作后确认，不要只依赖视觉结果
