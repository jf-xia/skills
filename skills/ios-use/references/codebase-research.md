# 代码库研究与分析

## 概述

使用 DeepWiki CLI 深入研究 WebDriverAgent 代码库，分析当前 skills 无法解决的问题或存在缺陷的问题。分析结果存储在项目根目录的 `tmp/` 文件夹下，供后续优化参考。

## DeepWiki CLI 使用

### 基本语法

```bash
dw aq -r "appium/WebDriverAgent" -q "问题描述"
```

### 常用查询示例

```bash
# 接口处理链路
dw aq -r "appium/WebDriverAgent" -q "POST /session 经过哪些 handler"

# 参数生效机制
dw aq -r "appium/WebDriverAgent" -q "element/:uuid/value 的 frequency 参数如何生效"

# 错误来源追踪
dw aq -r "appium/WebDriverAgent" -q "No Such Driver 从哪里抛出"

# 功能差异分析
dw aq -r "appium/WebDriverAgent" -q "accessibleSource 和 source 的生成路径差异"

# 端点处理差异
dw aq -r "appium/WebDriverAgent" -q "为什么 /wda/tap 是全局端点而 /wda/homescreen 不是"

# 元素交互机制
dw aq -r "appium/WebDriverAgent" -q "element/:uuid/click 的坐标计算逻辑"

# 键盘交互
dw aq -r "appium/WebDriverAgent" -q "键盘收起的触发条件和实现方式"
```

## 研究流程

### 1. 问题识别

从以下来源识别问题：
- 操作失败日志
- 脚本执行异常
- 用户反馈的不一致行为
- 文档与实际行为的差异

### 2. 代码分析

使用 DeepWiki 查询相关代码路径：
- 接口处理链路
- 错误抛出点
- 参数验证逻辑
- 状态管理机制

### 3. 解决方案

根据分析结果提出解决方案：
- 修复Skills缺陷
- 优化操作流程
- 优化脚本

### 4. 验证与迭代

- 实施解决方案
- 通过脚本测试验证修复效果
- 收集反馈，必要时迭代优化

### 5. 验收

- 总结并记录在 `tmp/` 文件夹，供后续参考
- git commit 相关代码改动，并在 commit message 中引用分析结果