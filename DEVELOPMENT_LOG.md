# 开发记录与 AI 使用说明

> 本文件用于说明项目是怎么做出来的、哪些决策由参赛者确认、AI 参与到了什么程度。
> 推送到 GitHub 后，实际 commit / Issue / PR 记录以公开仓库为准。

## 一、开发过程

| 阶段 | 工作 | 验证方式 |
| --- | --- | --- |
| M1 | 设计 `Version` 数据结构；实现严格解析与 SemVer 优先级比较 | 4 个测试：合法/非法语法、官方优先级链、字符串往返 |
| M2 | 实现 `^` `~` 通配、比较运算符、AND/OR 组合与预发布策略 | 5 个测试，覆盖 25+ 组版本/范围样例 |
| M3 | 实现约束求交、最高版本选择、冲突报错 | 3 个测试，覆盖正常求解与冲突场景 |
| M4 | 编写 CLI 示例、README、内部项目素材、许可证与本记录 | `moon check`、`moon test`、CLI 手工运行 |

最终验证结果：

```text
$ moon check
Finished. moon: ran 5 tasks, now up to date

$ moon test
Total tests: 12, passed: 12, failed: 0.

$ moon run cmd -- demo
core -> 1.5.0
extra -> 0.1.0
```

## 二、关键设计决策

1. **为什么自己写数字解析，不用标准库 `parse_int`？**
   `parse_int` 接受部分非 SemVer 写法，且异常语义不适合库 API。逐字符校验能精确实现「ASCII 数字、无前导零」规则，并直接返回错误原因。

2. **为什么用 `Result[Version, String]` 而不是 `raise`？**
   库的使用者往往是包管理器等长期运行程序。把解析失败作为值返回，调用方可以决定是提示用户、记录日志还是回退，不会被迫 `try/catch`。

3. **为什么预发布版本默认不匹配范围？**
   这是 npm/semver 等主流实现的语义：预发布版本只属于明确的版本线。我们把它实现为「范围中显式出现相同 `major.minor.patch` 的预发布」才允许匹配，避免 `1.0.0-alpha` 意外命中 `^1.0.0`。

4. **为什么求解器只做直接依赖？**
   传递依赖与回溯会显著扩大范围，一个月内难以做到可靠验证。先把直接约束的求交、选版、冲突报告做扎实，并在 README 中明确边界，符合赛事「清晰边界、可靠测试」的导向。

## 三、AI 使用记录

| 环节 | AI 参与方式 | 参赛者复核动作 |
| --- | --- | --- |
| 需求理解 | 从赛事海报与官网提取赛道一要求、验收项、评分维度 | 逐条对照官网原文确认，未把海报未写明的规则当作硬要求 |
| 代码初稿 | 生成 `version.mbt`、`range.mbt`、`constraint.mbt` 第一版 | 逐函数阅读；发现并修正了「全局 split 导致预发布解析失败」「`1.x` 上界算成 `1.1.0`」等问题 |
| 测试 | 生成测试用例与预期值 | 按 SemVer 官方示例链逐条核对预期；全部测试实际运行通过 |
| 文档 | 生成 README、内部项目素材与开发记录 | 核对事实、补齐待填字段、确认无夸大描述 |

**责任声明**：AI 只参与生成与辅助，项目目标、技术选型、范围边界与最终质量均由参赛者理解并负责。所有代码均可离线编译，测试可复现，不依赖任何 AI 服务运行。

## 四、提交到公开仓库的建议

推送后请保留连续、可追踪的提交记录。可按以下粒度提交（或合并为真实开发节奏对应的提交）：

```text
feat: add strict SemVer 2.0.0 parser and precedence comparison
test: cover SemVer official precedence example chain
feat: add npm-style range parsing and satisfaction checks
feat: add direct dependency constraint solver
feat: add runnable CLI demo
docs: add README, project proposal and AI usage disclosure
```

后续如修复问题，请继续用独立 commit 记录，并在 GitHub Issues 中跟踪；验收时可直接展示 commit 历史与 `moon test` 输出。

## 五、验收前检查清单

- [x] `moon.mod` 的 `repository` 已改为 `https://github.com/xianjuanzi/mbt-semver`
- [x] 内部项目素材中的 GitHub ID 已填为 `xianjuanzi`
- [x] `moon check` / `moon test` 通过（12/12）
- [x] LICENSE 保留在仓库根目录
- [x] 已提供 `运行与上传指南.md` 与一键运行的 `run.bat`
- [x] 本地已整理 11 个有效提交（功能/文档各有独立提交，无空提交）
- [ ] 仓库推送到 GitHub 并设为 Public
- [ ] 已加入赛事交流群，群昵称改为 GitHub ID
- [ ] 通过官网报名入口提交仓库链接与**本人手写**的项目申报书（不要用 AI 代写）
