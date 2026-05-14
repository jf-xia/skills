---
name: ios-use
description: "操作 iOS / iPhone 真机与模拟器。用于 WebDriverAgent 场景下的设备发现、WDA 启动、Session 创建、页面读取、元素交互、手势、系统控制、故障恢复。适用于 xcodebuild、simctl、curl 或 WDA REST API。"
argument-hint: "描述任务，例如：启动 WDA 并创建 session；读取 source 后点击按钮"
user-invocable: true
---

# iOS 使用能力

## 缓存文件

缓存文件为 `ios-use-cache.json`，包含：udid、iproxy、sessionId

## 快速开始

```bash
# 一条命令：创建 session + 启动应用（自动处理设备检查、iproxy、WDA）
bash skills/ios-use/scripts/ios_wda_session.sh --bundle-id com.apple.Preferences

# 获取页面源码
curl -s http://<HOST>:8100/session/<SESSION_ID>/source | jq '.value'

# 获取截图
curl -s http://<HOST>:8100/screenshot | jq -r '.value' | base64 --decode > screenshot.png
```

## 工作流

### 标准启动流程
1. `ios_wda_init.sh` — 检查设备、启动 iproxy、启动 WDA、等待 ready
2. `ios_wda_session.sh --bundle-id <BUNDLE_ID>` — 创建 session、激活应用
3. `ios_wda_snapshot.sh` — 获取 source、accessibleSource、screenshot

### 元素交互流程
1. 获取页面树：`GET /source` 或 `GET /wda/accessibleSource`
2. 定位元素：优先 accessibility id / predicate / class chain，避免 XPath
3. 执行操作：`POST /element/:uuid/click`、`/value`、`/clear`
4. 验证结果：重新读取 source 或截图确认

### 输入文本流程
1. `ios_wda_type.sh --element-id <ID> --text "内容"` — 点击聚焦 + 输入 + 验证
2. 或手动：`POST /element/:uuid/click` → `POST /element/:uuid/value`
3. 长文本用 `--text-file` 避免 shell 转义问题

### 视觉闭环（结构化信息不足时）
1. **Observe**：截图或拉取页面树
2. **Plan**：根据文本/视觉确定目标位置
3. **Act**：调用点击、输入、滚动等接口
4. **Check**：再次截图或读取 source 确认生效

## 坐标系要点

| 场景 | 基准点 |
|------|--------|
| `/wda/tap`、`/wda/swipe` 等简单手势 | 屏幕绝对坐标，原点 `(0,0)` 左上角 |
| 元素 + 偏移量 | 偏移基准是**元素左上角**，不是中心 |
| W3C Actions | 通常以元素中心为基准，与 WDA 简单手势不同 |

## 脚本参数速查

### ios_wda_init.sh
`--udid` `--host` `--port` `--project-path` `--scheme` `--max-wait`

### ios_wda_session.sh
`--bundle-id` `--udid` `--host` `--port` `--force-new` `--delete` `--session-id`

### ios_wda_snapshot.sh
`--session-id` `--output-dir` `--only-source` `--only-accessible` `--only-screenshot`

### ios_wda_type.sh
`--element-id` `--using` `--locator` `--text` `--text-file` `--frequency` `--clear` `--no-click` `--no-verify`

## WDA API 核心速查

| 类别 | 关键接口 |
|------|----------|
| 状态 | `GET /status`、`GET /wda/healthcheck` |
| Session | `POST /session`、`DELETE /session` |
| 页面 | `GET /source`、`GET /wda/accessibleSource`、`GET /screenshot` |
| 元素 | `GET/POST /element/:uuid/{click,value,clear,text,rect,enabled,displayed}` |
| 手势 | `POST /wda/{tap,doubleTap,touchAndHold,swipe,pinch,rotate,dragfromtoforduration,scroll}` |
| 应用 | `POST /wda/apps/{launch,activate,terminate,state}`、`/wda/homescreen` |
| 弹窗 | `GET /alert/text`、`POST /alert/{accept,dismiss}`、`GET /wda/alert/buttons` |
| 设备 | `POST /wda/lock`、`/orientation`、`GET /wda/screen`、`/wda/device/info` |

## 详细文档

| 主题 | 路径 |
|------|------|
| 启动与 Session | [startup-and-session.md](references/startup-and-session.md) |
| 命令参考 | [command-reference.md](references/command-reference.md) |
| 输入与键盘 | [input-and-keyboard.md](references/input-and-keyboard.md) |
| 应用与设备控制 | [app-and-device-control.md](references/app-and-device-control.md) |
| 视觉与性能 | [visual-and-performance.md](references/visual-and-performance.md) |
| 故障排查 | [troubleshooting.md](references/troubleshooting.md) |
| 限制与取舍 | [limitations.md](references/limitations.md) |

## 清理

```bash
bash skills/ios-use/scripts/cleanup_ios_wda.sh
```
