# Skills 开发指南

## 项目概述

这是一个为 AI Agent 开发技能（Skills）的框架项目。

## 性格风格 - 极简

去掉：冠词（的/一个）、填充词（只是/其实/基本上/确实/简单地）、客套话（当然/很高兴/没问题）、模糊限定。允许碎片句。短同义词（大 不用 庞大，修 不用 实施解决方案）。缩写常用词（数据库/认证/配置/请求/响应/函数/实现）。省略连词。用箭头表因果（X -> Y）。能一个字说完就不用两个字。

杜绝重复, 当在任何一个地方说明了，在其他地方就不要重复，不需要展开来解释。

技术术语保持原样不变。代码块不动。错误原样引用。

模式：`[事物] [动作] [原因]。[下一步]。`


## 目录结构

```tree
skills/
├── .agents/                    # Agent 运行时目录
│   ├── skills/                 # 技能软链接目录
│   └── tmp/                    # 临时文件目录
├── skills/                     # 技能开发目录
│   └── ios-use/                # iOS 使用能力技能
│       ├── SKILL.md            # 技能主文档
│       ├── references/         # 详细参考文档
│       └── scripts/            # 可执行脚本
├── tests/                      # 测试目录
│   └── ios-use/                # iOS 技能测试
└── AGENTS.md                   # 本文件
```

## 最佳实践

### 1. 文档编写

- **简洁优先：** 避免冗余解释，AI 能理解即可
- **示例驱动：** 提供可直接执行的示例
- **错误处理：** 说明常见错误和解决方法

### 2. 脚本开发

- **模块化：** 公共函数提取到 common 文件
- **单一职责原则：** 每个脚本只做一件事
- **命名规范：** 在脚本名称后面加上预期的执行时间，例如 `ios_wda_session_30s.sh`，如果是常驻脚本，则明确标注为 background。
- **Background 运行：** 长时间操作放后台执行，避免阻塞 Agent 主流程
- **日志记录：** 提供详细的执行日志
- **参数验证：** 验证输入参数的有效性
- **测试脚本：** 测试脚本应该包含执行成功与否，执行的结果如果是常驻进程，截取是否常驻成功，如果不是, 获取执行所需时间

### 3. 性能优化

- **缓存机制：** 合理使用缓存减少重复操作
- **批量操作：** 支持批量处理提高效率
- **资源管理：** 及时释放资源，避免内存泄漏

## Process

1. **Gather requirements** - ask user about:
   - What task/domain does the skill cover?
   - What specific use cases should it handle?
   - Does it need executable scripts or just instructions?
   - Any reference materials to include?

2. **Draft the skill** - create:
   - SKILL.md with concise instructions
   - Additional reference files if content exceeds 500 lines
   - Utility scripts if deterministic operations needed

3. **Review with user** - present draft and ask:
   - Does this cover your use cases?
   - Anything missing or unclear?
   - Should any section be more/less detailed?

## SKILL.md Template

```md
---
name: skill-name
description: Brief description of capability. Use when [specific triggers].
---

# Skill Name

## Quick start

[Minimal working example]

## Workflows

[Step-by-step processes with checklists for complex tasks]

## Advanced features

[Link to separate files: See [REFERENCE.md](REFERENCE.md)]
```

## Description Requirements

The description is **the only thing your agent sees** when deciding which skill to load. It's surfaced in the system prompt alongside all other installed skills. Your agent reads these descriptions and picks the relevant skill based on the user's request.

**Goal**: Give your agent just enough info to know:

1. What capability this skill provides
2. When/why to trigger it (specific keywords, contexts, file types)

**Format**:

- Max 1024 chars
- Write in third person
- First sentence: what it does
- Second sentence: "Use when [specific triggers]"

**Good example**:

```
Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when user mentions PDFs, forms, or document extraction.
```

**Bad example**:

```
Helps with documents.
```

The bad example gives your agent no way to distinguish this from other document skills.

## When to Add Scripts

Add utility scripts when:

- Operation is deterministic (validation, formatting)
- Same code would be generated repeatedly
- Errors need explicit handling

Scripts save tokens and improve reliability vs generated code.

## When to Split Files

Split into separate files when:

- SKILL.md exceeds 100 lines
- Content has distinct domains (finance vs sales schemas)
- Advanced features are rarely needed

## Review Checklist

After drafting, verify:

- [ ] Description includes triggers ("Use when...")
- [ ] SKILL.md under 100 lines
- [ ] No time-sensitive info
- [ ] Consistent terminology
- [ ] Concrete examples included
- [ ] References one level deep
