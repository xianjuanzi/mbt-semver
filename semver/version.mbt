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
  major : Int32
  minor : Int32
  patch : Int32
  prerelease : Array[String]
  build : String?
}

///|
/// Create a normal (non-prerelease) version.
pub fn Version::new(major : Int32, minor : Int32, patch : Int32) -> Version {
  { major, minor, patch, prerelease: [], build: None, }
}

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
/// Parse a numeric identifier: ASCII digits only, no leading zero.
fn parse_number(view : StringView) -> Result[Int32, String] {
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
      let mut value = 0
      for i = 0; i < view.length(); i = i + 1 {
        match view.get_char(i) {
          None => return Err("missing digit")
          Some(ch) => {
            if !ch.is_ascii_digit() {
              return Err("numeric identifier contains a non-digit")
            }
            value = value * 10 + (ch.to_int() - '0'.to_int())
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
      match parse_number(id) {
        Err(e) => return Err(e)
        Ok(_) => ()
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
  let minus = patch_view.find("-")
  let plus = patch_view.find("+")

  let mut core_end = patch_view.length()
  let mut pre_start = -1
  let mut build_start = -1
  match minus {
    Some(idx) => {
      pre_start = idx + 1
      core_end = idx
    }
    None => ()
  }
  match plus {
    Some(idx) => {
      if pre_start >= 0 && idx < pre_start {
        return Err("build metadata must follow prerelease")
      }
      build_start = idx + 1
      if pre_start < 0 {
        core_end = idx
      }
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
    match (parse_number(a), parse_number(b)) {
      (Ok(x), Ok(y)) => cmp_int(x, y)
      _ => 0
    }
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
  let c = cmp_int(a.major, b.major)
  if c != 0 {
    return c
  }
  let c = cmp_int(a.minor, b.minor)
  if c != 0 {
    return c
  }
  let c = cmp_int(a.patch, b.patch)
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
