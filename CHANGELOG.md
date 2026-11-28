# Changelog

All notable changes to this project are documented in this file.

## [0.5.7] - 2026-11-27 (final)

### Changed (publishing)

- Module namespace changed from `hackathon/mbt-semver` to `xianjuanzi/mbt-semver` to match the author's mooncakes.io account; `cmd/moon.pkg` import updated accordingly.
- Published to mooncakes.io as `xianjuanzi/mbt-semver`; docs at `https://mooncakes.io/docs/xianjuanzi/mbt-semver`.
- README corrected: the mooncakes.io publication item is now marked done rather than pending.
- No semantic changes; `moon test` remains 51/51 passing.

## [0.5.6] - 2026-11-23 (final)

### Fixed (final self-check: universal OR branch collapses prerelease opt-in)

- `range.mbt::parse_range`: node-semver desugars an OR branch that is the universal set (`*`, `x`, `>=0.0.0`, `>=0`, `>=*`, `<=*`, empty) into a single ANY comparator, and `U || X = U` collapses the whole range to `*`. Our parser kept all branches, so a prerelease could slip through a sibling opt-in branch: `1.5.0-beta` against `* || ^1.5.0-beta` was wrongly accepted. Added `range_is_universal`; if any branch is universal the whole range now collapses to `*`, matching node-semver. The algebra layer inherits this through `from_range_set`.
- Verification: a systematic OR-isolation differential generated 289 two-branch ranges x 12 versions = **3468** cases checked at both layers (6936 assertions), 6936/6936 matching after the fix; this is what exposed the defect. Generated file deleted after the run.
- Tests: 50 -> 51. Total 51/51 passing. Cumulative defects: 21 concrete / 15 categories.

## [0.5.5] - 2026-11-23

### Fixed (prerelease opt-in isolation across `||` branches)

- `range.mbt`: prerelease opt-in keys were collected globally across every `||` branch of a range, so a prerelease mentioned in one branch wrongly authorised the same `major.minor.patch` tuple in another branch with no opt-in of its own. `semver@7` rejects `1.5.0-rc` against `^1.0.0 || =1.5.0-beta`, while the old implementation accepted it. `RangeSet` now stores `keys_per_range : Array[Array[String]]`, one key list per conjunctive group; `satisfies` admits a prerelease only through a branch that both opts in to its tuple and contains the version.
- `range_algebra.mbt`: `from_range_set` attaches each group's own keys to its interval instead of sharing one global array, keeping `contains` consistent with `satisfies` and node-semver.
- `range.mbt`: prerelease-key extraction now reuses `range_tokens`, so a tab/spaced operator such as `>=\t1.0.0-alpha` opts in exactly like its compact form.
- Verification: regenerated the `semver@7` differential set with cross-branch prerelease and tab opt-in cases added: 100 range expressions x 47 versions = **4700** cases checked at both layers (9400 assertions), 9400/9400 matching. Generated file deleted after the run.
- Tests: 49 -> 50. Total 50/50 passing. Cumulative defects: 20 concrete / 14 categories.

## [0.5.4] - 2026-11-23

### Fixed (whitespace tolerance in range syntax)

- `range.mbt::parse_range_part`: node-semver accepts any whitespace as a separator and allows an operator to be separated from its version (`>= 1.2.3`, `> 1`, `1.2.3\t-\t2.3.4`). The old parser split only on literal spaces and treated a bare `>=` as a missing-version error; tabs also broke hyphen-range detection. It now normalises tabs/newlines to spaces and rejoins a standalone operator with the next token before hyphen detection. Note: MoonBit's `String::replace` replaces only the first occurrence, so `replace_all` is required here.
- Verification: regenerated the temporary `semver@7` differential set with seven whitespace variants added: 93 range expressions x 45 versions = **4186** cases checked at both layers (8372 assertions), 8372/8372 matching. Generated file deleted after the run.
- Tests: 48 -> 49. Total 49/49 passing. Cumulative defects: 18 concrete / 13 categories.

## [0.5.3] - 2026-11-23

### Fixed (final self-check: prerelease opt-in at the algebra layer, empty range)

- `range_algebra.mbt`: `Interval` now carries an optional `prerelease_keys` policy. `from_range_set` copies the opt-in keys from `parse_range`, so `contains(parse_algebra("^1.0.0-alpha"), 1.5.0-beta)` is now `false`, matching `satisfies` and node-semver's "prereleases of a different tuple" rule. Before, the algebra layer used pure SemVer precedence and returned `true` — the same range had two different meanings in the two layers.
- Set operations compose policies: `intersection` takes the stricter policy, `union` keeps each interval's own policy, `normalise` never merges intervals with different policies, and `is_universal` checks coverage independently of policies. `Interval::new` still builds a pure interval (`prerelease_keys: None`), so the exhaustive/property tests are unchanged.
- `range.mbt`: an empty or whitespace-only range is now the X-range `*` (`>=0.0.0`), matching node-semver. It used to be rejected as "empty range".
- Verification: regenerated a temporary differential test from `semver@7`: 86 range expressions x 45 versions = **3864** cases checked at **both** layers (7728 assertions), including cross-tuple prereleases and empty ranges; 7728/7728 matched. The generated file was deleted after the run.
- Tests: 46 -> 48. Total 48/48 passing. Cumulative defects: 17 concrete / 12 categories.

## [0.5.2] - 2026-11-23

### Fixed (final self-check: node-semver written-precision and partial comparators)

- `range.mbt`: caret bounds were computed from the zero-padded `Version` value alone, so `^0`, `^0.x`, `^0.0` and `^0.0.x` all desugared to `<0.0.1-0`. node-semver decides from the *written* precision: `^0` / `^0.x` = `<1.0.0-0`, `^0.0` / `^0.0.x` = `<0.1.0-0`, while the fully written `^0.0.0` = `<0.0.1-0`. Added `written_components` and `caret_level`; `^0` used to reject every `0.x` release above `0.0.0`.
- `range.mbt`: tilde used a plain dot-count as "minor specified", so `~0.x` bumped minor (`<0.1.0-0`) instead of major (`<1.0.0-0`). It now uses the same written-component count as caret.
- `range.mbt`: comparators with a partial operand (`>1`, `>=1.2`, `<1`, `<=1.2`, `=1.2`) were rejected outright. They now desugar to node-semver X-range semantics (`>1` = `>=2.0.0`, `<=1.2` = `<1.3.0-0`, `=1.2` = `>=1.2.0 <1.3.0-0`). Wildcard operands (`^*`, `~*`, `>=x`) now mean the universal set.
- `range_algebra.mbt`: regression tests pin the written-precision caret bounds and partial comparators at the algebra layer, which shares `parse_range`.
- Verification: regenerated a temporary differential test from the live `semver@7` reference: 76 range expressions x 47 versions = **3572** `(version, range, expected)` assertions checked by MoonBit; 3572/3572 matched. The generated file was deleted after the run and is not in the repository.
- Tests: 43 -> 46. Total 46/46 passing. Cumulative defects: 15 concrete / 10 categories.

## [0.5.1] - 2026-11-23

### Fixed (final self-check: base/algebra prerelease consistency)

- `range.mbt`: caret/tilde/partial exclusive upper bounds were `<X.Y.Z` instead of node-semver's `<X.Y.Z-0`. The base layer hid this via prerelease opt-in, but the algebra layer works on pure intervals, so `contains(parse("^1.2.3"), 2.0.0-alpha)` returned `true` while `satisfies(2.0.0-alpha, "^1.2.3")` returned `false`. Added `upper_with_zero` so all bumped exclusive bounds carry `-0`, making the two layers agree and matching node-semver. Hyphen partial upper ends already used `-0` and are unchanged.
- `range_algebra.mbt`: regression test `exclusive upper bounds exclude the next tuple's prereleases` pins six range forms against both layers.
- Differential check: 330 version/range pairs x 2 layers (660 assertions) against an independent node-semver reference, all matching.
- Tests: 42 -> 43. Total 43/43 passing.

## [0.5.0] - 2026-11-23 (final)

### Added (final: property testing and conflict diagnosis)

- `range_algebra.mbt`: deterministic QuickCheck-style property test. A Park-Miller LCG (zero dependency, reproducible seeds) generates 250 seeds x 3 pseudo-random interval sets; 17 boolean-algebra laws are checked against an independent endpoint-based membership oracle over a dense probe domain that makes open/closed endpoints observable. Mutation testing (injecting a wrong `difference`) confirmed the test catches the defect at seed 1.
- `range_algebra.mbt`: `algebra_diagnose(a, b)` renders a readable conflict report (both canonical sets, overlap, exclusive parts, union, COMPATIBLE/CONFLICT status) from pure algebra operations, with unit tests for partial overlap, conflict and subset cases.
- `cmd/main.mbt`: new `diagnose <range-a> <range-b>` subcommand; `usage` updated. CLI now exposes parse/compare/check/algebra/diagnose/demo.
- README: former "后续计划" section replaced by a final-state section; all three items resolved (property test ✅, diagnosis rendering ✅, mooncakes.io publish left to the author's account as `moon publish` requires `moon login`).
- Tests: 40 -> 42 (1 property test, 1 diagnosis report test). Total 42/42 passing.

## [0.4.0] - 2026-11-23

### Added (post-registration approval: hyphen ranges)

- `range.mbt`: npm/node-semver hyphen ranges `X - Y`, desugared with the official Hyphen Ranges semantics from node-semver:
  - `1.2.3 - 2.3.4` := `>=1.2.3 <=2.3.4` (both ends inclusive).
  - partial left side is padded with zeroes (`1.2 - 2.3.4` := `>=1.2.0 <=2.3.4`).
  - partial right side expands to the next tuple and excludes all its prereleases (`1.2.3 - 2.3` := `>=1.2.3 <2.4.0-0`, `1.2.3 - 2` := `>=1.2.3 <3.0.0-0`).
  - wildcard side is unbounded (`1.2.3 - *`); prerelease endpoints opt in to their own tuple; malformed hyphens are rejected.
- `range_algebra.mbt`: hyphen ranges parse into the same canonical interval set as their hand-written comparator equivalents, and compose with union/intersection/difference/complement/satisfiable.
- `cmd/main.mbt`: the `algebra` demo now prints the desugared interval set for each hyphen form.
- Tests: 38 -> 40 (1 hyphen-range case group in `range.mbt`, 1 canonical-equivalence group in `range_algebra.mbt`); an independent Python reference produced 123 differential assertions for hyphen ranges, all matching.

## [0.2.0] - 2026-11-20

### Added (re-submission: range set algebra)

- `semver/range_algebra.mbt`: parse any range into a canonical, normalised set of disjoint intervals.
- Set operations closed over interval sets: `union`, `intersection`, `difference`, `complement`.
- Decision helpers: `satisfiable`, `contains`, `is_empty`, `is_universal`, plus normalised equivalence.
- `algebra_` prefixed public API and an `algebra` CLI subcommand demonstrating all operations.
- 22 unit tests for the algebra (total 38), covering De Morgan, double complement, complement laws, idempotence/commutativity/associativity/distributivity, unbounded endpoints and prerelease precedence, plus exhaustive verification over a finite version domain (all intervals and triples checked against independent pointwise reference semantics).

### Fixed

- `range.mbt::parse_comparator`: `>` was implemented as an upper bound instead of a lower bound, so `1.5.0 > 1.0.0` wrongly evaluated to false. Corrected with a regression test.
- `range_algebra.mbt::lo_min` / `hi_max`: mixed `(None, Some(v))` bounds returned `Some(v)` instead of the unbounded extreme, dropping `-infinity` / `+infinity` during interval merging.
- `range_algebra.mbt::complement`: an unbounded lower bound in the first interval (or unbounded upper bound in the last) produced a spurious universal gap, so `complement(<2.0.0)` evaluated to `*`. Rewritten with explicit gap handling.
- `range_algebra.mbt::normalise`: touching intervals with no gap were not merged (`<1.0.0` and `>=1.0.0`), so `A ∪ ¬A` could not normalise to the universe. Added `intervals_mergeable` while keeping two open endpoints unmerged.
- `version.mbt::parse_version`: a hyphen inside build metadata (`1.2.3+build-1`) was mistaken for a prerelease separator and rejected. The `-` is now searched only before `+`.
- `version.mbt::parse_number`: Int32 overflow silently wrapped `2147483648` to `-2147483648`, breaking precedence (`2147483648.0.0 < 5.0.0`). Core components now use Int64 with explicit overflow rejection instead of wrapping.
- `version.mbt::compare_identifier` / `parse_ids`: prerelease numeric identifiers no longer depend on integer width. Leading zeroes are checked lexically and numeric comparison uses length-then-lexical order, so arbitrarily long identifiers remain valid and correctly ordered.

- `range.mbt::parse_comparator`: caret/tilde/partial upper bounds used `component + 1`, which overflowed to a negative value at the Int64 limit and turned a valid range into an empty interval (even the exact version failed to match). Bounds now saturate to "unbounded" via `bump_upper`, with a regression test.
- `range_algebra.mbt::lo_cmp`: when two intervals had equal lower endpoints, the comparator ignored inclusiveness, so a closed singleton sorted after an open interval and `normalise` failed to merge `>0.0.0` with `=0.0.0` into `>=0.0.0`. This broke canonical-form equivalence and De Morgan. Equal endpoints now sort the inclusive end first. Found by exhaustive triple testing, not by fixed cases.

### Docs

- Repositioned README and proposal around range-set algebra with a comparison table against moonsemver / moondepsolve / version.mbt / moonguard, documenting the substantive difference found after the first-round feedback.

## [0.1.0] - 2026-11-19

### Added

- Strict SemVer 2.0.0 parsing with structured `Version` values and descriptive errors.
- Precedence comparison implementing the official SemVer example chain; `Eq` and `Compare` instances.
- Range expressions: exact versions, `*`, `1.x`, `1.2.x`, caret, tilde, comparison operators, whitespace AND, `||` OR, and prerelease opt-in.
- Direct dependency constraint resolution: intersect all constraints per package and select the highest available version.
- Runnable CLI demo with `parse`, `compare`, `check` and `demo` commands.
- 12 unit tests, README, one-page project proposal, development/AI disclosure and Apache-2.0 license.
