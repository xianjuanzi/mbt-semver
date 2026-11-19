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
/// A disjunctive set of ranges (joined with `||`), plus the set of core
/// versions that explicitly mention a prerelease. The latter implements the
/// usual package-manager rule: a prerelease only matches a range when the
/// range opts in to the same `major.minor.patch` line.
pub struct RangeSet {
  ranges : Array[Range]
  prerelease_keys : Array[String]
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
  let numbers : Array[Int32] = []
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
fn upper_for_caret(v : Version) -> Version {
  if v.major > 0 {
    Version::new(v.major + 1, 0, 0)
  } else if v.minor > 0 {
    Version::new(0, v.minor + 1, 0)
  } else {
    Version::new(0, 0, v.patch + 1)
  }
}

///|
fn upper_for_tilde(v : Version, had_minor : Bool) -> Version {
  if had_minor {
    Version::new(v.major, v.minor + 1, 0)
  } else {
    Version::new(v.major + 1, 0, 0)
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
      upper_for_caret(v)
    } else {
      let had_minor = rest.split(".").collect().length() > 1
      upper_for_tilde(v, had_minor)
    }
    return Ok({
      lower: Some({ version: v, inclusive: true, }),
      upper: Some({ version: upper, inclusive: false, }),
    })
  }

  let v = match parse_owned(rest) {
    Ok(v) => v
    Err(_) => {
      if op != "" {
        return Err("invalid version in comparator: \{token}")
      }
      let p = match parse_partial(rest) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let pieces = rest.split(".").collect()
      let mut numeric = 0
      for piece in pieces {
        let q = piece.trim()
        if q == "x" || q == "X" || q == "*" {
          break
        }
        numeric = numeric + 1
      }
      let upper = if numeric >= 2 {
        Version::new(p.major, p.minor + 1, 0)
      } else {
        Version::new(p.major + 1, 0, 0)
      }
      return Ok({
        lower: Some({ version: p, inclusive: true, }),
        upper: Some({ version: upper, inclusive: false, }),
      })
    }
  }
  if op == ">" {
    Ok({ lower: None, upper: Some({ version: v, inclusive: false, }), })
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
fn parse_range_part(part : StringView) -> Result[Range, String] {
  let tokens = part.trim().split(" ").collect()
  let mut result = empty_range()
  let mut count = 0
  for token in tokens {
    let t = token.trim()
    if t.length() == 0 {
      continue
    }
    let one = match parse_comparator(t) {
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
/// `1.2`, `1.2.x`), caret, tilde, comparison operators, whitespace for AND
/// and `||` for OR.
pub fn parse_range(input : String) -> Result[RangeSet, String] {
  let ranges : Array[Range] = []
  let keys : Array[String] = []
  for part in input.split("||").collect() {
    match parse_range_part(part) {
      Ok(r) => ranges.push(r)
      Err(e) => return Err(e)
    }
  }
  for part in input.split("||").collect() {
    for token in part.trim().split(" ").collect() {
      let t = token.trim()
      let stripped = if t.has_prefix(">=") || t.has_prefix("<=") {
        t[2:]
      } else if t.has_prefix("^") ||
        t.has_prefix("~") ||
        t.has_prefix(">") ||
        t.has_prefix("<") ||
        t.has_prefix("=") {
        t[1:]
      } else {
        t
      }
      match parse_version(stripped.to_owned()) {
        Ok(v) => if v.prerelease.length() > 0 { keys.push(key_of(v)) }
        Err(_) => ()
      }
    }
  }
  Ok({ ranges, prerelease_keys: keys, })
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
  if version.prerelease.length() > 0 {
    let k = key_of(version)
    let mut allowed = false
    for key in set.prerelease_keys {
      if key == k {
        allowed = true
      }
    }
    if !allowed {
      return false
    }
  }
  for range in set.ranges {
    if in_range(range, version) {
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
test "invalid ranges" {
  inspect(result_is_ok(parse_range("^")), content="false")
  inspect(result_is_ok(parse_range("1.2.3 || ")), content="false")
  inspect(result_is_ok(parse_range("~x.y")), content="false")
}
