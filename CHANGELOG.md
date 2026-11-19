# Changelog

All notable changes to this project are documented in this file.

## [0.1.0] - 2026-11-19

### Added

- Strict SemVer 2.0.0 parsing with structured `Version` values and descriptive errors.
- Precedence comparison implementing the official SemVer example chain; `Eq` and `Compare` instances.
- Range expressions: exact versions, `*`, `1.x`, `1.2.x`, caret, tilde, comparison operators, whitespace AND, `||` OR, and prerelease opt-in.
- Direct dependency constraint resolution: intersect all constraints per package and select the highest available version.
- Runnable CLI demo with `parse`, `compare`, `check` and `demo` commands.
- 12 unit tests, README, one-page project proposal, development/AI disclosure and Apache-2.0 license.
