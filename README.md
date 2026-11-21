# mbt-semver · 版本范围集合代数

> 用 MoonBit 写的、零第三方依赖的 SemVer 版本范围**集合代数**库。
> 面向 MoonBit 国产基础软件生态开源大赛 · 赛道一（新项目方向）。

本项目的核心不是「再写一个 semver 解析/satisfies」，而是把**版本范围当作数学集合**：任意范围被解析成规范化的区间集合，支持并集、交集、差集、补集、可满足性判定与规范化等价判定。这是包管理器做依赖冲突分析、许可证兼容矩阵、多版本共存策略时真正需要、但 MoonBit 生态现有库没有提供的能力。

## 与现有 MoonBit 库的差异（为什么不是重复造轮子）

初审指出：MoonBit 已有近期维护的版本库覆盖主要语义能力。这一判断属实，我们据此把项目重新聚焦到现有库都没有覆盖的**范围集合代数**上：

| 能力 | moonsemver | moondepsolve | version.mbt | moonguard | **本项目** |
| --- | --- | --- | --- | --- | --- |
| 严格 SemVer 解析 / 比较 | ✅ | ✅ | ✅ | — | ✅（基础） |
| `^` `~` 范围 / satisfies | ✅ | ✅ | ✅ | — | ✅（基础） |
| `\|\|` OR 表达式 | ❌ README 仅声明 AND | ❌ 明确不支持 | 部分 | — | ✅ |
| 连字符范围 `1.2.3 - 2.3.4` | ❌ | ❌ 明确不支持 | ❌ | — | ❌（未支持，不列为差异） |
| build 元数据 `+build` | ✅ | ❌ 明确不支持 | ✅ | — | ✅ |
| **范围并/交/差/补集合运算** | ❌ | ❌ | ❌ | ❌ | ✅ **核心差异** |
| **规范化与等价判定** | ❌ | ❌ | ❌ | ❌ | ✅ **核心差异** |
| **可满足性 / 冲突判定** | ❌ | 仅依赖求解内部 | ❌ | ❌ | ✅ **核心差异** |
| 依赖 lock / 升级规划 / 冲突报告 | ❌ | ✅ | ❌ | ❌ | ❌（不重复） |
| API 兼容性 diff | ❌ | ❌ | ❌ | ✅ | ❌（不重复） |

差异点说明：现有库回答「版本 v 是否满足范围 r」；本项目回答「范围 r1 与 r2 的并/交/差是什么、它们能否同时成立、两个不同写法是否表示同一个版本集合」。这是支撑依赖冲突诊断与版本策略分析的另一种能力，不与现有库重叠。

数据来源：逐字核对各库公开 README（2026-11-20 抓取并逐项复核）。可复核的原文依据：

- `moonsemver` 的 Ranges 一栏只列 `=` `>` `>=` `<` `<=` `^` `~` “+ whitespace AND”，公开 API 为 `parse` / `is_valid` / `compare` / `lt` / `le` / `gt` / `ge` / `eq` / `satisfies` / `sort_strings`，**没有 OR，也没有任何集合运算 API**。
- `moondepsolve`（v0.4.0）README 明确写有 “OR expressions, hyphen ranges, and bare `*` are not supported” 与 “Build metadata (`+build`) is not supported by the current `Version` type”；其 Public API 表列 `parse_version` / `matches` / `resolve` / `format_lock` / `plan_upgrade` / `build_conflict_report` 等，**无区间集合运算**。需区分两类「冲突」：其冲突报告属依赖求解层面（给定依赖图是否可解），本项目 `satisfiable` 属区间集合层面（任意两条范围表达式是否相交），不重叠。
- 本项目不把「尚未支持」的连字符范围写成差异点；对比表只列已实现、可运行验证的能力。

## 为什么做这个（项目价值）

- **边界清晰**：输入版本范围，输出规范化的区间集合；所有集合运算返回同构类型。
- **可验证**：38 个单元测试覆盖空/全集、无界端点、端点开闭、重叠与相接合并、德摩根律、双重补集、规范化等价，以及 SemVer 规范边界（构建元数据含连字符、超大版本号不溢出、任意长度 prerelease 数字、范围上界在 Int64 上限处不溢出）；其中 4 个**穷举测试**在有限版本域上枚举全部区间与区间三元组，用独立参考判定验证并/交/差/补与布尔代数定律，并据此抓出并修复了一个固定用例无法发现的规范形排序缺陷。另用独立 Python 参考实现做了 468 组 `(版本, 范围)` 差分对照，全部一致。累计修复 `>` 比较符误作上界、无界区间合并与补集边界、Int32 溢出回绕、构建元数据连字符误判、范围上界溢出、相等端点排序六类真实缺陷。
- **可复用**：核心库零第三方依赖，只使用 MoonBit 核心库；`parse`/`satisfies` 基础 API 与主流语义一致，集合代数为新增能力。

## 目录结构

```text
moonbit-semver/
├── moon.mod                 # 模块声明
├── semver/                  # 库包（包名 @semver）
│   ├── moon.pkg
│   ├── version.mbt          # Version 类型、严格解析、SemVer 优先级
│   ├── range.mbt            # ^ ~ >= < = * 范围解析与匹配
│   ├── range_algebra.mbt    # 核心差异：范围→区间集合、并/交/差/补、规范化
│   └── constraint.mbt       # 多约束交集筛选、最高版本选择
├── cmd/                     # 可执行示例
│   ├── moon.pkg
│   └── main.mbt             # parse / compare / check / algebra / demo 子命令
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

### 范围集合代数（核心差异）

```moonbit
///|
fn example_algebra() -> Unit {
  let a = @semver.parse_algebra(">=1.0.0 <3.0.0").unwrap()
  let b = @semver.parse_algebra(">=2.0.0 <4.0.0").unwrap()
  println(@semver.algebra_to_string(@semver.algebra_union(a, b)))        // >=1.0.0 <4.0.0
  println(@semver.algebra_to_string(@semver.algebra_intersection(a, b))) // >=2.0.0 <3.0.0
  println(@semver.algebra_to_string(@semver.algebra_difference(a, b)))   // >=1.0.0 <2.0.0
  println(@semver.algebra_to_string(@semver.algebra_complement(a)))      // <1.0.0 || >=3.0.0
  println(@semver.algebra_satisfiable(a, b))                             // true
}
```

- 任意范围先解析成**规范化区间集合**：排序、去重、合并重叠区间；两种不同写法若表示同一版本集合，规范化结果相同（等价判定）。
- `union` / `intersection` / `difference` / `complement` 对集合封闭，可组合嵌套。
- `satisfiable(a, b)` 判定两个范围是否可能同时成立，可直接用于依赖冲突预检。
- `algebra` CLI 子命令可运行上述全部演示。

## 测试与验证

```text
$ moon test
Total tests: 38, passed: 38, failed: 0.
```

覆盖内容包括：

- SemVer 官方优先级示例链（`alpha` → `alpha.1` → `alpha.beta` → `beta` → `beta.2` → `beta.11` → `rc.1` → 正式版）
- 前导零、空标识符、非法字符、多余组件等拒绝用例
- 构建元数据不参与优先级
- caret / tilde / 通配 / OR / AND 范围语义；`>` 比较符边界（含基础模块缺陷修复）
- 预发布版本的选择性匹配；约束冲突报错与最高版本选择
- **集合代数**：空/全集、无界端点（`-∞` / `+∞`）合并与补集、端点开闭、重叠与相接合并、并/交/差/补、可满足性、规范化等价
- **代数定律**：双重补集为恒等、德摩根律、`A∪¬A=全集`、`A∩¬A=空`、幂等/交换/结合/分配/吸收律、预发布版本在集合中的优先级，含有限版本域上的穷举验证（22 个集合代数专项测试）

## 与赛事验收标准的对应

| 官方验收项 | 本项目情况 |
| --- | --- |
| MoonBit 为主 | 全部实现与测试均为 MoonBit，零第三方依赖 |
| 仓库公开、提交可追踪 | 提交到公开 GitHub 仓库，按模块分阶段提交（见 `DEVELOPMENT_LOG.md`） |
| 能运行 | `moon check` / `moon test` 通过（38/38）；`cmd` 提供 parse/compare/check/algebra/demo 五个可运行子命令 |
| 工作有效 | 赛道一新项目方向；初审后按反馈聚焦到竞品空白的范围集合代数，形成实质差异 |
| 开源合规 | Apache-2.0 许可证；未移植第三方代码 |
| AI 可解释 | AI 参与代码与文档生成，逐项由参赛者审查、测试并解释，详见 `DEVELOPMENT_LOG.md` |

## 后续计划

- 支持连字符范围 `1.2.3 - 2.3.4`（现有库明确不支持）
- 用 QuickCheck 属性测试验证集合代数的交换律/结合律/德摩根律
- 发布到 mooncakes.io，供其他 MoonBit 项目直接引用
- 提供区间集合 → 冲突诊断报告的渲染

仓库地址与 GitHub ID 已按 `xianjuanzi` 填好。推送公开仓库后即可按 `运行与上传指南.md` 报名。
