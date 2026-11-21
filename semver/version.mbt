// Copyright 2026 MoonBit Hackathon contributor
// Licensed under the Apache License, Version 2.0.

///|
/// A Semantic Versioning 2.0.0 version value.
///
/// `major.minor.patch` are non-negative integers without leading zeroes.
/// `prerelease` is an array of dot-separated identifiers; `build` is the raw
/// build metadata suffix (without the leading `+`). Build metadata is ignored
/// by version precedence, as required by SemVer 2.0.0 section 10.
pub struct Version {
  major : Int64
  minor : Int64
  patch : Int64
  prerelease : Array[String]
  build : String?
}

///|
/// Create a normal (non-prerelease) version.
pub fn Version::new(major : Int64, minor : Int64, patch : Int64) -> Version {
  { major, minor, patch, prerelease: [], build: None, }
}

///|
/// Largest core-component value representable by Int64. SemVer places no
/// numeric bound on core components, so values beyond this are rejected with
/// a clear error rather than silently wrapping to a negative number.
const MAX_CORE : Int64 = 9223372036854775807L

///|
fn cmp_int(a : Int32, b : Int32) -> Int32 {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///|
fn cmp_i64(a : Int64, b : Int64) -> Int32 {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///|
/// Parse a numeric identifier: ASCII digits only, no leading zero. Uses Int64
/// and checks every step for overflow so a very large component is rejected
/// instead of wrapping to a negative value (which would break precedence).
fn parse_number(view : StringView) -> Result[Int64, String] {
  if view.length() == 0 {
    return Err("empty numeric identifier")
  }
  match view.get_char(0) {
    None => Err("empty numeric identifier")
    Some(first) => {
      if !first.is_ascii_digit() {
        return Err("numeric identifier contains a non-digit")
      }
      if first == '0' && view.length() > 1 {
        return Err("numeric identifier has a leading zero")
      }
      let mut value : Int64 = 0L
      for i = 0; i < view.length(); i = i + 1 {
        match view.get_char(i) {
          None => return Err("missing digit")
          Some(ch) => {
            if !ch.is_ascii_digit() {
              return Err("numeric identifier contains a non-digit")
            }
            let digit : Int64 = (ch.to_int() - '0'.to_int()).to_int64()
            // value * 10 + digit <= MAX_CORE  <=>  value <= (MAX_CORE - digit) / 10
            if value > (MAX_CORE - digit) / 10L {
              return Err("numeric identifier exceeds the supported range")
            }
            value = value * 10L + digit
          }
        }
      }
      Ok(value)
    }
  }
}

///|
fn is_numeric_identifier(view : StringView) -> Bool {
  if view.length() == 0 {
    return false
  }
  for i = 0; i < view.length(); i = i + 1 {
    match view.get_char(i) {
      None => return false
      Some(ch) => if !ch.is_ascii_digit() { return false }
    }
  }
  true
}

///|
fn valid_identifier(view : StringView) -> Bool {
  if view.length() == 0 {
    return false
  }
  for i = 0; i < view.length(); i = i + 1 {
    match view.get_char(i) {
      None => return false
      Some(ch) =>
        if !(ch.is_ascii_digit() || ch.is_ascii_alphabetic() || ch == '-') {
          return false
        }
    }
  }
  true
}

///|
fn parse_ids(
  text : StringView,
  numeric_rules~ : Bool,
) -> Result[Array[String], String] {
  let ids = text.split(".").collect()
  let result : Array[String] = []
  for id in ids {
    if !valid_identifier(id) {
      return Err("invalid identifier: \{id}")
    }
    if numeric_rules && is_numeric_identifier(id) {
      // SemVer numeric identifiers must not have leading zeroes. Check the
      // syntax directly instead of parsing to Int64: prerelease identifiers
      // may be arbitrarily long and must not be capped by the core-version
      // integer range.
      if id.length() > 1 {
        match id.get_char(0) {
          Some(first) =>
            if first == '0' {
              return Err("numeric identifier has a leading zero")
            }
          None => ()
        }
      }
    }
    result.push(id.to_owned())
  }
  Ok(result)
}

///|
/// Parse a SemVer 2.0.0 version string. Returns a description of the first
/// syntax error instead of raising an exception.
pub fn parse_version(input : String) -> Result[Version, String] {
  let (major_view, rest) = match input.split_once(".") {
    Some(pair) => pair
    None =>
      return Err(
        "a version must have exactly three dot-separated core components",
      )
  }
  let (minor_view, patch_view) = match rest.split_once(".") {
    Some(pair) => pair
    None =>
      return Err(
        "a version must have exactly three dot-separated core components",
      )
  }
  let major = match parse_number(major_view) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let minor = match parse_number(minor_view) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  // `+` is the single build separator. Search for the prerelease `-` only in
  // the part BEFORE `+`: a build suffix may legally contain `-` (e.g. the
  // valid version `1.2.3+build-1`). Searching `-` across the whole patch view
  // would wrongly treat that build hyphen as a prerelease separator.
  let plus = patch_view.find("+")
  let build_start = match plus {
    Some(idx) => idx + 1
    None => -1
  }

  // `pre_region` is the core + prerelease portion, excluding build metadata.
  let pre_region_end = match plus {
    Some(idx) => idx
    None => patch_view.length()
  }
  let pre_region = patch_view[:pre_region_end]
  let minus = pre_region.find("-")

  let mut core_end = pre_region_end
  let mut pre_start = -1
  match minus {
    Some(idx) => {
      pre_start = idx + 1
      core_end = idx
    }
    None => ()
  }

  let patch = match parse_number(patch_view[:core_end]) {
    Ok(v) => v
    Err(e) => return Err(e)
  }

  let mut prerelease : Array[String] = []
  if pre_start >= 0 {
    let pre_end = if build_start >= 0 {
      build_start - 1
    } else {
      patch_view.length()
    }
    if pre_start == pre_end {
      return Err("empty prerelease identifier")
    }
    match parse_ids(patch_view[pre_start:pre_end], numeric_rules=true) {
      Ok(ids) => prerelease = ids
      Err(e) => return Err(e)
    }
  }

  let mut build : String? = None
  if build_start >= 0 {
    if build_start == patch_view.length() {
      return Err("empty build metadata")
    }
    let raw = patch_view[build_start:]
    match parse_ids(raw, numeric_rules=false) {
      Ok(_) => build = Some(raw.to_owned())
      Err(e) => return Err(e)
    }
  }

  Ok({ major, minor, patch, prerelease, build, })
}

///|
fn compare_identifier(a : StringView, b : StringView) -> Int32 {
  let a_num = is_numeric_identifier(a)
  let b_num = is_numeric_identifier(b)
  if a_num && b_num {
    // Numeric identifiers compare by numeric value. For canonical decimal
    // strings without leading zeroes this equals: shorter string is smaller;
    // equal length compares lexicographically. This avoids any integer width
    // limit and supports arbitrarily long prerelease numbers.
    if a.length() != b.length() {
      return cmp_int(a.length(), b.length())
    }
    let limit = a.length()
    for i = 0; i < limit; i = i + 1 {
      match (a.get_char(i), b.get_char(i)) {
        (Some(x), Some(y)) => {
          let c = cmp_int(x.to_int(), y.to_int())
          if c != 0 {
            return c
          }
        }
        _ => return 0
      }
    }
    0
  } else if a_num {
    -1
  } else if b_num {
    1
  } else {
    let limit = if a.length() < b.length() { a.length() } else { b.length() }
    for i = 0; i < limit; i = i + 1 {
      match (a.get_char(i), b.get_char(i)) {
        (Some(x), Some(y)) => {
          let c = cmp_int(x.to_int(), y.to_int())
          if c != 0 {
            return c
          }
        }
        _ => return 0
      }
    }
    cmp_int(a.length(), b.length())
  }
}

///|
/// Compare two versions by SemVer precedence. Returns -1, 0 or 1.
/// Build metadata is deliberately ignored.
pub fn compare_version(a : Version, b : Version) -> Int32 {
  let c = cmp_i64(a.major, b.major)
  if c != 0 {
    return c
  }
  let c = cmp_i64(a.minor, b.minor)
  if c != 0 {
    return c
  }
  let c = cmp_i64(a.patch, b.patch)
  if c != 0 {
    return c
  }
  let a_pre = a.prerelease
  let b_pre = b.prerelease
  if a_pre.length() == 0 && b_pre.length() > 0 {
    return 1
  }
  if a_pre.length() > 0 && b_pre.length() == 0 {
    return -1
  }
  let limit = if a_pre.length() < b_pre.length() {
    a_pre.length()
  } else {
    b_pre.length()
  }
  for i = 0; i < limit; i = i + 1 {
    let c = compare_identifier(a_pre[i][:], b_pre[i][:])
    if c != 0 {
      return c
    }
  }
  cmp_int(a_pre.length(), b_pre.length())
}

///|
pub impl Eq for Version with fn equal(a : Version, b : Version) -> Bool {
  compare_version(a, b) == 0
}

///|
pub impl Compare for Version with fn compare(a : Version, b : Version) -> Int32 {
  compare_version(a, b)
}

///|
/// Render a version back to its canonical string form.
pub fn Version::to_string(self : Version) -> String {
  let mut out = "\{self.major}.\{self.minor}.\{self.patch}"
  if self.prerelease.length() > 0 {
    out = out + "-" + self.prerelease.join(".")
  }
  match self.build {
    Some(b) => out + "+" + b
    None => out
  }
}

///|
fn[T, E] is_ok(result : Result[T, E]) -> Bool {
  match result {
    Ok(_) => true
    Err(_) => false
  }
}

///|
fn version_of(text : String) -> Version raise {
  match parse_version(text) {
    Ok(v) => v
    Err(e) => fail("invalid test fixture \{text}: \{e}")
  }
}

///|
test "parse core versions" {
  inspect(is_ok(parse_version("0.0.0")), content="true")
  inspect(is_ok(parse_version("10.20.30")), content="true")
  inspect(is_ok(parse_version("1.0.0-alpha.1+build.5")), content="true")
  inspect(
    match version_of("1.2.3+exp.sha.5114f85").build {
      Some(_) => true
      None => false
    },
    content="true",
  )
}

///|
test "reject invalid syntax" {
  inspect(is_ok(parse_version("1.2")), content="false")
  inspect(is_ok(parse_version("1.2.3.4")), content="false")
  inspect(is_ok(parse_version("01.2.3")), content="false")
  inspect(is_ok(parse_version("1.02.3")), content="false")
  inspect(is_ok(parse_version("1.2.03")), content="false")
  inspect(is_ok(parse_version("1.2.-3")), content="false")
  inspect(is_ok(parse_version("1.2.3-")), content="false")
  inspect(is_ok(parse_version("1.2.3+")), content="false")
  inspect(is_ok(parse_version("1.2.3-01")), content="false")
  inspect(is_ok(parse_version("1.2.3-alpha..1")), content="false")
  inspect(is_ok(parse_version("v1.2.3")), content="false")
  inspect(is_ok(parse_version("1.2.x")), content="false")
}

///|
test "precedence follows semver specification" {
  inspect(
    compare_version(version_of("1.0.0"), version_of("1.0.1")) < 0,
    content="true",
  )
  inspect(
    compare_version(version_of("1.0.0"), version_of("2.0.0")) < 0,
    content="true",
  )
  inspect(
    compare_version(version_of("1.0.0-alpha"), version_of("1.0.0")) < 0,
    content="true",
  )
  inspect(
    compare_version(version_of("1.0.0-alpha.1"), version_of("1.0.0-alpha.beta")) <
    0,
    content="true",
  )
  inspect(
    compare_version(version_of("1.0.0-alpha.beta"), version_of("1.0.0-beta")) <
    0,
    content="true",
  )
  inspect(
    compare_version(version_of("1.0.0-beta.2"), version_of("1.0.0-beta.11")) < 0,
    content="true",
  )
  inspect(
    compare_version(version_of("1.0.0-beta.11"), version_of("1.0.0-rc.1")) < 0,
    content="true",
  )
  inspect(
    compare_version(version_of("1.0.0+build.1"), version_of("1.0.0+build.2")) ==
    0,
    content="true",
  )
}

///|
test "round trip" {
  inspect(
    version_of("1.2.3-alpha.1+sha.abc").to_string(),
    content="1.2.3-alpha.1+sha.abc",
  )
}

///|
/// Regression: a build suffix may legally contain `-`. A global search for
/// `-` used to mistake that hyphen for a prerelease separator and reject the
/// version with "build metadata must follow prerelease".
test "build metadata may contain hyphens" {
  inspect(is_ok(parse_version("1.2.3+build-1")), content="true")
  inspect(is_ok(parse_version("1.2.3+build.5-1")), content="true")
  inspect(is_ok(parse_version("1.2.3-alpha+build-1")), content="true")
  inspect(version_of("1.2.3+build-1").to_string(), content="1.2.3+build-1")
  // Build metadata never affects precedence.
  inspect(
    compare_version(version_of("1.0.0+build-1"), version_of("1.0.0+build-2")) ==
    0,
    content="true",
  )
}

///|
/// Regression: core components were Int32 without overflow checks, so
/// 2147483648 silently wrapped to -2147483648 and broke precedence.
test "large core components do not overflow" {
  inspect(is_ok(parse_version("2147483648.0.0")), content="true")
  inspect(version_of("2147483648.0.0").to_string(), content="2147483648.0.0")
  inspect(
    compare_version(version_of("2147483648.0.0"), version_of("5.0.0")) > 0,
    content="true",
  )
  inspect(is_ok(parse_version("9223372036854775807.0.0")), content="true")
  // Beyond the supported 64-bit range: reject clearly, never wrap negative.
  inspect(is_ok(parse_version("9223372036854775808.0.0")), content="false")
  inspect(is_ok(parse_version("99999999999999999999999.0.0")), content="false")
}

///|
/// Regression: numeric prerelease identifiers compare by numeric value even
/// when they exceed 32 bits (SemVer spec item 11).
test "large numeric prerelease identifiers compare numerically" {
  inspect(
    compare_version(version_of("1.0.0-2147483648"), version_of("1.0.0-9")) > 0,
    content="true",
  )
  inspect(
    compare_version(
      version_of("1.0.0-4294967296"),
      version_of("1.0.0-4294967295"),
    ) >
    0,
    content="true",
  )
  // SemVer sets no width limit on prerelease numeric identifiers: arbitrarily
  // long identifiers parse and compare by value (length, then lexical order).
  inspect(
    is_ok(parse_version("1.0.0-999999999999999999999999999999999")),
    content="true",
  )
  inspect(
    compare_version(
      version_of("1.0.0-999999999999999999999999999999999"),
      version_of("1.0.0-999999999999999999999999999999998"),
    ) >
    0,
    content="true",
  )
  // Leading zeroes stay forbidden even for a very long identifier.
  inspect(
    is_ok(parse_version("1.0.0-09999999999999999999999999999999")),
    content="false",
  )
}
