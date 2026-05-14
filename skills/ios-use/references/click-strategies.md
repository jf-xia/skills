# 点击策略详解

## 问题背景

`/element/:uuid/click` 内部调用 `[element tap]`，WDA 自行计算中点。对大元素或布局不规则的元素，中点可能不在预期位置。

## 四种策略对比

| 策略 | API | 坐标基准 | 精确度 | 性能 |
|------|-----|----------|--------|------|
| `element` | `/element/:uuid/click` | WDA 内部中点 | 低 | 最快 |
| `center` | `/wda/tap` + rect 中心 | 屏幕绝对坐标 | 中 | 快 |
| `w3c` | `/session/:sid/actions` | viewport 或 element 中心 | 高 | 略慢 |
| `offset` | `/wda/tap/:uuid` + 偏移 | 元素**左上角**偏移 | 高 | 快 |

## 策略选择决策树

```
element.click() 失败或点错？
  ├─ 元素小且居中 → 重试 element（可能只是时序问题）
  ├─ 元素大或形状不规则 → center（计算中心点绝对坐标）
  ├─ center 也点错 → w3c（最底层模拟，绕过 WDA 坐标计算）
  └─ 需要精确偏移 → offset（传入 x/y 偏移量）
```

## 坐标计算

### center 策略

```bash
# 元素 rect: { x: 100, y: 200, width: 300, height: 50 }
center_x = x + width/2   # 100 + 150 = 250
center_y = y + height/2  # 200 + 25 = 225
# POST /wda/tap { x: 250, y: 225 }
```

### offset 策略

```bash
# 偏移基准是元素左上角 (0,0)
# 不传 x/y 时自动使用 (width/2, height/2)
POST /wda/tap/$ELEMENT_ID { x: 150, y: 25 }  # width/2, height/2
```

> ⚠️ `/wda/tap/:uuid` 的偏移基准是**左上角**，不是中心。如果要偏移到中心，需传 `(width/2, height/2)`。

### w3c 策略

```bash
# origin: viewport → 绝对坐标
# origin: $ELEMENT_ID → 相对元素中心 (0,0) 就是中心点
{ "type": "pointerMove", "origin": "viewport", "x": 250, "y": 225 }
```

W3C Actions 元素相对坐标以**中心** `(0.5, 0.5)` 为基准，`(0, 0)` = 中心点。

## 常见失败模式

| 现象 | 原因 | 解决 |
|------|------|------|
| element 点击但无响应 | WDA 中点落在元素不可交互区域 | 换 `center` 或 `w3c` |
| 点击位置偏移 | 元素有透明 padding/overlay | 用 `offset` 精确指定位置 |
| 点击后元素消失但未触发 | 点到了相邻元素 | 用 `w3c` 模拟真实触摸 |
| 间歇性点错 | 动画未结束/页面未稳定 | 加等待后重试 |
