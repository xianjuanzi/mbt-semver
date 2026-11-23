// Copyright 2026 MoonBit Hackathon contributor
// Licensed under the Apache License, Version 2.0.

///|
fn usage() -> Unit {
  println("mbt-semver - a SemVer 2.0.0 library demo written in MoonBit")
  println("")
  println("usage:")
  println("  moon run cmd -- parse <version>")
  println("  moon run cmd -- compare <version-a> <version-b>")
  println("  moon run cmd -- check <version> <range>")
  println("  moon run cmd -- algebra           # range set algebra demo")
  println("  moon run cmd -- diagnose <range-a> <range-b>")
  println("  moon run cmd -- demo")
}

///|
fn show_parse(text : String) -> Unit {
  match @semver.parse_version(text) {
    Ok(v) => {
      println("parsed: \{v.to_string()}")
      println("core: \{v.major}.\{v.minor}.\{v.patch}")
      println("prerelease identifiers: \{v.prerelease.length()}")
    }
    Err(e) => println("invalid version '\{text}': \{e}")
  }
}

///|
fn show_compare(a_text : String, b_text : String) -> Unit {
  match (@semver.parse_version(a_text), @semver.parse_version(b_text)) {
    (Ok(a), Ok(b)) => {
      let c = @semver.compare_version(a, b)
      let word = if c < 0 {
        "LOWER"
      } else if c > 0 {
        "HIGHER"
      } else {
        "EQUAL"
      }
      println("\{a_text} is \{word} than \{b_text}")
    }
    (Err(e), _) => println("invalid version '\{a_text}': \{e}")
    (_, Err(e)) => println("invalid version '\{b_text}': \{e}")
  }
}

///|
fn show_check(version_text : String, range_text : String) -> Unit {
  match @semver.parse_version(version_text) {
    Err(e) => println("invalid version '\{version_text}': \{e}")
    Ok(v) =>
      match @semver.satisfies_text(v, range_text) {
        Ok(result) => {
          let word = if result { "SATISFIES" } else { "DOES NOT SATISFY" }
          println("\{version_text} \{word} \{range_text}")
        }
        Err(e) => println("invalid range '\{range_text}': \{e}")
      }
  }
}

///|
fn show_demo() -> Unit {
  println("== catalogue ==")
  let core = match
    @semver.parse_catalogue(["1.0.0", "1.5.0", "2.0.0", "2.1.0"]) {
    Ok(v) => v
    Err(e) => {
      println("catalogue error: \{e}")
      return
    }
  }
  let extra = match @semver.parse_catalogue(["0.1.0", "0.2.0"]) {
    Ok(v) => v
    Err(e) => {
      println("catalogue error: \{e}")
      return
    }
  }
  println("core  = 1.0.0, 1.5.0, 2.0.0, 2.1.0")
  println("extra = 0.1.0, 0.2.0")

  println("")
  println("== constraints ==")
  println("core >=1.0.0 <2.0.0")
  println("core ^1.2.0")
  println("extra ~0.1.0")

  let catalogue = [("core", core), ("extra", extra)]
  let requirements = [
    @semver.Requirement::new("core", ">=1.0.0 <2.0.0"),
    @semver.Requirement::new("core", "^1.2.0"),
    @semver.Requirement::new("extra", "~0.1.0"),
  ]
  match @semver.resolve(catalogue, requirements) {
    Ok(result) => {
      println("")
      println("== selected ==")
      for entry in result.selected {
        println("\{entry.0} -> \{entry.1.to_string()}")
      }
    }
    Err(e) => println("resolution failed: \{e}")
  }
}

///|
fn show_algebra() -> Unit {
  println("== range set algebra ==")
  let a = @semver.parse_algebra(">=1.0.0 <3.0.0")
  let b = @semver.parse_algebra(">=2.0.0 <4.0.0")
  match (a, b) {
    (Ok(x), Ok(y)) => {
      println("A        = \{@semver.algebra_to_string(x)}")
      println("B        = \{@semver.algebra_to_string(y)}")
      println(
        "A union B= \{@semver.algebra_to_string(@semver.algebra_union(x, y))}",
      )
      println(
        "A inter B= \{@semver.algebra_to_string(@semver.algebra_intersection(x, y))}",
      )
      println(
        "A minus B= \{@semver.algebra_to_string(@semver.algebra_difference(x, y))}",
      )
      println(
        "compl A  = \{@semver.algebra_to_string(@semver.algebra_complement(x))}",
      )
      println("A & B satisfiable = \{@semver.algebra_satisfiable(x, y)}")
    }
    (Err(e), _) => println("invalid range A: \{e}")
    (_, Err(e)) => println("invalid range B: \{e}")
  }
  println("")
  println("== canonical form (two expressions, same version set) ==")
  match
    (
      @semver.parse_algebra(">=1.0.0 <3.0.0 || >=2.0.0 <4.0.0"),
      @semver.parse_algebra(">=1.0.0 <4.0.0"),
    ) {
    (Ok(x), Ok(y)) => {
      println("normalised 1 = \{@semver.algebra_to_string(x)}")
      println("normalised 2 = \{@semver.algebra_to_string(y)}")
    }
    (Err(e), _) => println("invalid range: \{e}")
    (_, Err(e)) => println("invalid range: \{e}")
  }
  println("")
  println("== hyphen ranges (node-semver inclusive set) ==")
  match
    (
      @semver.parse_algebra("1.2.3 - 2.3.4"),
      @semver.parse_algebra("1.2.3 - 2.3"),
      @semver.parse_algebra("1.2.3 - 2"),
    ) {
    (Ok(x), Ok(y), Ok(z)) => {
      println("1.2.3 - 2.3.4 = \{@semver.algebra_to_string(x)}")
      println("1.2.3 - 2.3   = \{@semver.algebra_to_string(y)}")
      println("1.2.3 - 2     = \{@semver.algebra_to_string(z)}")
    }
    (Err(e), _, _) => println("invalid range: \{e}")
    (_, Err(e), _) => println("invalid range: \{e}")
    (_, _, Err(e)) => println("invalid range: \{e}")
  }
}

///|
fn show_diagnose(a_text : String, b_text : String) -> Unit {
  match (@semver.parse_algebra(a_text), @semver.parse_algebra(b_text)) {
    (Ok(a), Ok(b)) => println(@semver.algebra_diagnose(a, b))
    (Err(e), _) => println("invalid range A '\{a_text}': \{e}")
    (_, Err(e)) => println("invalid range B '\{b_text}': \{e}")
  }
}

///|
fn main {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    return
  }
  let command = args[1]
  if command == "parse" && args.length() >= 3 {
    show_parse(args[2])
  } else if command == "compare" && args.length() >= 4 {
    show_compare(args[2], args[3])
  } else if command == "check" && args.length() >= 4 {
    show_check(args[2], args[3])
  } else if command == "algebra" {
    show_algebra()
  } else if command == "diagnose" && args.length() >= 4 {
    show_diagnose(args[2], args[3])
  } else if command == "demo" {
    show_demo()
  } else {
    usage()
  }
}
