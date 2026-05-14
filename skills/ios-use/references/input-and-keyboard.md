# 输入与键盘

## 入口选择

| 场景 | 接口 |
|------|------|
| 对具体元素输入 | `POST /element/:uuid/value` |
| 清空文本 | `POST /element/:uuid/clear` |
| 已聚焦、只发键盘字符 | `POST /wda/keys` |

## 元素输入

```bash
curl -X POST http://localhost:8100/session/$SESSION_ID/element/$ELEMENT_ID/value \
  -H "Content-Type: application/json" \
  -d '{"value": ["text"], "frequency": 60}'
```

- `value` 接受字符串数组，WDA 拼接成最终内容
- `frequency` 可选，控制字符输入频率
- 元素级输入会先处理焦点管理

## 清空文本

```bash
curl -X POST http://localhost:8100/session/$SESSION_ID/element/$ELEMENT_ID/clear
```

清空失败时不要盲目循环；先判断控件类型。

## 向当前焦点发送按键

```bash
curl -X POST http://localhost:8100/session/$SESSION_ID/wda/keys \
  -H "Content-Type: application/json" \
  -d '{"value": ["hello"], "frequency": 30}'
```

适用：元素已聚焦但定位不稳定、需发送连续文本、需绕开焦点管理。

## PickerWheel

```bash
curl -X POST http://localhost:8100/session/$SESSION_ID/wda/pickerwheel/$ELEMENT_ID/select \
  -H "Content-Type: application/json" \
  -d '{"order": "next", "value": "58 minutes", "maxAttempts": 30}'
```

- `order` 只能 `next` 或 `previous`
- 每次调用先移动一格再检查是否达到目标值
- 已在目标值时继续调用可能拨离目标
- 多轮控件一次只改一个 wheel，关闭弹层后重新读取
- `/element/:uuid/value` 返回成功但 UI 没变 → 优先怀疑控件类型错误

## Slider

只接受 `0` 到 `1` 的归一化值。

## 特殊键名称

| 键类别 | 键名 |
|--------|------|
| 编辑键 | `Delete` `Return` `Enter` `Tab` `Space` `Escape` |
| 方向键 | `UpArrow` `DownArrow` `LeftArrow` `RightArrow` |
| 功能键 | `F1`~`F19` |

- 先保证焦点明确，再发 `/wda/keys`
- 旧系统/Xcode 组合特殊键覆盖可能较弱

## 频率参数

优先级：请求体 `frequency` → `FBConfiguration.maxTypingFrequency` → 默认值

丢字或太慢 → 先调 `frequency`，再排查动画/键盘弹出/页面性能。

## 平台差异

| 特性 | iOS | tvOS |
|------|-----|------|
| 点击激活键盘 | 支持 | 一般不依赖 |
| 清空优化 | 可能用快捷策略 | 能力受限 |
| 特殊键 | 更完整 | 较弱 |

## 已知陷阱

- 长文本/多行 → 用 `--text-file`，避免 shell 转义
- 输入后被 App 自动改写 → 应用层格式化，非 WDA 失败
- 时间窗/日程页面 → 以设备 UI 显示的 AM/PM 为准，不按宿主机时间推断
- Notes 等应用自动编号 → 应用层改写，不按 WDA 丢字排查

## 完成检查

输入后重新读取元素文本或截图确认 UI 已更新。输入未生效 → 先判焦点/键盘/控件类型。
