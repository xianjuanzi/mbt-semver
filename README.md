# mbt-semver

> 用 MoonBit 写的、零第三方依赖的 Semantic Versioning 2.0.0 工具库。
> 面向 MoonBit 国产基础软件生态开源大赛 · 赛道一（新项目方向）。

`mbt-semver` 把「版本号解析 → 优先级比较 → 版本范围匹配 → 依赖约束求解」做成一条完整、可验证的链路。它不依赖任何外部包，只使用 MoonBit 核心库，因此可以作为一个基础组件被其他 MoonBit 项目直接复用。

## 为什么做这个

MoonBit 的包管理器需要判断「某个版本是否满足依赖约束」，而这类逻辑通常被埋在工具链内部，生态里缺少一个独立、可读、可测试的公开实现。本项目把这个能力抽成库：

- **边界清晰**：输入字符串，输出结构化版本、比较结果与约束求解结果。
- **可验证**：语法错误返回 `Result` 而非异常；边界条件有 12 个测试用例覆盖。
- **可复用**：核心库无第三方依赖，API 与 npm/semver 的常见语义保持一致。

## 目录结构

```text
moonbit-semver/
├── moon.mod                 # 模块声明
├── semver/                  # 库包（包名 @semver）
│   ├── moon.pkg
│   ├── version.mbt          # Version 类型、严格解析、SemVer 优先级
│   ├── range.mbt            # ^ ~ >= < = * 范围解析与匹配
│   └── constraint.mbt       # 多约束交集筛选、最高版本选择
├── cmd/                     # 可执行示例
│   ├── moon.pkg
│   └── main.mbt             # parse / compare / check / demo 四个子命令
├── INTERNAL_NOTES.md        # 内部素材（不要当申报书提交）
├── DEVELOPMENT_LOG.md       # 开发过程与 AI 使用说明
├── CHANGELOG.md
└── LICENSE                  # Apache-2.0
```

## 快速开始

需要 MoonBit 工具链（`moon` 与 `moonc`）。

```bash
# 类型检查
moon check

# 运行全部测试
moon test

# 运行示例 CLI
moon run cmd -- demo
moon run cmd -- parse 1.2.3-alpha.1+sha.abc
moon run cmd -- compare 1.0.0-alpha 1.0.0
moon run cmd -- check 1.9.0 '^1.2.3'
```

`moon run cmd -- demo` 的输出：

```text
== selected ==
core -> 1.5.0
extra -> 0.1.0
```

## API 概览

### 版本与比较

```moonbit
///|
fn example_version() -> Unit {
  match @semver.parse_version("1.2.3-alpha.1+sha.abc") {
    Ok(v) => {
      println(v.to_string())          // 1.2.3-alpha.1+sha.abc
      println(v.major)                // 1
      println(v.prerelease.length())  // 2
    }
    Err(e) => println(e)
  }
}
```

- `parse_version(text) -> Result[Version, String]`：严格遵循 SemVer 2.0.0 语法，拒绝前导零、`v` 前缀、空标识符等非法输入，返回可读错误原因。
- `compare_version(a, b) -> Int`：返回 `-1 / 0 / 1`；实现 `Eq` 与 `Compare` trait，可直接用 `==`、`>` 等运算符。
- 构建元数据（ `+...` ）按顺序规则被忽略：`1.0.0+build.1 == 1.0.0+build.2`。

### 范围匹配

| 表达式 | 含义 |
| --- | --- |
| `1.2.3` / `=1.2.3` | 精确版本 |
| `>=1.2.3 <2.0.0` | 空格表示 AND |
| `^1.2.3` | `>=1.2.3 <2.0.0`（`0.x` 与 `0.0.x` 按 SemVer 规则收紧） |
| `~1.2.3` / `~1.2` | 锁定到次版本：`>=1.2.3 <1.3.0` |
| `1.x` / `1.2.x` / `*` | 通配符 |
| `^1.0.0 || ^3.0.0` | `||` 表示 OR |

预发布版本默认不匹配范围；只有当范围中显式写出相同 `major.minor.patch` 的预发布版本时才匹配，例如 `^1.0.0-alpha.1` 可以匹配 `1.0.0-beta.1`。

```moonbit
///|
fn example_range() -> Unit {
  let v = @semver.parse_version("1.9.0").unwrap()
  println(@semver.satisfies_text(v, "^1.2.3").unwrap()) // true
}
```

### 约束求解

```moonbit
///|
fn example_resolve() -> Unit {
  let catalogue = [("core", @semver.parse_catalogue(["1.0.0", "1.5.0", "2.0.0"]).unwrap())]
  let requirements = [
    @semver.Requirement::new("core", ">=1.0.0 <2.0.0"),
    @semver.Requirement::new("core", "^1.2.0"),
  ]
  match @semver.resolve(catalogue, requirements) {
    Ok(r) => println(r.selected[0].1.to_string()) // 1.5.0
    Err(e) => println(e)
  }
}
```

`resolve` 对每个包的全部约束求交集，再选择满足条件的最高版本；无解时返回明确错误。它目前只处理**直接依赖**，不遍历传递依赖——这是有意设计的边界，便于审计和验证。

## 测试与验证

```text
$ moon test
Total tests: 12, passed: 12, failed: 0.
```

覆盖内容包括：

- SemVer 官方优先级示例链（`alpha` → `alpha.1` → `alpha.beta` → `beta` → `beta.2` → `beta.11` → `rc.1` → 正式版）
- 前导零、空标识符、非法字符、多余组件等拒绝用例
- 构建元数据不参与优先级
- caret / tilde / 通配 / OR / AND 范围语义
- 预发布版本的选择性匹配
- 约束冲突报错与最高版本选择

## 与赛事验收标准的对应

| 官方验收项 | 本项目情况 |
| --- | --- |
| MoonBit 为主 | 全部实现与测试均为 MoonBit，零第三方依赖 |
| 仓库公开、提交可追踪 | 提交到公开 GitHub 仓库，按模块分阶段提交（见 `DEVELOPMENT_LOG.md`） |
| 能运行 | `moon check` / `moon test` 通过；`cmd` 提供 4 个可运行子命令 |
| 工作有效 | 赛道一新项目方向，本期从零开始 |
| 开源合规 | Apache-2.0 许可证；未移植第三方代码 |
| AI 可解释 | AI 参与代码与文档生成，逐项由参赛者审查、测试并解释，详见 `DEVELOPMENT_LOG.md` |

## 后续计划

- 增加传递依赖解析与冲突回溯
- 增加 QuickCheck 属性测试，随机对照参考实现
- 发布到 mooncakes.io，供其他 MoonBit 项目直接引用

仓库地址与 GitHub ID 已按 `xianjunzi` 填好。推送公开仓库后即可按 `运行与上传指南.md` 报名。
