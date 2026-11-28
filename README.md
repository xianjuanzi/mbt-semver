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
| 连字符范围 `1.2.3 - 2.3.4` | ❌ | ❌ 明确不支持 | ❌ | — | ✅ **新增** |
| build 元数据 `+build` | ✅ | ❌ 明确不支持 | ✅ | — | ✅ |
| **范围并/交/差/补集合运算** | ❌ | ❌ | ❌ | ❌ | ✅ **核心差异** |
| **规范化与等价判定** | ❌ | ❌ | ❌ | ❌ | ✅ **核心差异** |
| **可满足性 / 冲突判定** | ❌ | 仅依赖求解内部 | ❌ | ❌ | ✅ **核心差异** |
| 依赖 lock / 升级规划 / 冲突报告 | ❌ | ✅ | ❌ | ❌ | ❌（不重复） |
| API 兼容性 diff | ❌ | ❌ | ❌ | ✅ | ❌（不重复） |

差异点说明：现有库回答「版本 v 是否满足范围 r」；本项目回答「范围 r1 与 r2 的并/交/差是什么、它们能否同时成立、两个不同写法是否表示同一个版本集合」。这是支撑依赖冲突诊断与版本策略分析的另一种能力，不与现有库重叠。连字符范围 `1.2.3 - 2.3.4` 是初审通过后新增的能力，按 node-semver 官方语义实现，且与区间集合代数打通——解析后可直接参与并/交/差/补。

数据来源：逐字核对各库公开 README（2026-11-20 抓取并逐项复核）。可复核的原文依据：

- `moonsemver` 的 Ranges 一栏只列 `=` `>` `>=` `<` `<=` `^` `~` “+ whitespace AND”，公开 API 为 `parse` / `is_valid` / `compare` / `lt` / `le` / `gt` / `ge` / `eq` / `satisfies` / `sort_strings`，**没有 OR，也没有任何集合运算 API**。
- `moondepsolve`（v0.4.0）README 明确写有 “OR expressions, hyphen ranges, and bare `*` are not supported” 与 “Build metadata (`+build`) is not supported by the current `Version` type”；其 Public API 表列 `parse_version` / `matches` / `resolve` / `format_lock` / `plan_upgrade` / `build_conflict_report` 等，**无区间集合运算**。需区分两类「冲突」：其冲突报告属依赖求解层面（给定依赖图是否可解），本项目 `satisfiable` 属区间集合层面（任意两条范围表达式是否相交），不重叠。
- 对比表只列已实现、可运行验证的能力。连字符范围已按上述 node-semver 官方 Hyphen Ranges 语义实现：`1.2.3 - 2.3.4` = `>=1.2.3 <=2.3.4`（两端闭）；partial 端与 `<A.B.C-0` 上界规则均已覆盖，并有 123 组独立参考差分对拍。终版另用 `semver@7` 重新生成 4700 组 `(版本, 范围)` 差分断言并在基础层与代数层**双层**校验（9400 条断言），覆盖 caret/tilde 的 written-precision 规则、partial 比较符、跨元组预发布 opt-in、跨 OR 分支的 opt-in 隔离、空范围与空白分隔写法，全部一致。

## 为什么做这个（项目价值）

- **边界清晰**：输入版本范围，输出规范化的区间集合；所有集合运算返回同构类型。
- **可验证**：51 个单元测试覆盖空/全集、无界端点、端点开闭、重叠与相接合并、德摩根律、双重补集、规范化等价，以及 SemVer 规范边界（构建元数据含连字符、超大版本号不溢出、任意长度 prerelease 数字、范围上界在 Int64 上限处不溢出）、连字符范围（node-semver 闭区间、partial 端点、预发布端点、畸形输入拒绝）与范围解析边界（caret/tilde 按书写精度决定上界、partial 比较符）；其中 4 个**穷举测试**在有限版本域上枚举全部区间与区间三元组，1 个**属性测试**用确定性伪随机生成器（Park-Miller LCG，零依赖、可复现）产生 250 组种子 × 3 个随机区间集合、对 17 条代数定律逐一用独立端点判定校验——并用变异测试验证过它能捕获人为注入的差集缺陷。差分验证共六轮：独立 Python 参考 468 组 `(版本, 范围)` 对照、123 组连字符范围对拍、660 组「基础层 `satisfies` + 代数层 `contains`」双层对拍、3572 组与 4186 组 `semver@7` 差分对照，以及终版 4700 组 × 2 层（9400 条断言）的双层差分对照，全部一致。累计修复 `>` 比较符误作上界、无界区间合并与补集边界、Int32 溢出回绕、构建元数据连字符误判、范围上界溢出、相等端点排序、排他上界缺少 `-0` 导致双层预发布语义不一致、零主版本号 caret/tilde 上界忽略书写精度、partial 比较符被拒绝、代数层缺失预发布 opt-in 策略、空范围被误判为非法、操作符与版本之间的空白或制表符被拒、预发布 opt-in 跨 OR 分支泄漏、全集 OR 分支错误保留预发布准入共 15 类真实缺陷（按更细粒度归并为 21 个具体缺陷）。
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
│   └── main.mbt             # parse / compare / check / algebra / diagnose / demo 子命令
├── INTERNAL_NOTES.md        # 内部素材（不要当申报书提交）
├── DEVELOPMENT_LOG.md       # 开发过程与 AI 使用说明
├── CHANGELOG.md
└── LICENSE                  # Apache-2.0
```

## 安装

**作为依赖引入**（发布在 mooncakes.io）：

```bash
moon add xianjuanzi/mbt-semver
```

在 MoonBit 源码中用 `@semver` 引用库包，例如 `@semver.parse_version("1.2.3")`。

**从源码运行**：需要 MoonBit 工具链（`moon` 与 `moonc`，版本不低于 1.0.0-rc1）。

```bash
git clone https://github.com/xianjuanzi/mbt-semver.git
cd mbt-semver
```

## 快速开始

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
moon run cmd -- algebra
moon run cmd -- diagnose '>=1.0.0 <3.0.0' '>=2.0.0 <4.0.0'
```

`moon run cmd -- diagnose` 把两个范围渲染成冲突诊断报告（重叠段、各自独占段、并集与是否可同时满足）：

```text
== conflict diagnosis ==
A        = >=1.0.0 <3.0.0
B        = >=2.0.0 <4.0.0
overlap  = >=2.0.0 <3.0.0
A only   = >=1.0.0 <2.0.0
B only   = >=3.0.0 <4.0.0
union    = >=1.0.0 <4.0.0
status   = COMPATIBLE (partial overlap)
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
| `^1.2.3` | `>=1.2.3 <2.0.0-0`（`-0` 上界排除下个元组的全部预发布） |
| `^0` / `^0.x`、`^0.0` / `^0.0.x`、`^0.0.0` | `<1.0.0-0`、`<0.1.0-0`、`<0.0.1-0`（按**书写精度**决定上界，不是按补零后的数值） |
| `~0.x` | `>=0.0.0 <1.0.0-0`（书写精度只到 major，与 `~0` 相同） |
| `>1`、`<=1.2`、`=1.2` | partial 版本可作比较符操作数：`>=2.0.0`、`<1.3.0-0`、`>=1.2.0 <1.3.0-0` |
| `~1.2.3` / `~1.2` | 锁定到次版本：`>=1.2.3 <1.3.0-0` |
| `1.x` / `1.2.x` / `*` | 通配符 |
| `^1.0.0 || ^3.0.0` | `||` 表示 OR |
| `1.2.3 - 2.3.4` | 连字符闭区间 `>=1.2.3 <=2.3.4`（partial 端按 node-semver 规则扩展） |

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
  println(@semver.algebra_diagnose(a, b))                                // 冲突诊断报告
}
```

- 任意范围先解析成**规范化区间集合**：排序、去重、合并重叠区间；两种不同写法若表示同一版本集合，规范化结果相同（等价判定）。
- `union` / `intersection` / `difference` / `complement` 对集合封闭，可组合嵌套。
- `parse_algebra` 解析出的区间携带 node-semver 的预发布 opt-in 策略（只有范围中显式写出的 `major.minor.patch` 元组才接受该元组的预发布），因此代数层 `contains` 与基础层 `satisfies` 对预发布版本给出**相同结论**；集合运算按「交集取更严格策略、并集保留各自策略」合成，规范化的纯区间运算仍由 `Interval::new` 提供。
- `satisfiable(a, b)` 判定两个范围是否可能同时成立，可直接用于依赖冲突预检。
- `algebra_diagnose(a, b)` 把交集、差集、并集与可满足性渲染成可读的冲突诊断报告（区间集合 → 诊断渲染）。
- `algebra` / `diagnose` CLI 子命令可运行上述全部演示。

## 测试与验证

```text
$ moon test
Total tests: 51, passed: 51, failed: 0.
```

覆盖内容包括：

- SemVer 官方优先级示例链（`alpha` → `alpha.1` → `alpha.beta` → `beta` → `beta.2` → `beta.11` → `rc.1` → 正式版）
- 前导零、空标识符、非法字符、多余组件等拒绝用例
- 构建元数据不参与优先级
- caret / tilde / 通配 / OR / AND 范围语义；`>` 比较符边界（含基础模块缺陷修复）
- 预发布版本的选择性匹配；约束冲突报错与最高版本选择
- **集合代数**：空/全集、无界端点（`-∞` / `+∞`）合并与补集、端点开闭、重叠与相接合并、并/交/差/补、可满足性、规范化等价
- **代数定律**：双重补集为恒等、德摩根律、`A∪¬A=全集`、`A∩¬A=空`、幂等/交换/结合/分配/吸收律、预发布版本在集合中的优先级，含有限版本域上的穷举验证与确定性伪随机属性测试（28 个集合代数专项测试）

## 与赛事验收标准的对应

| 官方验收项 | 本项目情况 |
| --- | --- |
| MoonBit 为主 | 全部实现与测试均为 MoonBit，零第三方依赖 |
| 仓库公开、提交可追踪 | 提交到公开 GitHub 仓库，按模块分阶段提交（见 `DEVELOPMENT_LOG.md`） |
| 能运行 | `moon check` / `moon test` 通过（51/51）；`cmd` 提供 parse/compare/check/algebra/diagnose/demo 六个可运行子命令 |
| 工作有效 | 赛道一新项目方向；初审后按反馈聚焦到竞品空白的范围集合代数，形成实质差异 |
| 开源合规 | Apache-2.0 许可证；未移植第三方代码 |
| AI 可解释 | AI 参与代码与文档生成，逐项由参赛者审查、测试并解释，详见 `DEVELOPMENT_LOG.md` |

## 项目状态：终版

原「后续计划」三项已全部落地，本版本为终版：

- ✅ **属性测试**：`range_algebra.mbt` 内置确定性伪随机属性测试（Park-Miller LCG，零依赖、种子可复现），250 组种子 × 3 个随机区间集合逐条校验 17 条代数定律；已通过变异测试验证其能捕获人为注入的缺陷。
- ✅ **冲突诊断报告渲染**：`algebra_diagnose(a, b)` 公开 API 与 `diagnose` CLI 子命令，把区间集合渲染为含重叠段、独占段、并集和状态判定的可读报告。
- ✅ **发布到 mooncakes.io**：已发布为 `xianjuanzi/mbt-semver`，文档页 `https://mooncakes.io/docs/xianjuanzi/mbt-semver`，版本 0.5.7；可由依赖方用 `moon add xianjuanzi/mbt-semver` 引入。

三项后续计划均已落地，本版本为终版。仓库地址与 GitHub ID 已按 `xianjuanzi` 填好，按 `运行与上传指南.md` 完成上传与报名即可。
