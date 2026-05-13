# 输入与键盘

## 入口选择
- 需要对具体元素输入时，优先 `POST /element/:uuid/value`。
- 需要清空文本时，使用 `POST /element/:uuid/clear`。
- 当前焦点已经明确、只需要发送键盘字符时，使用 `POST /wda/keys`。

## 元素输入

```bash
curl -X POST http://localhost:8100/session/$SESSION_ID/element/$ELEMENT_ID/value \
  -H "Content-Type: application/json" \
  -d '{
    "value": ["text"],
    "frequency": 60
  }'
```

说明：
- `value` 接受字符串数组，WDA 会拼接成最终输入内容。
- `frequency` 是可选的字符输入频率；未提供时使用配置默认值。
- 元素级输入通常会先处理焦点管理，再执行输入。

## 清空文本

```bash
curl -X POST http://localhost:8100/session/$SESSION_ID/element/$ELEMENT_ID/clear
```

清空失败时不要盲目循环；先判断该控件是否真的是普通文本输入框。

## 向当前焦点发送按键

```bash
curl -X POST http://localhost:8100/session/$SESSION_ID/wda/keys \
  -H "Content-Type: application/json" \
  -d '{
    "value": ["hello"],
    "frequency": 30
  }'
```

适用场景：
- 元素已经聚焦，但元素定位本身不稳定。
- 需要发送连续文本到当前焦点。
- 需要绕开元素级焦点管理。

## 特殊控件

| 控件 | 行为 |
| --- | --- |
| `PickerWheel` | 使用目标值调整，而不是普通键盘输入 |
| `Slider` | 只接受 `0` 到 `1` 的归一化值 |
| 普通文本元素 | 标准输入与清空流程 |

## 频率参数来源
1. 请求体显式传入的 `frequency`
2. `FBConfiguration.maxTypingFrequency`
3. 清空等回退路径使用的默认频率

如果输入明显丢字或太慢，先调整 `frequency`，再判断是否有动画、键盘弹出或页面性能问题。

## 键盘可见性与特殊按键
- 输入前先确认键盘是否已经出现，尤其是真机场景。
- iOS 在较新 Xcode 下支持更多特殊键映射，例如 Delete、Return、Tab、Escape、方向键与功能键。
- 如果脚本需要发送系统键序列，优先保证焦点明确，再发 `/wda/keys`。

## 特殊键名称

以下键名在较新 iOS 与 Xcode 组合上更常见，适合在焦点已明确时通过 `/wda/keys` 使用：

| 键类别 | 键名 | 说明 |
| --- | --- | --- |
| 编辑键 | `Delete` | 退格删除 |
| 编辑键 | `Return` | 回车 |
| 编辑键 | `Enter` | 输入确认 |
| 编辑键 | `Tab` | 制表符 |
| 编辑键 | `Space` | 空格 |
| 编辑键 | `Escape` | 退出或关闭当前输入态 |
| 方向键 | `UpArrow` `DownArrow` `LeftArrow` `RightArrow` | 方向控制 |
| 功能键 | `F1` 到 `F19` | 功能键 |

使用建议：
- 先保证目标输入框已获得焦点，再发送特殊键。
- 旧系统或旧 Xcode 组合的特殊键覆盖可能较弱；如果无效，先回退到普通文本输入或 UI 级确认动作。

## 平台差异

| 特性 | iOS | tvOS |
| --- | --- | --- |
| 点击激活键盘 | 支持 | 一般不依赖点击激活 |
| 清空优化 | 可能使用快捷清空策略 | 能力受限 |
| 特殊键支持 | 更完整 | 较弱 |
| 重试策略 | 常见多策略回退 | 一般更保守 |

## 完成检查
- 输入后重新读取元素文本，或通过截图确认 UI 已更新。
- 如果输入未生效，优先判断焦点、键盘和控件类型，而不是立即提高手速或重复重试。