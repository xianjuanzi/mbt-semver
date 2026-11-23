// Copyright 2026 MoonBit Hackathon contributor
// Licensed under the Apache License, Version 2.0.

///|
/// A version constraint on one package, expressed in the range syntax
/// supported by this module.
pub struct Requirement {
  name : String
  range_text : String
}

///|
/// Build a requirement from a package name and a range expression.
pub fn Requirement::new(name : String, range_text : String) -> Requirement {
  { name, range_text, }
}

///|
/// The result of resolving a set of constraints against available versions.
pub struct Resolution {
  selected : Array[(String, Version)]
}

///|
/// Pick the greatest version from a candidate list.
pub fn select_highest(candidates : Array[Version]) -> Version? {
  if candidates.length() == 0 {
    return None
  }
  let mut best = candidates[0]
  for i = 1; i < candidates.length(); i = i + 1 {
    if compare_version(candidates[i], best) > 0 {
      best = candidates[i]
    }
  }
  Some(best)
}

///|
/// Parse every entry in a list of version strings. Fails on the first bad
/// entry so that callers never resolve against a partially parsed catalogue.
pub fn parse_catalogue(texts : Array[String]) -> Result[Array[Version], String] {
  let versions : Array[Version] = []
  for text in texts {
    match parse_version(text) {
      Ok(v) => versions.push(v)
      Err(e) => return Err("\{text}: \{e}")
    }
  }
  Ok(versions)
}

///|
fn ranges_for(
  name : String,
  requirements : Array[Requirement],
) -> Result[Array[RangeSet], String] {
  let sets : Array[RangeSet] = []
  for req in requirements {
    if req.name == name {
      match parse_range(req.range_text) {
        Ok(set) => sets.push(set)
        Err(e) => return Err("\{name}: \{e}")
      }
    }
  }
  Ok(sets)
}

///|
fn names_of(requirements : Array[Requirement]) -> Array[String] {
  let names : Array[String] = []
  for req in requirements {
    let mut seen = false
    for name in names {
      if name == req.name {
        seen = true
      }
    }
    if !seen {
      names.push(req.name)
    }
  }
  names
}

///|
fn versions_of(
  name : String,
  catalogue : Array[(String, Array[Version])],
) -> Array[Version] {
  for entry in catalogue {
    if entry.0 == name {
      return entry.1
    }
  }
  []
}

///|
/// Resolve a list of direct constraints. For every required package, all
/// constraints are intersected; the highest available version that satisfies
/// every one of them is selected. This is intentionally a direct-dependency
/// solver: it does not traverse transitive dependencies, which keeps the
/// algorithm deterministic and easy to audit.
pub fn resolve(
  catalogue : Array[(String, Array[Version])],
  requirements : Array[Requirement],
) -> Result[Resolution, String] {
  let selected : Array[(String, Version)] = []
  for name in names_of(requirements) {
    let sets = match ranges_for(name, requirements) {
      Ok(sets) => sets
      Err(e) => return Err(e)
    }
    let candidates : Array[Version] = []
    for v in versions_of(name, catalogue) {
      let mut fits = true
      for set in sets {
        if !satisfies(v, set) {
          fits = false
        }
      }
      if fits {
        candidates.push(v)
      }
    }
    match select_highest(candidates) {
      Some(v) => selected.push((name, v))
      None =>
        return Err("no available version of \{name} satisfies all constraints")
    }
  }
  Ok({ selected, })
}

///|
fn[T, E] r_is_ok(result : Result[T, E]) -> Bool {
  match result {
    Ok(_) => true
    Err(_) => false
  }
}

///|
fn rv_of(text : String) -> Version raise {
  match parse_version(text) {
    Ok(v) => v
    Err(e) => fail("invalid test fixture \{text}: \{e}")
  }
}

///|
test "select highest version" {
  let candidates : Array[Version] = []
  for text in ["1.0.0", "2.1.0", "2.0.9", "1.9.9"] {
    candidates.push(rv_of(text))
  }
  match select_highest(candidates) {
    Some(v) => inspect(v.to_string(), content="2.1.0")
    None => inspect("none", content="2.1.0")
  }
  match select_highest([]) {
    Some(_) => inspect("some", content="none")
    None => inspect("none", content="none")
  }
}

///|
test "resolve intersecting constraints" {
  let core = parse_catalogue(["1.0.0", "1.5.0", "2.0.0", "2.1.0"])
  let extra = parse_catalogue(["0.1.0", "0.2.0"])
  match (core, extra) {
    (Ok(core), Ok(extra)) => {
      let catalogue = [("core", core), ("extra", extra)]
      let requirements = [
        { name: "core", range_text: ">=1.0.0 <2.0.0", },
        { name: "core", range_text: "^1.2.0", },
        { name: "extra", range_text: "~0.1.0", },
      ]
      match resolve(catalogue, requirements) {
        Ok(result) => {
          inspect(result.selected.length(), content="2")
          inspect(result.selected[0].1.to_string(), content="1.5.0")
          inspect(result.selected[1].1.to_string(), content="0.1.0")
        }
        Err(e) => fail("unexpected resolution failure: \{e}")
      }
    }
    _ => fail("invalid catalogue fixture")
  }
}

///|
test "conflicting constraints are reported" {
  let core = match parse_catalogue(["1.0.0", "2.0.0"]) {
    Ok(v) => v
    Err(e) => fail("\{e}")
  }
  let requirements = [
    { name: "core", range_text: "^1.0.0", },
    { name: "core", range_text: "^2.0.0", },
  ]
  inspect(r_is_ok(resolve([("core", core)], requirements)), content="false")
}
