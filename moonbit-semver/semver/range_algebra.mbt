// Copyright 2026 MoonBit Hackathon contributor
// Licensed under the Apache License, Version 2.0.

///|
/// A single interval over the totally ordered SemVer version space.
///
/// A missing lower bound means `-infinity`; a missing upper bound means
/// `+infinity`. `lo_inclusive` / `hi_inclusive` say whether the endpoint
/// itself belongs to the interval. Several intervals joined by `||` form a
/// *normalised interval set*: sorted, pairwise disjoint and merged whenever
/// they overlap. That representation is what makes set algebra possible.
pub struct Interval {
  lo : Version?
  hi : Version?
  lo_inclusive : Bool
  hi_inclusive : Bool
  /// `None` means "no prerelease policy" (a pure interval, as used by the
  /// algebra-law tests). `Some(keys)` is the package-manager rule: a
  /// prerelease version only belongs to this interval when its
  /// `major.minor.patch` tuple appears in `keys`. Parsed ranges carry
  /// `Some(keys)` so `parse_algebra(...)` agrees with `satisfies(...)`.
  prerelease_keys : Array[String]?
}

///|
/// Construct a pure interval with no prerelease policy. The caller is
/// responsible for passing valid bounds; use `normalise` to repair ordering.
pub fn Interval::new(
  lo : Version?,
  lo_inclusive : Bool,
  hi : Version?,
  hi_inclusive : Bool,
) -> Interval {
  { lo, hi, lo_inclusive, hi_inclusive, prerelease_keys: None, }
}

///|
/// The empty interval set (matches no version).
pub fn empty_set() -> Array[Interval] {
  []
}

///|
/// The universal interval set (matches every version).
pub fn universal_set() -> Array[Interval] {
  [Interval::new(None, true, None, true)]
}

///|
fn ver_cmp(a : Version, b : Version) -> Int32 {
  compare_version(a, b)
}

///|
/// lower bound, smaller wins; equal bounds OR their inclusiveness
fn lo_min(a : Interval, b : Interval) -> (Version?, Bool) {
  match (a.lo, b.lo) {
    // A missing lower bound is -infinity, which is always the minimum.
    (None, None) => (None, true)
    (None, Some(_)) => (None, true)
    (Some(_), None) => (None, true)
    (Some(x), Some(y)) => {
      let c = ver_cmp(x, y)
      if c < 0 {
        (Some(x), a.lo_inclusive)
      } else if c > 0 {
        (Some(y), b.lo_inclusive)
      } else {
        (Some(x), a.lo_inclusive || b.lo_inclusive)
      }
    }
  }
}

///|
/// lower bound, larger wins; equal bounds AND their inclusiveness
fn lo_max(a : Interval, b : Interval) -> (Version?, Bool) {
  match (a.lo, b.lo) {
    (None, None) => (None, true)
    (None, Some(v)) => (Some(v), b.lo_inclusive)
    (Some(v), None) => (Some(v), a.lo_inclusive)
    (Some(x), Some(y)) => {
      let c = ver_cmp(x, y)
      if c > 0 {
        (Some(x), a.lo_inclusive)
      } else if c < 0 {
        (Some(y), b.lo_inclusive)
      } else {
        (Some(x), a.lo_inclusive && b.lo_inclusive)
      }
    }
  }
}

///|
/// upper bound, larger wins; equal bounds OR their inclusiveness
fn hi_max(a : Interval, b : Interval) -> (Version?, Bool) {
  match (a.hi, b.hi) {
    // A missing upper bound is +infinity, which is always the maximum.
    (None, None) => (None, true)
    (None, Some(_)) => (None, true)
    (Some(_), None) => (None, true)
    (Some(x), Some(y)) => {
      let c = ver_cmp(x, y)
      if c > 0 {
        (Some(x), a.hi_inclusive)
      } else if c < 0 {
        (Some(y), b.hi_inclusive)
      } else {
        (Some(x), a.hi_inclusive || b.hi_inclusive)
      }
    }
  }
}

///|
/// upper bound, smaller wins; equal bounds AND their inclusiveness
fn hi_min(a : Interval, b : Interval) -> (Version?, Bool) {
  match (a.hi, b.hi) {
    (None, None) => (None, true)
    (None, Some(v)) => (Some(v), b.hi_inclusive)
    (Some(v), None) => (Some(v), a.hi_inclusive)
    (Some(x), Some(y)) => {
      let c = ver_cmp(x, y)
      if c < 0 {
        (Some(x), a.hi_inclusive)
      } else if c > 0 {
        (Some(y), b.hi_inclusive)
      } else {
        (Some(x), a.hi_inclusive && b.hi_inclusive)
      }
    }
  }
}

///|
fn make_interval(
  lo : Version?,
  lo_inclusive : Bool,
  hi : Version?,
  hi_inclusive : Bool,
) -> Interval {
  Interval::new(lo, lo_inclusive, hi, hi_inclusive)
}

///|
fn make_interval_with_keys(
  lo : Version?,
  lo_inclusive : Bool,
  hi : Version?,
  hi_inclusive : Bool,
  prerelease_keys : Array[String]?,
) -> Interval {
  { lo, hi, lo_inclusive, hi_inclusive, prerelease_keys, }
}

///|
fn core_key(v : Version) -> String {
  "\{v.major}.\{v.minor}.\{v.patch}"
}

///|
/// node-semver's prerelease opt-in rule, applied to the interval's policy.
fn keys_allow(keys : Array[String]?, v : Version) -> Bool {
  match keys {
    None => true
    Some(allowed) => {
      if v.prerelease.length() == 0 {
        return true
      }
      let k = core_key(v)
      for a in allowed {
        if a == k {
          return true
        }
      }
      false
    }
  }
}

///|
/// Intersection of two prerelease policies: the stricter (smaller) set wins.
fn meet_keys(a : Array[String]?, b : Array[String]?) -> Array[String]? {
  match (a, b) {
    (None, other) => other
    (other, None) => other
    (Some(xs), Some(ys)) => {
      let out : Array[String] = []
      for x in xs {
        for y in ys {
          if x == y {
            out.push(x)
          }
        }
      }
      Some(out)
    }
  }
}

///|
fn keys_equal(a : Array[String]?, b : Array[String]?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(xs), Some(ys)) => {
      if xs.length() != ys.length() {
        return false
      }
      for x in xs {
        let mut found = false
        for y in ys {
          if x == y {
            found = true
          }
        }
        if !found {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// Whether an interval contains no version at all.
pub fn interval_is_empty(iv : Interval) -> Bool {
  match (iv.lo, iv.hi) {
    (None, None) => false
    (None, Some(_)) => false
    (Some(_), None) => false
    (Some(lo), Some(hi)) => {
      let c = ver_cmp(lo, hi)
      c > 0 || (c == 0 && !(iv.lo_inclusive && iv.hi_inclusive))
    }
  }
}

///|
/// Whether two intervals share at least one version.
pub fn intervals_overlap(a : Interval, b : Interval) -> Bool {
  let (lo, lo_inc) = lo_max(a, b)
  let (hi, hi_inc) = hi_min(a, b)
  match (lo, hi) {
    (None, None) => true
    (None, Some(_)) => true
    (Some(_), None) => true
    (Some(l), Some(h)) => {
      let c = ver_cmp(l, h)
      c < 0 || (c == 0 && lo_inc && hi_inc)
    }
  }
}

///| Whether two intervals can be merged into a single interval. This is true

///| both for genuine overlap and for intervals that merely touch with no gap

///| between them: `<1.0.0` and `>=1.0.0` must merge into `*`, while `<1.0.0`

///|
/// and `>1.0.0` must not (the single version 1.0.0 is missing).
fn intervals_mergeable(a : Interval, b : Interval) -> Bool {
  if intervals_overlap(a, b) {
    return true
  }
  match (a.hi, b.lo) {
    (Some(h), Some(l)) => {
      let c = ver_cmp(h, l)
      c == 0 && (a.hi_inclusive || b.lo_inclusive)
    }
    _ => false
  }
}

///|
fn lo_cmp(a : Interval, b : Interval) -> Int32 {
  match (a.lo, b.lo) {
    (None, None) => 0
    (None, Some(_)) => -1
    (Some(_), None) => 1
    (Some(x), Some(y)) => {
      let c = ver_cmp(x, y)
      if c != 0 {
        c
        // Equal lower endpoints: sort the inclusive (closed) end first. This
        // lets `intervals_mergeable` detect touching intervals in the next
        // pass. Without it, `>0.0.0` sorts before `=0.0.0`, so the singleton
        // sits after the open interval and `intervals_mergeable` only ever
        // compares (a.hi, b.lo) in the wrong orientation; `>0.0.0 ∪ =0.0.0`
        // then fails to normalise to `>=0.0.0`, breaking canonical form and
        // De Morgan. (Found by the exhaustive triple test below.)
      } else if a.lo_inclusive && !b.lo_inclusive {
        -1
      } else if !a.lo_inclusive && b.lo_inclusive {
        1
      } else {
        0
      }
    }
  }
}

///|
fn sort_intervals(xs : Array[Interval]) -> Unit {
  for i = 1; i < xs.length(); i = i + 1 {
    let key = xs[i]
    let mut j = i - 1
    while j >= 0 && lo_cmp(xs[j], key) > 0 {
      xs[j + 1] = xs[j]
      j = j - 1
    }
    xs[j + 1] = key
  }
}

///|
/// Normalise an interval set: drop empty intervals, sort by lower bound,
/// and merge overlapping intervals. The result is canonical, so two
/// different range expressions that denote the same version set produce
/// the same normalised value.
pub fn normalise(intervals : Array[Interval]) -> Array[Interval] {
  let cleaned : Array[Interval] = []
  for iv in intervals {
    if !interval_is_empty(iv) {
      cleaned.push(iv)
    }
  }
  sort_intervals(cleaned)
  let out : Array[Interval] = []
  for iv in cleaned {
    if out.length() == 0 {
      out.push(iv)
    } else {
      let last = out[out.length() - 1]
      if intervals_mergeable(last, iv) &&
        keys_equal(last.prerelease_keys, iv.prerelease_keys) {
        let (lo, lo_inc) = lo_min(last, iv)
        let (hi, hi_inc) = hi_max(last, iv)
        out[out.length() - 1] = make_interval_with_keys(
          lo,
          lo_inc,
          hi,
          hi_inc,
          last.prerelease_keys,
        )
      } else {
        out.push(iv)
      }
    }
  }
  out
}

///|
/// Alias using American spelling for discoverability.
pub fn normalize(intervals : Array[Interval]) -> Array[Interval] {
  normalise(intervals)
}

///|
/// Union of two interval sets: every version in either set.
pub fn union(a : Array[Interval], b : Array[Interval]) -> Array[Interval] {
  let all : Array[Interval] = []
  for iv in a {
    all.push(iv)
  }
  for iv in b {
    all.push(iv)
  }
  normalise(all)
}

///|
/// Intersection of two interval sets: only versions in both sets.
pub fn intersection(
  a : Array[Interval],
  b : Array[Interval],
) -> Array[Interval] {
  let parts : Array[Interval] = []
  for x in a {
    for y in b {
      let (lo, lo_inc) = lo_max(x, y)
      let (hi, hi_inc) = hi_min(x, y)
      let iv = make_interval_with_keys(
        lo,
        lo_inc,
        hi,
        hi_inc,
        meet_keys(x.prerelease_keys, y.prerelease_keys),
      )
      if !interval_is_empty(iv) {
        parts.push(iv)
      }
    }
  }
  normalise(parts)
}

///|
fn segment_nonempty(
  lo : Version?,
  lo_inc : Bool,
  hi : Version?,
  hi_inc : Bool,
) -> Bool {
  match (lo, hi) {
    (None, None) => true
    (None, Some(_)) => true
    (Some(_), None) => true
    (Some(l), Some(h)) => {
      let c = ver_cmp(l, h)
      c < 0 || (c == 0 && lo_inc && hi_inc)
    }
  }
}

///|
/// Complement of an interval set: every version NOT in the set.
/// Endpoints flip inclusiveness (`>=1.0.0` becomes `<1.0.0`, etc.).
pub fn complement(a : Array[Interval]) -> Array[Interval] {
  let sorted = normalise(a)
  // Complement of the empty set is the whole space.
  if sorted.length() == 0 {
    return universal_set()
  }
  let parts : Array[Interval] = []
  // `gap_lo` is the lower bound of the next complement gap. It starts at
  // -infinity and, after each original interval, moves to that interval's
  // upper bound with inclusiveness flipped (an inclusive end excludes the
  // endpoint from the complement, an exclusive end includes it).
  let mut gap_lo : Version? = None
  let mut gap_lo_inc = true
  for iv in sorted {
    // An interval with lower bound -infinity leaves no gap before it. Emitting
    // one here would wrongly turn e.g. complement(<2.0.0) into "*".
    match iv.lo {
      Some(v) => {
        let gap_hi_inc = !iv.lo_inclusive
        if segment_nonempty(gap_lo, gap_lo_inc, Some(v), gap_hi_inc) {
          parts.push(make_interval(gap_lo, gap_lo_inc, Some(v), gap_hi_inc))
        }
      }
      None => ()
    }
    gap_lo = iv.hi
    gap_lo_inc = match iv.hi {
      // Upper bound +infinity leaves no trailing gap.
      None => false
      Some(_) => !iv.hi_inclusive
    }
  }
  // A trailing gap exists only when the last interval has a finite upper bound.
  match gap_lo {
    Some(_) =>
      if segment_nonempty(gap_lo, gap_lo_inc, None, true) {
        parts.push(make_interval(gap_lo, gap_lo_inc, None, true))
      }
    None => ()
  }
  normalise(parts)
}

///|
/// Difference A \ B, implemented as A ∩ complement(B).
pub fn difference(a : Array[Interval], b : Array[Interval]) -> Array[Interval] {
  intersection(a, complement(b))
}

///|
/// Whether an interval set matches no version.
pub fn is_empty(set : Array[Interval]) -> Bool {
  set.length() == 0
}

///|
/// Whether two interval sets can be satisfied simultaneously.
pub fn satisfiable(a : Array[Interval], b : Array[Interval]) -> Bool {
  !is_empty(intersection(a, b))
}

///|
/// Whether an interval set covers the whole version space.
pub fn is_universal(set : Array[Interval]) -> Bool {
  // Universality is a statement about the version *axis*, independent of
  // any prerelease opt-in policy attached to individual intervals. Strip the
  // policies before checking coverage, otherwise A and complement(A) appear
  // non-universal merely because their policies differ.
  let plain : Array[Interval] = []
  for iv in set {
    plain.push(Interval::new(iv.lo, iv.lo_inclusive, iv.hi, iv.hi_inclusive))
  }
  let s = normalise(plain)
  if s.length() != 1 {
    return false
  }
  match (s[0].lo, s[0].hi) {
    (None, None) => true
    (Some(_), Some(_)) => false
    (None, Some(_)) => false
    (Some(_), None) => false
  }
}

///|
/// Whether a concrete version belongs to an interval set.
pub fn contains(set : Array[Interval], version : Version) -> Bool {
  for iv in set {
    let lower_ok = match iv.lo {
      None => true
      Some(lo) => {
        let c = ver_cmp(version, lo)
        c > 0 || (c == 0 && iv.lo_inclusive)
      }
    }
    let upper_ok = match iv.hi {
      None => true
      Some(hi) => {
        let c = ver_cmp(version, hi)
        c < 0 || (c == 0 && iv.hi_inclusive)
      }
    }
    if keys_allow(iv.prerelease_keys, version) && lower_ok && upper_ok {
      return true
    }
  }
  false
}

///|
/// Convert one conjunctive `Range` into an interval.
fn range_to_interval(r : Range) -> Interval {
  let lo = match r.lower {
    None => None
    Some(b) => Some(b.version)
  }
  let lo_inc = match r.lower {
    None => true
    Some(b) => b.inclusive
  }
  let hi = match r.upper {
    None => None
    Some(b) => Some(b.version)
  }
  let hi_inc = match r.upper {
    None => true
    Some(b) => b.inclusive
  }
  make_interval(lo, lo_inc, hi, hi_inc)
}

///|
/// Build a normalised interval set from an existing `RangeSet`.
pub fn from_range_set(set : RangeSet) -> Array[Interval] {
  let parts : Array[Interval] = []
  // Prerelease opt-in is per `||` branch: attach each group's own keys to
  // its interval. Sharing one global key array across all branches used to
  // let a prerelease in one branch authorise the same tuple in another,
  // disagreeing with both `satisfies` and node-semver.
  for i = 0; i < set.ranges.length(); i = i + 1 {
    let iv = range_to_interval(set.ranges[i])
    parts.push(
      make_interval_with_keys(
        iv.lo,
        iv.lo_inclusive,
        iv.hi,
        iv.hi_inclusive,
        Some(set.keys_per_range[i]),
      ),
    )
  }
  normalise(parts)
}

///|
/// Parse a range expression into a normalised interval set. Supports the
/// same grammar as `parse_range`, including `||` (OR) and whitespace AND.
pub fn parse(text : String) -> Result[Array[Interval], String] {
  match parse_range(text) {
    Ok(set) => Ok(from_range_set(set))
    Err(e) => Err(e)
  }
}

///|
fn bound_text(version : Version, inclusive : Bool, is_lower : Bool) -> String {
  if is_lower {
    if inclusive {
      ">=\{version.to_string()}"
    } else {
      ">\{version.to_string()}"
    }
  } else if inclusive {
    "<=\{version.to_string()}"
  } else {
    "<\{version.to_string()}"
  }
}

///|
fn interval_text(iv : Interval) -> String {
  match (iv.lo, iv.hi) {
    (None, None) => "*"
    (None, Some(h)) => bound_text(h, iv.hi_inclusive, false)
    (Some(l), None) => bound_text(l, iv.lo_inclusive, true)
    (Some(l), Some(h)) =>
      "\{bound_text(l, iv.lo_inclusive, true)} \{bound_text(h, iv.hi_inclusive, false)}"
  }
}

///|
fn join_intervals(set : Array[Interval]) -> String {
  let parts : Array[String] = []
  for iv in set {
    parts.push(interval_text(iv))
  }
  let mut out = ""
  for i = 0; i < parts.length(); i = i + 1 {
    if i > 0 {
      out = out + " || "
    }
    out = out + parts[i]
  }
  out
}

///|
/// Render a normalised interval set as a readable range expression.
pub fn to_string(set : Array[Interval]) -> String {
  if set.length() == 0 {
    return "<empty>"
  }
  join_intervals(normalise(set))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "interval emptiness" {
  let v1 = version_of("1.0.0")
  let v2 = version_of("2.0.0")
  inspect(
    interval_is_empty(Interval::new(Some(v1), true, Some(v2), true)),
    content="false",
  )
  inspect(
    interval_is_empty(Interval::new(Some(v2), true, Some(v1), true)),
    content="true",
  )
  inspect(
    interval_is_empty(Interval::new(Some(v1), false, Some(v1), false)),
    content="true",
  )
  inspect(
    interval_is_empty(Interval::new(Some(v1), true, Some(v1), true)),
    content="false",
  )
}

///|
test "normalise merges overlapping intervals" {
  let a = Interval::new(
    Some(version_of("1.0.0")),
    true,
    Some(version_of("2.0.0")),
    false,
  )
  let b = Interval::new(
    Some(version_of("1.5.0")),
    true,
    Some(version_of("3.0.0")),
    true,
  )
  let n = normalise([a, b])
  inspect(n.length(), content="1")
  inspect(to_string(n), content=">=1.0.0 <=3.0.0")
}

///|
test "normalise keeps disjoint intervals" {
  let a = Interval::new(
    Some(version_of("1.0.0")),
    true,
    Some(version_of("2.0.0")),
    false,
  )
  let b = Interval::new(
    Some(version_of("3.0.0")),
    true,
    Some(version_of("4.0.0")),
    true,
  )
  let n = normalise([a, b])
  inspect(n.length(), content="2")
}

///|
test "union and intersection" {
  let a = parse(">=1.0.0 <2.0.0").unwrap_or_else(fn() { [] })
  let b = parse(">=1.5.0 <3.0.0").unwrap_or_else(fn() { [] })
  inspect(is_empty(union(a, b)), content="false")
  inspect(to_string(intersection(a, b)), content=">=1.5.0 <2.0.0")
  inspect(satisfiable(a, b), content="true")
}

///|
test "difference and complement" {
  let all = universal_set()
  let a = parse(">=1.0.0 <2.0.0").unwrap_or_else(fn() { [] })
  let c = complement(a)
  inspect(contains(c, version_of("0.9.0")), content="true")
  inspect(contains(c, version_of("1.5.0")), content="false")
  inspect(contains(c, version_of("2.0.0")), content="true")
  let d = difference(all, a)
  inspect(to_string(d), content="<1.0.0 || >=2.0.0")
}

///|
test "contains respects endpoints" {
  let a = parse(">1.0.0 <=2.0.0").unwrap_or_else(fn() { [] })
  inspect(contains(a, version_of("1.0.0")), content="false")
  inspect(contains(a, version_of("1.0.1")), content="true")
  inspect(contains(a, version_of("2.0.0")), content="true")
  inspect(contains(a, version_of("2.0.1")), content="false")
}

///|
test "OR expression builds an interval set" {
  let a = parse("^1.0.0 || ^3.0.0").unwrap_or_else(fn() { [] })
  inspect(a.length(), content="2")
  inspect(contains(a, version_of("1.5.0")), content="true")
  inspect(contains(a, version_of("2.5.0")), content="false")
  inspect(contains(a, version_of("3.1.0")), content="true")
}

///|
test "canonical form for equivalent expressions" {
  let a = parse(">=1.0.0 <3.0.0 || >=2.0.0 <4.0.0").unwrap_or_else(fn() { [] })
  let b = parse(">=1.0.0 <4.0.0").unwrap_or_else(fn() { [] })
  inspect(to_string(a) == to_string(b), content="true")
}

///|
/// Hyphen ranges desugar to primitive comparators; the interval set must be
/// identical to the hand-written equivalent expression. This is the algebra
/// layer's direct check of the node-semver semantics implemented in range.mbt.
test "hyphen ranges normalise to their comparator equivalents" {
  inspect(
    to_string(parse("1.2.3 - 2.3.4").unwrap_or_else(fn() { [] })),
    content=to_string(parse(">=1.2.3 <=2.3.4").unwrap_or_else(fn() { [] })),
  )
  inspect(
    to_string(parse("1.2 - 2.3.4").unwrap_or_else(fn() { [] })),
    content=to_string(parse(">=1.2.0 <=2.3.4").unwrap_or_else(fn() { [] })),
  )
  inspect(
    to_string(parse("1.2.3 - 2.3").unwrap_or_else(fn() { [] })),
    content=to_string(parse(">=1.2.3 <2.4.0-0").unwrap_or_else(fn() { [] })),
  )
  inspect(
    to_string(parse("1.2.3 - 2").unwrap_or_else(fn() { [] })),
    content=to_string(parse(">=1.2.3 <3.0.0-0").unwrap_or_else(fn() { [] })),
  )
  // A hyphen range composes with the boolean operations like any other set.
  let a = parse("1.0.0 - 3.0.0").unwrap_or_else(fn() { [] })
  let b = parse("2.0.0 - 4.0.0").unwrap_or_else(fn() { [] })
  inspect(
    to_string(intersection(a, b)),
    content=to_string(parse("2.0.0 - 3.0.0").unwrap_or_else(fn() { [] })),
  )
  inspect(
    satisfiable(a, parse("4.0.0 - 5.0.0").unwrap_or_else(fn() { [] })),
    content="false",
  )
}

// ---------------------------------------------------------------------------
// Regression and algebraic-law tests. These exercise unbounded endpoints and
// the identities that a correct interval algebra must satisfy; several of
// them caught real defects during development (see DEVELOPMENT_LOG).
// ---------------------------------------------------------------------------

///|
test "normalise keeps unbounded lower bound when merging" {
  // (-inf, 2.0.0) U [1.0.0, 3.0.0) = (-inf, 3.0.0): the -infinity bound wins.
  let a = Interval::new(None, true, Some(version_of("2.0.0")), false)
  let b = Interval::new(
    Some(version_of("1.0.0")),
    true,
    Some(version_of("3.0.0")),
    false,
  )
  inspect(to_string(normalise([a, b])), content="<3.0.0")
}

///|
test "normalise keeps unbounded upper bound when merging" {
  // [0.0.0, 2.0.0) U [1.0.0, +inf) = [0.0.0, +inf): +infinity wins.
  let a = Interval::new(
    Some(version_of("0.0.0")),
    true,
    Some(version_of("2.0.0")),
    false,
  )
  let b = Interval::new(Some(version_of("1.0.0")), true, None, true)
  inspect(to_string(normalise([a, b])), content=">=0.0.0")
}

///|
test "normalise merges touching endpoints but keeps gaps" {
  let a = Interval::new(None, true, Some(version_of("1.0.0")), false)
  let b = Interval::new(
    Some(version_of("1.0.0")),
    true,
    Some(version_of("2.0.0")),
    false,
  )
  inspect(to_string(normalise([a, b])), content="<2.0.0")
  // Both ends exclusive => version 1.0.0 is missing => cannot merge.
  let c = Interval::new(None, true, Some(version_of("1.0.0")), false)
  let d = Interval::new(Some(version_of("1.0.0")), false, None, true)
  inspect(normalise([c, d]).length(), content="2")
}

///|
test "complement of unbounded ranges" {
  let lt = parse("<2.0.0").unwrap_or_else(fn() { [] })
  let ge = parse(">=2.0.0").unwrap_or_else(fn() { [] })
  inspect(to_string(complement(lt)), content=">=2.0.0")
  inspect(to_string(complement(ge)), content="<2.0.0")
  inspect(is_empty(complement(universal_set())), content="true")
  inspect(is_universal(complement(empty_set())), content="true")
}

///|
test "double complement is identity" {
  let a = parse(">=1.0.0 <2.0.0 || >=3.0.0 <4.0.0").unwrap_or_else(fn() { [] })
  inspect(to_string(complement(complement(a))) == to_string(a), content="true")
  let b = parse(">1.0.0").unwrap_or_else(fn() { [] })
  inspect(to_string(complement(complement(b))) == to_string(b), content="true")
}

///|
test "complement laws: A union not-A is universal, A intersect not-A is empty" {
  let a = parse(">=1.0.0 <2.0.0").unwrap_or_else(fn() { [] })
  inspect(is_universal(union(a, complement(a))), content="true")
  inspect(is_empty(intersection(a, complement(a))), content="true")
}

///|
test "De Morgan law" {
  let a = parse(">=1.0.0 <3.0.0").unwrap_or_else(fn() { [] })
  let b = parse(">=2.0.0 <4.0.0").unwrap_or_else(fn() { [] })
  let lhs = complement(union(a, b))
  let rhs = intersection(complement(a), complement(b))
  inspect(to_string(lhs) == to_string(rhs), content="true")
}

///|
test "intersection and union identities" {
  let a = parse(">=1.0.0 <3.0.0").unwrap_or_else(fn() { [] })
  let b = parse(">=2.0.0 <4.0.0").unwrap_or_else(fn() { [] })
  // Idempotent
  inspect(to_string(union(a, a)) == to_string(a), content="true")
  inspect(to_string(intersection(a, a)) == to_string(a), content="true")
  // Commutative
  inspect(to_string(union(a, b)) == to_string(union(b, a)), content="true")
  inspect(
    to_string(intersection(a, b)) == to_string(intersection(b, a)),
    content="true",
  )
  // Associative
  let c = parse(">=3.0.0 <5.0.0").unwrap_or_else(fn() { [] })
  inspect(
    to_string(union(union(a, b), c)) == to_string(union(a, union(b, c))),
    content="true",
  )
  inspect(
    to_string(intersection(intersection(a, b), c)) ==
    to_string(intersection(a, intersection(b, c))),
    content="true",
  )
  // Distributive: A ∩ (B ∪ C) = (A ∩ B) ∪ (A ∩ C)
  inspect(
    to_string(intersection(a, union(b, c))) ==
    to_string(union(intersection(a, b), intersection(a, c))),
    content="true",
  )
  // Difference agrees with the complement definition
  inspect(
    to_string(difference(a, b)) == to_string(intersection(a, complement(b))),
    content="true",
  )
}

///|
test "difference with unbounded bounds" {
  let all = universal_set()
  let lt = parse("<2.0.0").unwrap_or_else(fn() { [] })
  inspect(to_string(difference(all, lt)), content=">=2.0.0")
  let ge = parse(">=2.0.0").unwrap_or_else(fn() { [] })
  inspect(to_string(difference(all, ge)), content="<2.0.0")
  // Disjoint subtraction leaves the minuend unchanged; self-subtraction is empty.
  inspect(to_string(difference(lt, ge)) == to_string(lt), content="true")
  inspect(is_empty(difference(lt, lt)), content="true")
}

///|
test "prerelease versions respect SemVer precedence in sets" {
  let s = parse(">=1.0.0-alpha <1.0.0").unwrap_or_else(fn() { [] })
  inspect(contains(s, version_of("1.0.0-alpha.1")), content="true")
  inspect(contains(s, version_of("1.0.0-alpha")), content="true")
  inspect(contains(s, version_of("1.0.0")), content="false")
  inspect(contains(s, version_of("0.9.0")), content="false")
}

///|
/// Regression: caret/tilde/partial exclusive bounds must be `<X.Y.Z-0`, so
/// the algebra layer (pure intervals) agrees with the base `satisfies` layer
/// (prerelease opt-in) on prereleases of the *next* tuple. Before this fix
/// `parse("^1.2.3")` produced `>=1.2.3 <2.0.0`, whose `contains` wrongly
/// accepted `2.0.0-alpha` while `satisfies` correctly rejected it.
test "exclusive upper bounds exclude the next tuple's prereleases" {
  let cases = [
    ("^1.2.3", ">=1.2.3 <2.0.0-0", "2.0.0-alpha"),
    ("~1.2.3", ">=1.2.3 <1.3.0-0", "1.3.0-alpha"),
    ("1.2.x", ">=1.2.0 <1.3.0-0", "1.3.0-alpha"),
    ("1.x", ">=1.0.0 <2.0.0-0", "2.0.0-alpha"),
    ("^0.2.3", ">=0.2.3 <0.3.0-0", "0.3.0-alpha"),
    ("^0.0.3", ">=0.0.3 <0.0.4-0", "0.0.4-alpha"),
  ]
  for (range_text, expected, next_pre) in cases {
    let set = parse(range_text).unwrap_or_else(fn() { [] })
    inspect(to_string(set) == expected, content="true")
    let next = match parse_version(next_pre) {
      Ok(v) => v
      Err(e) => fail("bad fixture \{next_pre}: \{e}")
    }
    // Algebra layer: the next tuple's prerelease is excluded.
    inspect(contains(set, next), content="false")
    // Base layer: satisfies agrees (no prerelease opt-in for the next tuple).
    match satisfies_text(next, range_text) {
      Ok(r) => inspect(r, content="false")
      Err(e) => fail("bad range \{range_text}: \{e}")
    }
  }
}

///|
/// Regression: a prerelease version must only match a parsed interval set
/// when the range explicitly opts in to the same major.minor.patch tuple.
/// Before the opt-in policy was carried on intervals, `contains` used pure
/// precedence and accepted `1.5.0-beta` for `^1.0.0-alpha`, contradicting
/// both `satisfies` and node-semver ("prereleases of a different tuple").
test "algebra prerelease opt-in agrees with satisfies" {
  let s = parse("^1.0.0-alpha").unwrap_or_else(fn() { [] })
  inspect(contains(s, version_of("1.0.0-beta")), content="true")
  inspect(contains(s, version_of("1.0.0-alpha.1")), content="true")
  inspect(contains(s, version_of("1.5.0-beta")), content="false")
  inspect(contains(s, version_of("2.0.0-alpha")), content="false")
  match satisfies_text(version_of("1.5.0-beta"), "^1.0.0-alpha") {
    Ok(r) => inspect(r, content="false")
    Err(e) => fail("bad range: \{e}")
  }
  // A wildcard range does not opt in to any prerelease tuple.
  let all = parse("*").unwrap_or_else(fn() { [] })
  inspect(contains(all, version_of("1.0.0-alpha")), content="false")
  inspect(contains(all, version_of("1.0.0")), content="true")
  // The empty range is the universal X-range, not a parse error.
  inspect(to_string(parse("").unwrap_or_else(fn() { [] })), content="*")
  inspect(
    contains(parse("").unwrap_or_else(fn() { [] }), version_of("9.9.9")),
    content="true",
  )
}

///|
/// Regression: the algebra layer shares `parse_range`, so the node-semver
/// written-precision fix for zero-major caret ranges must be visible here too.
/// `^0` and `^0.x` are <1.0.0-0 while `^0.0` is <0.1.0-0 and `^0.0.0` is
/// <0.0.1-0; previously all four collapsed to <0.0.1-0.
test "algebra layer respects written-precision caret bounds" {
  inspect(
    to_string(parse("^0").unwrap_or_else(fn() { [] })),
    content=">=0.0.0 <1.0.0-0",
  )
  inspect(
    to_string(parse("^0.x").unwrap_or_else(fn() { [] })),
    content=">=0.0.0 <1.0.0-0",
  )
  inspect(
    to_string(parse("^0.0").unwrap_or_else(fn() { [] })),
    content=">=0.0.0 <0.1.0-0",
  )
  inspect(
    to_string(parse("^0.0.0").unwrap_or_else(fn() { [] })),
    content=">=0.0.0 <0.0.1-0",
  )
  // Partial comparators are valid operands and desugar to the same intervals.
  inspect(to_string(parse(">1").unwrap_or_else(fn() { [] })), content=">=2.0.0")
  inspect(
    to_string(parse("<=1.2").unwrap_or_else(fn() { [] })),
    content="<1.3.0-0",
  )
}

///|
test "conflict diagnosis report renders overlap, exclusive parts and status" {
  let a = parse(">=1.0.0 <3.0.0").unwrap_or_else(fn() { [] })
  let b = parse(">=2.0.0 <4.0.0").unwrap_or_else(fn() { [] })
  let expected = "== conflict diagnosis ==\n" +
    "A        = >=1.0.0 <3.0.0\n" +
    "B        = >=2.0.0 <4.0.0\n" +
    "overlap  = >=2.0.0 <3.0.0\n" +
    "A only   = >=1.0.0 <2.0.0\n" +
    "B only   = >=3.0.0 <4.0.0\n" +
    "union    = >=1.0.0 <4.0.0\n" +
    "status   = COMPATIBLE (partial overlap)"
  inspect(algebra_diagnose(a, b) == expected, content="true")

  let c = parse(">=5.0.0 <6.0.0").unwrap_or_else(fn() { [] })
  let conflict = algebra_diagnose(a, c)
  inspect(conflict.contains("overlap  = <empty>"), content="true")
  inspect(
    conflict.contains("status   = CONFLICT (no version satisfies both)"),
    content="true",
  )
  // A is a subset of its union with another set: subset status must appear.
  let sub = algebra_diagnose(a, parse("*").unwrap_or_else(fn() { [] }))
  inspect(
    sub.contains("status   = COMPATIBLE (A is a subset of B)"),
    content="true",
  )
}

// ---------------------------------------------------------------------------
// Public aliases with an explicit `algebra_` prefix. These make the range-set
// algebra API unambiguous next to the classic range API (`parse_range`,
// `satisfies`) and are what the CLI demo calls.
// ---------------------------------------------------------------------------

///|
/// Parse a range expression into a normalised interval set.
pub fn parse_algebra(text : String) -> Result[Array[Interval], String] {
  parse(text)
}

///|
/// Render a normalised interval set as a readable range expression.
pub fn algebra_to_string(set : Array[Interval]) -> String {
  to_string(set)
}

///|
/// Union of two interval sets.
pub fn algebra_union(
  a : Array[Interval],
  b : Array[Interval],
) -> Array[Interval] {
  union(a, b)
}

///|
/// Intersection of two interval sets.
pub fn algebra_intersection(
  a : Array[Interval],
  b : Array[Interval],
) -> Array[Interval] {
  intersection(a, b)
}

///|
/// Difference A \ B.
pub fn algebra_difference(
  a : Array[Interval],
  b : Array[Interval],
) -> Array[Interval] {
  difference(a, b)
}

///|
/// Complement of an interval set.
pub fn algebra_complement(a : Array[Interval]) -> Array[Interval] {
  complement(a)
}

///|
/// Whether two interval sets can be satisfied at the same time.
pub fn algebra_satisfiable(a : Array[Interval], b : Array[Interval]) -> Bool {
  satisfiable(a, b)
}

///|
/// Render a human-readable conflict diagnosis for two interval sets.
///
/// The report shows both normalised sets, their overlap, the parts exclusive
/// to each side, their union and a status line. Every field is derived from
/// the algebra operations, so the report is a faithful view of the sets and
/// can be printed directly by the CLI.
pub fn algebra_diagnose(a : Array[Interval], b : Array[Interval]) -> String {
  let inter = intersection(a, b)
  let a_only = difference(a, b)
  let b_only = difference(b, a)
  let uni = union(a, b)
  let mut out = "== conflict diagnosis ==\n"
  out = out + "A        = " + to_string(a) + "\n"
  out = out + "B        = " + to_string(b) + "\n"
  out = out + "overlap  = " + to_string(inter) + "\n"
  out = out + "A only   = " + to_string(a_only) + "\n"
  out = out + "B only   = " + to_string(b_only) + "\n"
  out = out + "union    = " + to_string(uni) + "\n"
  if is_empty(inter) {
    out = out + "status   = CONFLICT (no version satisfies both)"
  } else if is_empty(a_only) {
    out = out + "status   = COMPATIBLE (A is a subset of B)"
  } else if is_empty(b_only) {
    out = out + "status   = COMPATIBLE (B is a subset of A)"
  } else {
    out = out + "status   = COMPATIBLE (partial overlap)"
  }
  out
}

// ---------------------------------------------------------------------------
// Exhaustive verification over a finite version domain.
//
// The fixed regression tests above pin down known cases; the tests below
// instead *enumerate* every interval whose endpoints are drawn from a small
// finite domain (or are unbounded), then check that each set operation agrees
// with the pointwise boolean meaning of the operation. Membership is decided
// by an independent reference function written directly from the interval
// endpoints, so a defect in `normalise` / `union` / `intersection` /
// `difference` / `complement` cannot hide behind the library's own `contains`.
// ---------------------------------------------------------------------------

///|
fn probe_versions() -> Array[Version] {
  [
    Version::new(0, 0, 0),
    Version::new(0, 0, 1),
    Version::new(0, 0, 2),
    Version::new(0, 0, 3),
    Version::new(0, 0, 4),
    Version::new(0, 0, 100), // beyond every finite endpoint
    Version::new(100, 0, 0),
  ]
}

///|
fn domain_of(size : Int32) -> Array[Version] {
  let out : Array[Version] = []
  for i = 0; i < size; i = i + 1 {
    out.push(Version::new(0, 0, i.to_int64()))
  }
  out
}

///|
fn bounds_from(domain : Array[Version]) -> Array[Version?] {
  let out : Array[Version?] = [None]
  for v in domain {
    out.push(Some(v))
  }
  out
}

///|
fn enumerate_intervals(domain : Array[Version]) -> Array[Interval] {
  let out : Array[Interval] = []
  let bounds = bounds_from(domain)
  for lo in bounds {
    for lo_inc in [true, false] {
      for hi in bounds {
        for hi_inc in [true, false] {
          out.push(Interval::new(lo, lo_inc, hi, hi_inc))
        }
      }
    }
  }
  out
}

///|
/// Reference membership, computed directly from endpoints rather than by
/// calling the library's `contains`.
fn ref_has(set : Array[Interval], v : Version) -> Bool {
  for iv in set {
    let lower_ok = match iv.lo {
      None => true
      Some(l) => {
        let c = compare_version(v, l)
        if iv.lo_inclusive {
          c >= 0
        } else {
          c > 0
        }
      }
    }
    let upper_ok = match iv.hi {
      None => true
      Some(h) => {
        let c = compare_version(v, h)
        if iv.hi_inclusive {
          c <= 0
        } else {
          c < 0
        }
      }
    }
    if keys_allow(iv.prerelease_keys, v) && lower_ok && upper_ok {
      return true
    }
  }
  false
}

///|
fn finite_eq(a : Array[Interval], b : Array[Interval]) -> Bool {
  for v in probe_versions() {
    if ref_has(a, v) != ref_has(b, v) {
      return false
    }
  }
  true
}

///|
/// contains() agrees with the endpoint-based reference on every interval.
test "exhaustive: contains matches reference membership" {
  let ivs = enumerate_intervals(domain_of(5))
  let probes = probe_versions()
  for iv in ivs {
    for v in probes {
      if contains([iv], v) != ref_has([iv], v) {
        fail("contains mismatch at \{v.to_string()} for \{to_string([iv])}")
      }
    }
  }
}

///|
/// Complement is pointwise negation for every interval, including unbounded
/// and singleton intervals.
test "exhaustive: complement is pointwise negation" {
  let ivs = enumerate_intervals(domain_of(5))
  let probes = probe_versions()
  for iv in ivs {
    let c = complement([iv])
    for v in probes {
      if ref_has(c, v) == ref_has([iv], v) {
        fail(
          "complement not negated at \{v.to_string()} for \{to_string([iv])}",
        )
      }
    }
  }
}

///|
/// Union / intersection / difference agree with boolean OR / AND / AND-NOT
/// for every ordered pair of intervals in the finite domain.
test "exhaustive: binary set operations match boolean semantics" {
  let ivs = enumerate_intervals(domain_of(5))
  let probes = probe_versions()
  for a in ivs {
    for b in ivs {
      let u = union([a], [b])
      let i = intersection([a], [b])
      let d = difference([a], [b])
      for v in probes {
        let ma = ref_has([a], v)
        let mb = ref_has([b], v)
        if ref_has(u, v) != (ma || mb) {
          fail(
            "union mismatch at \{v.to_string()}: \{to_string([a])} | \{to_string([b])}",
          )
        }
        if ref_has(i, v) != (ma && mb) {
          fail(
            "intersection mismatch at \{v.to_string()}: \{to_string([a])} & \{to_string([b])}",
          )
        }
        if ref_has(d, v) != (ma && !mb) {
          fail(
            "difference mismatch at \{v.to_string()}: \{to_string([a])} - \{to_string([b])}",
          )
        }
      }
    }
  }
}

///|
/// Boolean algebra laws over every ordered triple of intervals drawn from a
/// three-point domain (64 intervals): associativity, distributivity,
/// De Morgan, absorption, complement laws and double complement.
test "exhaustive: boolean algebra laws over interval triples" {
  let ivs = enumerate_intervals(domain_of(3))
  for a in ivs {
    let cc = complement(complement([a]))
    if !finite_eq(cc, [a]) {
      fail("double complement is not identity for \{to_string([a])}")
    }
    if !is_empty(intersection([a], complement([a]))) {
      fail("A & !A not empty for \{to_string([a])}")
    }
    if !is_universal(union([a], complement([a]))) {
      fail("A | !A not universal for \{to_string([a])}")
    }
    for b in ivs {
      // Commutativity
      if !finite_eq(union([a], [b]), union([b], [a])) {
        fail("union not commutative for \{to_string([a])} / \{to_string([b])}")
      }
      if !finite_eq(intersection([a], [b]), intersection([b], [a])) {
        fail(
          "intersection not commutative for \{to_string([a])} / \{to_string([b])}",
        )
      }
      // De Morgan
      if !finite_eq(
          complement(union([a], [b])),
          intersection(complement([a]), complement([b])),
        ) {
        fail(
          "De Morgan (union) failed for \{to_string([a])} / \{to_string([b])}",
        )
      }
      if !finite_eq(
          complement(intersection([a], [b])),
          union(complement([a]), complement([b])),
        ) {
        fail(
          "De Morgan (intersection) failed for \{to_string([a])} / \{to_string([b])}",
        )
      }
      // Absorption
      if !finite_eq(union([a], intersection([a], [b])), [a]) {
        fail(
          "absorption (union) failed for \{to_string([a])} / \{to_string([b])}",
        )
      }
      if !finite_eq(intersection([a], union([a], [b])), [a]) {
        fail(
          "absorption (intersection) failed for \{to_string([a])} / \{to_string([b])}",
        )
      }
      for c in ivs {
        if !finite_eq(union(union([a], [b]), [c]), union([a], union([b], [c]))) {
          fail(
            "union not associative for \{to_string([a])} / \{to_string([b])} / \{to_string([c])}",
          )
        }
        if !finite_eq(
            intersection(intersection([a], [b]), [c]),
            intersection([a], intersection([b], [c])),
          ) {
          fail(
            "intersection not associative for \{to_string([a])} / \{to_string([b])} / \{to_string([c])}",
          )
        }
        if !finite_eq(
            intersection([a], union([b], [c])),
            union(intersection([a], [b]), intersection([a], [c])),
          ) {
          fail(
            "distribution failed for \{to_string([a])} / \{to_string([b])} / \{to_string([c])}",
          )
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Property-based testing (QuickCheck-style, but deterministic).
//
// Instead of enumerating a fixed set of cases, we generate pseudo-random
// interval sets from a seed and assert algebraic laws over them. The generator
// is a Park-Miller LCG implemented in MoonBit with no external dependency, so
// every run is reproducible: a failing seed can be replayed exactly.
//
// Equality of two sets is decided by `prop_eq`, which compares membership on
// a dense probe domain using the independent endpoint-based `ref_has` (never
// the library's own `contains`). The probe inserts prerelease points between
// consecutive patch versions so open/closed endpoints are distinguishable.
// ---------------------------------------------------------------------------

///|
/// Park-Miller minimal standard generator. Seed stays below 2^31, so the
/// multiplication cannot overflow Int64.
fn rand_int(seed : Int64, bound : Int64) -> (Int64, Int64) {
  let next = seed * 16807 % 2147483647
  (next % bound, next)
}

///|
/// Generate an interval set of up to three pseudo-random intervals.
fn rand_set(seed : Int64, domain : Array[Version]) -> (Array[Interval], Int64) {
  let bounds = bounds_from(domain)
  let bound_count = bounds.length().to_int64()
  let mut state = seed
  let out : Array[Interval] = []
  for _i = 0; _i < 3; _i = _i + 1 {
    let (lo_i, s1) = rand_int(state, bound_count)
    let (hi_i, s2) = rand_int(s1, bound_count)
    let (lo_b, s3) = rand_int(s2, 2)
    let (hi_b, s4) = rand_int(s3, 2)
    state = s4
    out.push(
      Interval::new(
        bounds[lo_i.to_int()],
        lo_b == 1,
        bounds[hi_i.to_int()],
        hi_b == 1,
      ),
    )
  }
  (out, state)
}

///|
/// A version with a prerelease identifier, constructed directly so this
/// helper stays free of the error effect carried by `version_of`.
fn pre_version(patch : Int64) -> Version {
  { major: 0, minor: 0, patch, prerelease: ["alpha"], build: None, }
}

///|
/// Dense probe: a prerelease point between every pair of patch versions makes
/// open/closed endpoints observable, and the trailing points lie beyond every
/// finite endpoint generated by `rand_set`.
fn property_probe() -> Array[Version] {
  [
    pre_version(0),
    Version::new(0, 0, 0),
    pre_version(1),
    Version::new(0, 0, 1),
    pre_version(2),
    Version::new(0, 0, 2),
    pre_version(3),
    Version::new(0, 0, 3),
    pre_version(4),
    Version::new(0, 0, 4),
    Version::new(0, 0, 5),
    Version::new(100, 0, 0),
  ]
}

///|
fn prop_eq(a : Array[Interval], b : Array[Interval]) -> Bool {
  for v in property_probe() {
    if ref_has(a, v) != ref_has(b, v) {
      return false
    }
  }
  true
}

///|
/// Deterministic property test: 250 seeds x 3 random interval sets, checking
/// the full boolean-algebra law set against an independent membership oracle.
test "property: pseudo-random sets satisfy boolean algebra laws" {
  let domain = domain_of(5)
  let mut seed : Int64 = 1
  for iter = 0; iter < 250; iter = iter + 1 {
    let (a, s1) = rand_set(seed, domain)
    let (b, s2) = rand_set(s1 + 1, domain)
    let (c, s3) = rand_set(s2 + 1, domain)
    seed = s3 + 1

    if !prop_eq(union(a, a), a) {
      fail("iter \{iter}: union not idempotent")
    }
    if !prop_eq(intersection(a, a), a) {
      fail("iter \{iter}: intersection not idempotent")
    }
    if !prop_eq(union(a, b), union(b, a)) {
      fail("iter \{iter}: union not commutative")
    }
    if !prop_eq(intersection(a, b), intersection(b, a)) {
      fail("iter \{iter}: intersection not commutative")
    }
    if !prop_eq(union(union(a, b), c), union(a, union(b, c))) {
      fail("iter \{iter}: union not associative")
    }
    if !prop_eq(
        intersection(intersection(a, b), c),
        intersection(a, intersection(b, c)),
      ) {
      fail("iter \{iter}: intersection not associative")
    }
    if !prop_eq(
        intersection(a, union(b, c)),
        union(intersection(a, b), intersection(a, c)),
      ) {
      fail("iter \{iter}: intersection over union not distributive")
    }
    if !prop_eq(
        union(a, intersection(b, c)),
        intersection(union(a, b), union(a, c)),
      ) {
      fail("iter \{iter}: union over intersection not distributive")
    }
    if !prop_eq(
        complement(union(a, b)),
        intersection(complement(a), complement(b)),
      ) {
      fail("iter \{iter}: De Morgan (union) failed")
    }
    if !prop_eq(
        complement(intersection(a, b)),
        union(complement(a), complement(b)),
      ) {
      fail("iter \{iter}: De Morgan (intersection) failed")
    }
    if !prop_eq(complement(complement(a)), a) {
      fail("iter \{iter}: double complement failed")
    }
    if !prop_eq(union(a, complement(a)), universal_set()) {
      fail("iter \{iter}: A union not-A is not universal")
    }
    if !is_empty(intersection(a, complement(a))) {
      fail("iter \{iter}: A intersection not-A is not empty")
    }
    if !prop_eq(difference(a, b), intersection(a, complement(b))) {
      fail("iter \{iter}: difference disagrees with complement definition")
    }
    if !prop_eq(union(a, intersection(a, b)), a) {
      fail("iter \{iter}: absorption (union) failed")
    }
    if !prop_eq(intersection(a, union(a, b)), a) {
      fail("iter \{iter}: absorption (intersection) failed")
    }
    if satisfiable(a, b) != !is_empty(intersection(a, b)) {
      fail("iter \{iter}: satisfiable disagrees with intersection")
    }
  }
}
