# Changelog

All notable changes to this project are documented in this file.

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
