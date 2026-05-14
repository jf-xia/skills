---
name: ios-use
description: "操作 iOS / iPhone 真机与模拟器。用于 WebDriverAgent 场景下的设备发现、WDA 启动、Session 创建、页面读取、元素交互、手势、系统控制、故障恢复。适用于 xcodebuild、simctl、curl 或 WDA REST API。"
argument-hint: "描述任务，例如：启动 WDA 并创建 session；读取 source 后点击按钮"
user-invocable: true
---

# iOS 使用能力

## 快速开始
```bash
# 一条命令：创建 session + 启动应用（自动处理设备检查、iproxy、WDA）
bash skills/ios-use/scripts/ios_wda_session.sh --bundle-id com.apple.Preferences
# 获取页面源码
curl -s http://<HOST>:8100/session/<SESSION_ID>/source | jq '.value'
# 获取截图
curl -s http://<HOST>:8100/screenshot | jq -r '.value' | base64 --decode > screenshot.png
```



## 工作流（ReAct 循环）

**核心原则：每次操作前必须截屏观察当前状态，禁止预测式连续操作。**

每个操作步骤都遵循：
```
截屏 → 观察屏幕内容 → 决策下一步 → 执行操作 → 再次截屏验证
```

### ReAct 模板
1. **Observe**：`ios_wda_snapshot.sh` 截屏 + 获取 source
2. **Think**：分析当前屏幕状态，确认目标元素位置和状态
3. **Act**：执行单个操作（点击/输入/滑动等）
4. **Verify**：再次截屏，确认操作生效
5. **Repeat**：回到步骤 1，直到任务完成

> ⚠️ 禁止跳过截屏直接执行多个操作。每步操作后必须截图确认结果。

### 标准启动流程
1. `ios_wda_init.sh` — 检查设备、启动 iproxy、启动 WDA、等待 ready
2. `ios_wda_session.sh --bundle-id <BUNDLE_ID>` — 创建 session、激活应用
3. `ios_wda_snapshot.sh` — **截屏确认启动成功**

### 元素交互流程
1. **Observe**：`ios_wda_snapshot.sh` 获取 source + screenshot
2. **Think**：从 source 定位元素（优先 accessibility id / predicate / class chain，避免 XPath）
3. **Act**：`ios_wda_click.sh --element-id <ID>` 或 `ios_wda_type.sh`；点击失败时换策略（center → w3c）
4. **Verify**：再次 `ios_wda_snapshot.sh` 截屏确认操作生效

### 输入文本流程
1. **Observe**：截屏确认输入框状态
2. **Act**：`ios_wda_type.sh --element-id <ID> --text "内容"`
3. **Verify**：截屏确认输入内容正确
4. 长文本用 `--text-file` 避免 shell 转义问题

### 关闭应用流程
1. **Observe**：截屏确认当前应用状态
2. **Act**：`POST /wda/homescreen`（**全局端点**）或 `POST /wda/apps/terminate`
3. **Verify**：截屏确认回到主屏

> ⚠️ `/wda/homescreen` 是全局端点，错误写法 `/session/<ID>/wda/homescreen` 会报 `unknown command`。

## 坐标系要点

| 场景 | 基准点 |
|------|--------|
| `/wda/tap`、`/wda/swipe` 等简单手势 | 屏幕绝对坐标，原点 `(0,0)` 左上角 |
| 元素 + 偏移量 | 偏移基准是**元素左上角**，不是中心 |
| W3C Actions | 通常以元素中心为基准，与 WDA 简单手势不同 |

## 点击策略

`element.click()` 依赖 WDA 计算中点，有时点错位置。使用 `ios_wda_click.sh` 选择策略：

| 策略 | 原理 | 适用场景 |
|------|------|----------|
| `element` | `/element/:uuid/click`，WDA 内部选中点 | 默认，元素小且居中时 |
| `center` | 获取 rect → 计算 `(x+w/2, y+h/2)` → `/wda/tap` 绝对坐标 | 元素大或中点偏移时 |
| `w3c` | W3C Actions pointerDown/pointerUp，最底层模拟 | element/center 都失败时 |
| `offset` | 获取 rect → `/wda/tap/:uuid` + 左上角偏移 | 需要精确偏移点击时 |

```bash
# 默认点击
bash ios_wda_click.sh --element-id <ID>
# 中心坐标点击（推荐当 element 点错时）
bash ios_wda_click.sh --element-id <ID> --strategy center
# W3C 模拟点击
bash ios_wda_click.sh --element-id <ID> --strategy w3c
# 偏移点击（基准是元素左上角）
bash ios_wda_click.sh --element-id <ID> --strategy offset --x-offset 30 --y-offset 10
```

> 偏移策略不传 x/y 时自动使用 `(width/2, height/2)` 等效中心点。

## 脚本参数速查

| 脚本 | 关键参数 |
|------|----------|
| `ios_wda_init.sh` | `--udid` `--host` `--port` `--project-path` `--scheme` `--max-wait` |
| `ios_wda_session.sh` | `--bundle-id` `--udid` `--host` `--port` `--force-new` `--delete` `--session-id` |
| `ios_wda_snapshot.sh` | `--session-id` `--output-dir` `--only-source` `--only-accessible` `--only-screenshot` |
| `ios_wda_click.sh` | `--element-id` `--strategy element|center|w3c|offset` `--x-offset` `--y-offset` `--verify` |
| `ios_wda_type.sh` | `--element-id` `--using` `--locator` `--text` `--text-file` `--frequency` `--clear` `--no-click` `--no-verify` |

## WDA API 核心速查

| 类别 | 关键接口 |
|------|----------|
| 状态 | `GET /status`、`GET /wda/healthcheck` |
| Session | `POST /session`、`DELETE /session` |
| 页面 | `GET /source`、`GET /wda/accessibleSource`、`GET /screenshot` |
| 元素 | `GET/POST /element/:uuid/{click,value,clear,text,rect,enabled,displayed}` |
| 手势 | `POST /wda/{tap,doubleTap,touchAndHold,swipe,pinch,rotate,dragfromtoforduration,scroll}` |
| 应用 | `POST /wda/apps/{launch,activate,terminate,state}`、`POST /wda/homescreen`（全局端点） |
| 弹窗 | `GET /alert/text`、`POST /alert/{accept,dismiss}`、`GET /wda/alert/buttons` |
| 设备 | `POST /wda/lock`、`/orientation`、`GET /wda/screen`、`/wda/device/info` |

## 性能优化

当脚本多次出错或多次无法完成任务的时候进行优化建议, 如果改动小，直接优化，如果复杂，需要用户确认后再优化。

## 详细文档

| 主题 | 路径 |
|------|------|
| 启动与 Session | [startup-and-session.md](references/startup-and-session.md) |
| 命令参考 | [command-reference.md](references/command-reference.md) |
| 输入与键盘 | [input-and-keyboard.md](references/input-and-keyboard.md) |
| 应用与设备控制 | [app-and-device-control.md](references/app-and-device-control.md) |
| 视觉与性能 | [visual-and-performance.md](references/visual-and-performance.md) |
| 点击策略 | [click-strategies.md](references/click-strategies.md) |
| 故障排查 | [troubleshooting.md](references/troubleshooting.md) |
| 限制与取舍 | [limitations.md](references/limitations.md) |
| 多次操作失败请使用代码库研究 | [codebase-research.md](references/codebase-research.md) |

## 清理
```bash
bash skills/ios-use/scripts/cleanup_ios_wda.sh
```
