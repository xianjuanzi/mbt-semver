// Copyright 2026 MoonBit Hackathon contributor
// Licensed under the Apache License, Version 2.0.

///|
/// One inclusive or exclusive end of a version range.
pub struct Bound {
  version : Version
  inclusive : Bool
}

///|
/// A single conjunctive range: lower AND upper.
pub struct Range {
  lower : Bound?
  upper : Bound?
}

///|
/// A disjunctive set of ranges (joined with `||`), plus the prerelease
/// opt-in keys *per conjunctive group*. node-semver scopes the opt-in to a
/// single comparator set: a prerelease mentioned in one `||` branch must not
/// authorise the same `major.minor.patch` prereleases in another branch.
/// `keys_per_range[i]` therefore belongs exclusively to `ranges[i]`.
pub struct RangeSet {
  ranges : Array[Range]
  keys_per_range : Array[Array[String]]
}

///|
fn empty_range() -> Range {
  { lower: None, upper: None, }
}

///|
fn key_of(version : Version) -> String {
  "\{version.major}.\{version.minor}.\{version.patch}"
}

///|
fn parse_owned(text : StringView) -> Result[Version, String] {
  parse_version(text.to_owned())
}

///|
/// Parse a partial version such as `1`, `1.2` or `1.2.x`, filling missing
/// components with zero. Prerelease/build suffixes are not accepted here.
fn parse_partial(text : StringView) -> Result[Version, String] {
  let pieces = text.split(".").collect()
  if pieces.length() > 3 {
    return Err("partial version has too many components: \{text}")
  }
  let numbers : Array[Int64] = []
  for piece in pieces {
    let p = piece.trim()
    if p == "x" || p == "X" || p == "*" {
      break
    }
    let mut digits = true
    for i = 0; i < p.length(); i = i + 1 {
      match p.get_char(i) {
        None => ()
        Some(ch) => if !ch.is_ascii_digit() { digits = false }
      }
    }
    if !digits || p.length() == 0 {
      return Err("invalid partial version: \{text}")
    }
    let n = match parse_version("\{p}.0.0") {
      Ok(v) => v.major
      Err(e) => return Err(e)
    }
    numbers.push(n)
  }
  if numbers.length() == 0 {
    return Err("partial version has no numeric component: \{text}")
  }
  let major = numbers[0]
  let minor = if numbers.length() > 1 { numbers[1] } else { 0 }
  let patch = if numbers.length() > 2 { numbers[2] } else { 0 }
  Ok(Version::new(major, minor, patch))
}

///|
/// An exclusive upper bound must also exclude every prerelease of the next
/// tuple. In node-semver, `^1.2.3` desugars to `>=1.2.3 <2.0.0-0`, not
/// `<2.0.0`: since `2.0.0-0` is the smallest `2.0.0-*` prerelease, any
/// `<2.0.0` bound would wrongly include `2.0.0-alpha` at the pure interval
/// layer. The base `satisfies` layer hides this via prerelease opt-in, but the
/// algebra layer (`parse_algebra` -> `contains`) works on pure intervals, so
/// without `-0` the two layers disagree. This appends the `-0` identifier to
/// a bumped upper bound; `None` is propagated for the saturation case.
fn upper_with_zero(bumped : Version?) -> Version? {
  match bumped {
    None => None
    Some(base) =>
      match parse_version("\{base.major}.\{base.minor}.\{base.patch}-0") {
        Ok(v) => Some(v)
        // The text is constructed from validated Int64 components, so this
        // cannot fail; keep the bound unbounded rather than inventing one.
        Err(_) => None
      }
  }
}

///|
/// Form the exclusive upper bound by incrementing one core component, with a
/// carry towards the next more significant component on saturation. `level`
/// selects the component: 0 = patch, 1 = minor, 2 = major.
///
/// Returns `None` only when no greater version can be represented (every
/// component is at `MAX_CORE` in the relevant prefix). Callers interpret this
/// as an unbounded upper end. This prevents `major + 1` from silently
/// overflowing to a negative number at the Int64 limit, which used to turn a
/// valid caret/tilde range into an empty interval.
fn bump_upper(v : Version, level : Int32) -> Version? {
  if level == 0 {
    if v.patch < MAX_CORE {
      Some(Version::new(v.major, v.minor, v.patch + 1L))
    } else if v.minor < MAX_CORE {
      Some(Version::new(v.major, v.minor + 1L, 0L))
    } else if v.major < MAX_CORE {
      Some(Version::new(v.major + 1L, 0L, 0L))
    } else {
      None
    }
  } else if level == 1 {
    if v.minor < MAX_CORE {
      Some(Version::new(v.major, v.minor + 1L, 0L))
    } else if v.major < MAX_CORE {
      Some(Version::new(v.major + 1L, 0L, 0L))
    } else {
      None
    }
  } else if v.major < MAX_CORE {
    Some(Version::new(v.major + 1L, 0L, 0L))
  } else {
    None
  }
}

///|
/// Number of explicitly written numeric components before the first wildcard.
/// node-semver decides caret/tilde/comparator upper bounds from the *written
/// precision*, not from the zero-padded `Version` value: `^0` (<1.0.0-0) and
/// `^0.0.0` (<0.0.1-0) both parse to 0.0.0 but must have different bounds.
fn written_components(text : StringView) -> Int32 {
  partial_numeric_count(text)
}

///|
/// Caret upper-bound level: 0 = patch, 1 = minor, 2 = major (node-semver).
/// A missing minor/patch is "flexible", so `^0.0` bumps minor while the fully
/// written `^0.0.0` bumps patch. A missing minor bumps major (`^0`, `^0.x`).
fn caret_level(v : Version, written : Int32) -> Int32 {
  if v.major > 0 {
    2
  } else if written >= 3 {
    if v.minor > 0 {
      1
    } else {
      0
    }
  } else if written == 2 {
    1
  } else {
    2
  }
}

///|
/// Tilde upper-bound level: an explicitly written minor bumps minor,
/// otherwise major. `~0.x` is the same as `~0`: both allow any 0.x.
fn tilde_level(written : Int32) -> Int32 {
  if written >= 2 {
    1
  } else {
    2
  }
}

///|
fn upper_for_caret(v : Version, written : Int32) -> Version? {
  upper_with_zero(bump_upper(v, caret_level(v, written)))
}

///|
fn upper_for_tilde(v : Version, written : Int32) -> Version? {
  upper_with_zero(bump_upper(v, tilde_level(written)))
}

///|
/// Build a bounded-below range with an optional exclusive upper bound.
fn bounded_range(v : Version, upper : Version?) -> Range {
  {
    lower: Some({ version: v, inclusive: true, }),
    upper: match upper {
      Some(u) => Some({ version: u, inclusive: false, })
      None => None
    },
  }
}

///|
fn parse_comparator(token : StringView) -> Result[Range, String] {
  if token == "*" || token == "x" || token == "X" {
    return Ok(empty_range())
  }
  let mut op = ""
  let mut rest = token
  if token.has_prefix(">=") {
    op = ">="
    rest = token[2:]
  } else if token.has_prefix("<=") {
    op = "<="
    rest = token[2:]
  } else if token.has_prefix(">") {
    op = ">"
    rest = token[1:]
  } else if token.has_prefix("<") {
    op = "<"
    rest = token[1:]
  } else if token.has_prefix("=") {
    op = "="
    rest = token[1:]
  } else if token.has_prefix("^") {
    op = "^"
    rest = token[1:]
  } else if token.has_prefix("~") {
    op = "~"
    rest = token[1:]
  }
  rest = rest.trim()
  if rest.length() == 0 {
    return Err("comparator is missing a version: \{token}")
  }
  // node-semver accepts a wildcard as the operand of any comparator:
  // `^*`, `~*` and `>=x` all mean "any version".
  if rest == "*" || rest == "x" || rest == "X" {
    return Ok(empty_range())
  }
  let written = written_components(rest)
  if written == 0 {
    return Err("invalid version in comparator: \{token}")
  }

  if op == "^" || op == "~" {
    let v = match parse_owned(rest) {
      Ok(v) => v
      Err(_) =>
        match parse_partial(rest) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
    }
    let upper = if op == "^" {
      upper_for_caret(v, written)
    } else {
      upper_for_tilde(v, written)
    }
    return Ok(bounded_range(v, upper))
  }

  match parse_owned(rest) {
    Ok(v) =>
      if op == ">" {
        Ok({ lower: Some({ version: v, inclusive: false, }), upper: None, })
      } else if op == ">=" {
        Ok({ lower: Some({ version: v, inclusive: true, }), upper: None, })
      } else if op == "<" {
        Ok({ lower: None, upper: Some({ version: v, inclusive: false, }), })
      } else if op == "<=" {
        Ok({ lower: None, upper: Some({ version: v, inclusive: true, }), })
      } else {
        Ok({
          lower: Some({ version: v, inclusive: true, }),
          upper: Some({ version: v, inclusive: true, }),
        })
      }
    Err(_) => {
      // A partial operand is an X-range, and node-semver applies the
      // comparator to that whole range: `>1` = `>=2.0.0`, `<=1.2` =
      // `<1.3.0-0`, `=1.2` = `>=1.2.0 <1.3.0-0`, `<1` = `<1.0.0-0`.
      // Rejecting these forms used to make valid ranges unparseable.
      let p = match parse_partial(rest) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let level = tilde_level(written)
      if op == ">" {
        match bump_upper(p, level) {
          None => Ok(empty_range())
          Some(b) =>
            Ok({ lower: Some({ version: b, inclusive: true, }), upper: None, })
        }
      } else if op == ">=" {
        Ok({ lower: Some({ version: p, inclusive: true, }), upper: None, })
      } else if op == "<" {
        let v = match parse_version("\{p.major}.\{p.minor}.\{p.patch}-0") {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        Ok({ lower: None, upper: Some({ version: v, inclusive: false, }), })
      } else if op == "<=" {
        Ok({
          lower: None,
          upper: match upper_with_zero(bump_upper(p, level)) {
            None => None
            Some(u) => Some({ version: u, inclusive: false, })
          },
        })
      } else {
        Ok(bounded_range(p, upper_with_zero(bump_upper(p, level))))
      }
    }
  }
}

///|
fn stronger_lower(a : Bound?, b : Bound?) -> Bound? {
  match (a, b) {
    (None, other) => other
    (other, None) => other
    (Some(x), Some(y)) => {
      let c = compare_version(x.version, y.version)
      if c < 0 {
        Some(y)
      } else if c > 0 {
        Some(x)
      } else {
        Some({ version: x.version, inclusive: x.inclusive && y.inclusive, })
      }
    }
  }
}

///|
fn stronger_upper(a : Bound?, b : Bound?) -> Bound? {
  match (a, b) {
    (None, other) => other
    (other, None) => other
    (Some(x), Some(y)) => {
      let c = compare_version(x.version, y.version)
      if c < 0 {
        Some(x)
      } else if c > 0 {
        Some(y)
      } else {
        Some({ version: x.version, inclusive: x.inclusive && y.inclusive, })
      }
    }
  }
}

///|
/// Count numeric components of a partial version, stopping at the first
/// wildcard (`x`, `X` or `*`). Used to decide which boundary a partial upper
/// end in a hyphen range expands to.
fn partial_numeric_count(text : StringView) -> Int32 {
  let pieces = text.split(".").collect()
  let mut n = 0
  for piece in pieces {
    let p = piece.trim()
    if p == "x" || p == "X" || p == "*" {
      break
    }
    n = n + 1
  }
  n
}

///|
/// Parse a hyphen range `X - Y` with node-semver semantics:
/// `1.2.3 - 2.3.4` = `>=1.2.3 <=2.3.4` (both ends inclusive). A partial left
/// side is padded with zeroes (`1.2 - 2.3.4` = `>=1.2.0 <=2.3.4`); a partial
/// right side expands to the next boundary and becomes an exclusive
/// `<A.B.C-0` end (`1.2.3 - 2.3` = `>=1.2.3 <2.4.0-0`,
/// `1.2.3 - 2` = `>=1.2.3 <3.0.0-0`). A wildcard side is unbounded.
fn parse_hyphen_range(
  left : StringView,
  right : StringView,
) -> Result[Range, String] {
  let lower_version = if left == "*" || left == "x" || left == "X" {
    Version::new(0L, 0L, 0L)
  } else {
    match parse_owned(left) {
      Ok(v) => v
      Err(_) =>
        match parse_partial(left) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
    }
  }
  let upper_bound : Bound? = if right == "*" || right == "x" || right == "X" {
    None
  } else {
    match parse_owned(right) {
      Ok(v) => Some({ version: v, inclusive: true, })
      Err(_) => {
        let p = match parse_partial(right) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        let numeric = partial_numeric_count(right)
        let level : Int32 = if numeric >= 2 { 1 } else { 2 }
        match bump_upper(p, level) {
          None => None
          Some(base) => {
            // `<A.B.C-0` excludes every prerelease of the next tuple, which is
            // exactly how node-semver desugars a partial upper end.
            let zero_text = "\{base.major}.\{base.minor}.\{base.patch}-0"
            match parse_version(zero_text) {
              Ok(zero) => Some({ version: zero, inclusive: false, })
              Err(e) => return Err(e)
            }
          }
        }
      }
    }
  }
  Ok({
    lower: Some({ version: lower_version, inclusive: true, }),
    upper: upper_bound,
  })
}

///|
/// Normalise arbitrary whitespace and rejoin a bare operator with its
/// operand. Shared by range parsing and prerelease-key extraction so the two
/// always agree on how one conjunctive group is tokenised (`>=\t1.0.0-a`
/// must opt in just like `>=1.0.0-a`).
fn range_tokens(part : StringView) -> Result[Array[StringView], String] {
  let text = part
    .to_owned()
    .replace_all(old="\t", new=" ")
    .replace_all(old="\n", new=" ")
    .replace_all(old="\r", new=" ")
  let split = text.trim().split(" ").collect()
  let tokens : Array[StringView] = []
  let mut pending : StringView = ""
  for token in split {
    let t = token.trim()
    if t.length() == 0 {
      continue
    }
    if t == ">" ||
      t == ">=" ||
      t == "<" ||
      t == "<=" ||
      t == "=" ||
      t == "^" ||
      t == "~" {
      pending = t
    } else if pending.length() > 0 {
      tokens.push(pending + t)
      pending = ""
    } else {
      tokens.push(t)
    }
  }
  if pending.length() > 0 {
    return Err("comparator is missing a version: \{part}")
  }
  Ok(tokens)
}

///|
fn parse_range_part(part : StringView) -> Result[Range, String] {
  // node-semver treats any whitespace as a separator, and allows an operator
  // to be separated from its version (`>= 1.2.3` == `>=1.2.3`).
  let tokens = match range_tokens(part) {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  // A standalone `-` surrounded by whitespace is a hyphen range separator.
  // Any other placement is rejected instead of being silently mis-parsed.
  let mut dashes = 0
  let mut dash_at = -1
  for i = 0; i < tokens.length(); i = i + 1 {
    if tokens[i] == "-" {
      dashes = dashes + 1
      dash_at = i
    }
  }
  if dashes > 0 {
    if dashes != 1 || tokens.length() != 3 || dash_at != 1 {
      return Err("malformed hyphen range: \{part}")
    }
    return parse_hyphen_range(tokens[0], tokens[2])
  }
  let mut result = empty_range()
  let mut count = 0
  for token in tokens {
    let one = match parse_comparator(token) {
      Ok(r) => r
      Err(e) => return Err(e)
    }
    result = {
      lower: stronger_lower(result.lower, one.lower),
      upper: stronger_upper(result.upper, one.upper),
    }
    count = count + 1
  }
  if count == 0 {
    return Err("empty range")
  }
  Ok(result)
}

///|
/// Parse a npm-style semver range. Supports `*`, partial versions (`1`,
/// `1.2`, `1.2.x`), caret, tilde, comparison operators, hyphen ranges
/// (`1.2.3 - 2.3.4`), whitespace for AND and `||` for OR.
pub fn parse_range(input : String) -> Result[RangeSet, String] {
  // node-semver: "" (and whitespace-only) is the X-range `*`, i.e. >=0.0.0.
  // An empty operand used to be reported as an error.
  if input.trim().length() == 0 {
    return Ok({ ranges: [empty_range()], keys_per_range: [[]], })
  }
  let ranges : Array[Range] = []
  let keys_per_range : Array[Array[String]] = []
  for part in input.split("||").collect() {
    let r = match parse_range_part(part) {
      Ok(r) => r
      Err(e) => return Err(e)
    }
    let keys = match keys_for_part(part) {
      Ok(k) => k
      Err(e) => return Err(e)
    }
    ranges.push(r)
    keys_per_range.push(keys)
  }
  // node-semver desugars an OR branch that is the universal set (`*`, `x`,
  // `>=0.0.0`, `>=0`, `>=*`, `<=*` ... all become the empty comparator) into
  // a single ANY comparator. Because `U || X = U`, the whole range collapses
  // to `*`. This matters for prereleases: an explicitly opting-in branch is
  // swallowed, so `* || ^1.5.0-beta` rejects `1.5.0-beta` in node-semver.
  // Keep that behaviour: a universal branch collapses the whole set.
  for r in ranges {
    if range_is_universal(r) {
      return Ok({ ranges: [empty_range()], keys_per_range: [[]], })
    }
  }
  Ok({ ranges, keys_per_range, })
}

///|
/// Whether a conjunctive range covers the entire version space. SemVer
/// versions are non-negative, so `>=0.0.0` (and its partial/wildcard spellings
/// that parse to lower = 0.0.0) with no upper bound is universal.
fn range_is_universal(r : Range) -> Bool {
  let has_upper = match r.upper {
    None => false
    Some(_) => true
  }
  if has_upper {
    return false
  }
  match r.lower {
    None => true
    Some(b) =>
      if !b.inclusive {
        false
      } else {
        compare_version(b.version, Version::new(0L, 0L, 0L)) <= 0
      }
  }
}

///|
/// Collect the `major.minor.patch` tuples explicitly written with a
/// prerelease inside ONE conjunctive group. Extraction is per `||` branch:
/// a prerelease mentioned in one branch must not authorise the same tuple in
/// another. Reuses `range_tokens` so tab/spaced operators opt in identically.
fn keys_for_part(part : StringView) -> Result[Array[String], String] {
  let keys : Array[String] = []
  let tokens = match range_tokens(part) {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  for token in tokens {
    let stripped = if token.has_prefix(">=") || token.has_prefix("<=") {
      token[2:]
    } else if token.has_prefix("^") ||
      token.has_prefix("~") ||
      token.has_prefix(">") ||
      token.has_prefix("<") ||
      token.has_prefix("=") {
      token[1:]
    } else {
      token
    }
    match parse_version(stripped.to_owned()) {
      Ok(v) => if v.prerelease.length() > 0 { keys.push(key_of(v)) }
      Err(_) => ()
    }
  }
  Ok(keys)
}

///|
fn in_range(range : Range, version : Version) -> Bool {
  match range.lower {
    None => ()
    Some(bound) => {
      let c = compare_version(version, bound.version)
      if bound.inclusive {
        if c < 0 {
          return false
        }
      } else if c <= 0 {
        return false
      }
    }
  }
  match range.upper {
    None => ()
    Some(bound) => {
      let c = compare_version(version, bound.version)
      if bound.inclusive {
        if c > 0 {
          return false
        }
      } else if c >= 0 {
        return false
      }
    }
  }
  true
}

///|
/// Check whether a version satisfies a parsed range set.
pub fn satisfies(version : Version, set : RangeSet) -> Bool {
  let is_prerelease = version.prerelease.length() > 0
  let k = key_of(version)
  // The opt-in is scoped to a single `||` branch: a prerelease version is
  // admitted only by a branch that both (a) explicitly mentions the same
  // major.minor.patch with a prerelease and (b) contains the version.
  for i = 0; i < set.ranges.length(); i = i + 1 {
    if is_prerelease {
      let mut allowed = false
      for key in set.keys_per_range[i] {
        if key == k {
          allowed = true
        }
      }
      if !allowed {
        continue
      }
    }
    if in_range(set.ranges[i], version) {
      return true
    }
  }
  false
}

///|
/// Convenience wrapper: parse a range and check a version in one call.
pub fn satisfies_text(version : Version, text : String) -> Result[Bool, String] {
  match parse_range(text) {
    Ok(set) => Ok(satisfies(version, set))
    Err(e) => Err(e)
  }
}

///|
fn[T, E] result_is_ok(result : Result[T, E]) -> Bool {
  match result {
    Ok(_) => true
    Err(_) => false
  }
}

///|
fn v_of(text : String) -> Version raise {
  match parse_version(text) {
    Ok(v) => v
    Err(e) => fail("invalid test fixture \{text}: \{e}")
  }
}

///|
fn check(version : String, range : String) -> Bool raise {
  match satisfies_text(v_of(version), range) {
    Ok(v) => v
    Err(e) => fail("invalid range fixture: \{e}")
  }
}

///|
test "caret and tilde" {
  inspect(check("1.2.3", "^1.2.3"), content="true")
  inspect(check("1.9.0", "^1.2.3"), content="true")
  inspect(check("2.0.0", "^1.2.3"), content="false")
  inspect(check("0.2.9", "^0.2.3"), content="true")
  inspect(check("0.3.0", "^0.2.3"), content="false")
  inspect(check("0.0.3", "^0.0.3"), content="true")
  inspect(check("0.0.4", "^0.0.3"), content="false")
  inspect(check("1.3.0", "~1.2.3"), content="false")
  inspect(check("1.2.9", "~1.2"), content="true")
  inspect(check("2.0.0", "~1"), content="false")
}

///|
test "comparison operators and conjunction" {
  inspect(check("1.5.0", ">=1.2.3 <2.0.0"), content="true")
  inspect(check("2.0.0", ">=1.2.3 <2.0.0"), content="false")
  inspect(check("1.2.3", ">=1.2.3 <2.0.0"), content="true")
  inspect(check("1.2.2", ">1.2.2"), content="false")
  inspect(check("1.0.0", "=1.0.0"), content="true")
  inspect(check("1.0.1", "1.0.0"), content="false")
}

///|
test "wildcards and disjunction" {
  inspect(check("1.9.9", "1.x"), content="true")
  inspect(check("2.0.0", "1.x"), content="false")
  inspect(check("1.2.9", "1.2.x"), content="true")
  inspect(check("1.3.0", "1.2.x"), content="false")
  inspect(check("3.0.0", "*"), content="true")
  inspect(check("1.0.0", "^1.0.0 || ^3.0.0"), content="true")
  inspect(check("3.2.0", "^1.0.0 || ^3.0.0"), content="true")
  inspect(check("2.0.0", "^1.0.0 || ^3.0.0"), content="false")
}

///|
test "prerelease opt-in" {
  inspect(check("1.0.0-alpha.1", "^1.0.0"), content="false")
  inspect(check("1.0.0-alpha.1", "^1.0.0-alpha.1"), content="true")
  inspect(check("1.0.0-beta.1", "^1.0.0-alpha.1"), content="true")
  inspect(check("1.1.0-alpha.1", "^1.0.0-alpha.1"), content="false")
}

///|
test "hyphen ranges (node-semver inclusive set)" {
  // Full versions: both ends inclusive.
  inspect(check("1.2.3", "1.2.3 - 2.3.4"), content="true")
  inspect(check("2.3.4", "1.2.3 - 2.3.4"), content="true")
  inspect(check("1.2.2", "1.2.3 - 2.3.4"), content="false")
  inspect(check("2.3.5", "1.2.3 - 2.3.4"), content="false")
  // Partial left: missing components are padded with zeroes.
  inspect(check("1.2.0", "1.2 - 2.3.4"), content="true")
  inspect(check("1.1.9", "1.2 - 2.3.4"), content="false")
  // Partial right: expands to the next tuple, excluding all of its prereleases.
  inspect(check("2.3.9", "1.2.3 - 2.3"), content="true")
  inspect(check("2.4.0", "1.2.3 - 2.3"), content="false")
  inspect(check("2.4.0-alpha", "1.2.3 - 2.3"), content="false")
  inspect(check("2.9.9", "1.2.3 - 2"), content="true")
  inspect(check("3.0.0", "1.2.3 - 2"), content="false")
  // Prerelease endpoints opt in to their own tuple only.
  inspect(check("2.3.4-beta.2", "1.2.3 - 2.3.4-beta.2"), content="true")
  inspect(check("2.3.4-beta.3", "1.2.3 - 2.3.4-beta.2"), content="false")
  inspect(check("2.3.4", "1.2.3 - 2.3.4-beta.2"), content="false")
  inspect(check("1.0.0-alpha", "1.0.0-alpha - 2.0.0"), content="true")
  inspect(check("0.9.9", "1.0.0-alpha - 2.0.0"), content="false")
  // Wildcard sides are unbounded.
  inspect(check("9.9.9", "1.2.3 - *"), content="true")
  inspect(check("0.0.1", "* - 2.3.4"), content="true")
}

///|
test "invalid ranges" {
  inspect(result_is_ok(parse_range("^")), content="false")
  inspect(result_is_ok(parse_range("1.2.3 || ")), content="false")
  inspect(result_is_ok(parse_range("~x.y")), content="false")
  inspect(result_is_ok(parse_range("1.2.3 -")), content="false")
  inspect(result_is_ok(parse_range("- 2.3.4")), content="false")
  inspect(result_is_ok(parse_range("1 - 2 - 3")), content="false")
  inspect(result_is_ok(parse_range("1.2.3 - x.y")), content="false")
}

///|
/// Regression: node-semver treats an empty (or whitespace-only) range as the
/// X-range `*`. The old parser reported "empty range" instead.
test "empty range means universal set" {
  inspect(check("0.0.0", ""), content="true")
  inspect(check("1.0.0", ""), content="true")
  inspect(check("9.9.9", "   "), content="true")
  // Prereleases are still excluded without an explicit opt-in.
  inspect(check("1.0.0-alpha", ""), content="false")
}

///|
/// Regression: node-semver treats any whitespace as a separator and allows
/// an operator to be separated from its version. Tabs and a spaced `>=`
/// used to be rejected or mis-parsed.
test "whitespace between comparators and operands is accepted" {
  inspect(check("1.9.0", ">= 1.2.3"), content="true")
  inspect(check("1.0.0", ">= 1.2.3"), content="false")
  inspect(check("2.0.0", "> 1"), content="true")
  inspect(check("1.9.9", "> 1"), content="false")
  inspect(check("1.5.0", "  ^1.2.3  "), content="true")
  inspect(check("2.3.4", "1.2.3\t-\t2.3.4"), content="true")
  inspect(check("2.3.5", "1.2.3\t-\t2.3.4"), content="false")
}

///|
/// Regression: prerelease opt-in is scoped to one `||` branch. A prerelease
/// mentioned in one branch must not authorise the same core tuple inside a
/// different branch that has no opt-in of its own (`^1.0.0 || =1.5.0-beta`
/// must reject `1.5.0-rc`, matching node-semver).
test "prerelease opt-in does not leak across OR branches" {
  inspect(check("1.5.0-rc", "^1.0.0 || =1.5.0-beta"), content="false")
  inspect(check("1.5.0-rc", "=1.5.0-beta || ^1.0.0"), content="false")
  // A branch that itself opts in still admits its own prereleases.
  inspect(check("1.5.0-rc", "^1.0.0 || ^1.5.0-beta"), content="true")
  inspect(check("1.0.0-alpha", "^2.0.0 || =1.0.0-alpha"), content="true")
  // Opt-in extraction reuses the same whitespace normalisation as parsing.
  inspect(check("1.0.0-alpha", ">=\t1.0.0-alpha"), content="true")
  inspect(check("2.3.4-beta", "1.2.3\t-\t2.3.4-beta"), content="true")
}

///|
/// Regression: node-semver collapses any OR branch that desugars to the
/// universal set (`*`, `>=0.0.0`, `>=0`, `>=*`, `<=*`, empty) into a single
/// ANY comparator for the WHOLE range (`U || X = U`). Consequently a
/// prerelease is rejected even when a sibling branch opts in to its tuple.
test "universal OR branch collapses the range for prereleases" {
  inspect(check("1.5.0-beta", "* || ^1.5.0-beta"), content="false")
  inspect(check("1.5.0-beta", ">=0.0.0 || ^1.5.0-beta"), content="false")
  inspect(check("1.5.0-beta", "^1.5.0-beta || >=0"), content="false")
  inspect(check("1.5.0-beta", ">=* || ^1.5.0-beta"), content="false")
  // A non-universal sibling does not suppress the opt-in.
  inspect(check("1.5.0-beta", ">0.0.0 || ^1.5.0-beta"), content="true")
  inspect(check("1.5.0-beta", "0.x || ^1.5.0-beta"), content="true")
  // Release versions are unaffected: universal really is universal.
  inspect(check("1.9.0", "* || ^1.5.0-beta"), content="true")
}

///|
/// Regression: node-semver decides caret bounds from the *written* precision,
/// not from the zero-padded tuple. `^0`, `^0.x`, `^0.0` and `^0.0.0` all parse
/// to 0.0.0 but desugar to <1.0.0-0, <1.0.0-0, <0.1.0-0 and <0.0.1-0.
/// The old implementation used only the parsed value and gave every one of
/// them <0.0.1-0, so `^0` wrongly rejected every 0.x release above 0.0.0.
test "caret bounds respect written precision for zero-major ranges" {
  inspect(check("0.9.9", "^0"), content="true")
  inspect(check("1.0.0", "^0"), content="false")
  inspect(check("0.0.1", "^0"), content="true")
  inspect(check("0.9.9", "^0.x"), content="true")
  inspect(check("1.0.0", "^0.x"), content="false")
  inspect(check("0.0.9", "^0.0"), content="true")
  inspect(check("0.1.0", "^0.0"), content="false")
  inspect(check("0.0.9", "^0.0.x"), content="true")
  inspect(check("0.1.0", "^0.0.x"), content="false")
  inspect(check("0.0.0", "^0.0.0"), content="true")
  inspect(check("0.0.1", "^0.0.0"), content="false")
  inspect(check("0.2.9", "^0.2"), content="true")
  inspect(check("0.3.0", "^0.2"), content="false")
  // Tilde follows the same written-minor rule: ~0.x == ~0 == <1.0.0-0.
  inspect(check("0.9.9", "~0.x"), content="true")
  inspect(check("1.0.0", "~0.x"), content="false")
  inspect(check("0.0.9", "~0.0"), content="true")
  inspect(check("0.1.0", "~0.0"), content="false")
}

///|
/// Regression: a comparator with a partial operand (`>1`, `<=1.2`, `=1.2`)
/// is a valid node-semver range. The old parser rejected every such form
/// because it only accepted a full three-component version after an operator.
test "partial versions are valid comparator operands" {
  inspect(check("2.0.0", ">1"), content="true")
  inspect(check("1.9.9", ">1"), content="false")
  inspect(check("1.3.0", ">1.2"), content="true")
  inspect(check("1.2.9", ">1.2"), content="false")
  inspect(check("1.2.0", ">=1.2"), content="true")
  inspect(check("1.1.9", ">=1.2"), content="false")
  inspect(check("0.9.9", "<1"), content="true")
  inspect(check("1.0.0", "<1"), content="false")
  inspect(check("1.0.0-alpha", "<1"), content="false")
  inspect(check("1.9.9", "<=1"), content="true")
  inspect(check("2.0.0", "<=1"), content="false")
  inspect(check("2.0.0-alpha", "<=1"), content="false")
  inspect(check("1.2.9", "<=1.2"), content="true")
  inspect(check("1.3.0", "<=1.2"), content="false")
  inspect(check("1.3.0-alpha", "<=1.2"), content="false")
  inspect(check("1.9.9", "=1"), content="true")
  inspect(check("2.0.0", "=1"), content="false")
  inspect(check("1.2.9", "=1.2"), content="true")
  inspect(check("1.3.0", "=1.2"), content="false")
  // Wildcards are accepted after an operator and mean the universal set.
  inspect(check("9.9.9", "^*"), content="true")
  inspect(check("9.9.9", "~*"), content="true")
  inspect(check("9.9.9", ">=x"), content="true")
}

///|
/// Regression: caret/tilde/partial upper bounds used `component + 1`, which
/// silently overflowed to a negative value at the Int64 limit and turned a
/// valid range into an empty interval (even the exact version failed to
/// match). The upper bound must saturate to "unbounded" instead.
test "comparator upper bounds do not overflow at Int64 limit" {
  // Caret at the largest major: exact version must still satisfy its own range.
  inspect(
    check("9223372036854775807.0.0", "^9223372036854775807.0.0"),
    content="true",
  )
  // No overflowed negative upper bound: a smaller version must not match.
  inspect(check("1.0.0", "^9223372036854775807.0.0"), content="false")
  // Exact major comparison remains coherent at the limit.
  inspect(
    check("9223372036854775807.0.0", ">=9223372036854775807.0.0"),
    content="true",
  )
  // Tilde and partial wildcard ranges follow the same saturation rule.
  inspect(
    check("9223372036854775807.0.0", "~9223372036854775807.0"),
    content="true",
  )
  inspect(
    check("9223372036854775807.0.0", "9223372036854775807.x"),
    content="true",
  )
}
