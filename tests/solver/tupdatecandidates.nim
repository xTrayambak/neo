## Test suite for the solver routines that compute lockfile dependency
## update candidates.
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak@disroot.org)
import std/unittest
import routines/dependencies
import pkg/[results, shakar, pretty, semver]

template v(s: string): semver.Version =
  # Template to make version parsing less verbose.
  parseVersion(s)

suite "update candidacy solver":
  test "0.4.3 ; { 0.4.41, 0.4.48, 0.4.91 } => 0.4.91":
    check &computePotentialUpdateCandidate(v"0.4.3", @[v"0.4.41", v"0.4.48", v"0.4.91"]) ==
      v"0.4.91"

  test "0.8.33 ; { 0.3.21, 0.8.33, 0.8.32, 0.1.0 } => None":
    check !computePotentialUpdateCandidate(
      v"0.8.33", @[v"0.3.21", v"0.8.33", v"0.8.32", v"0.1.0"]
    )

  test "1.18.1 ; { 2.0.2, 2.2.4, 1.18.4, 1.21.8 } => 1.21.8":
    # Avoid major upgrades
    check &computePotentialUpdateCandidate(v"1.18.1", @[v"2.0.2", v"1.18.4", v"1.21.8"]) ==
      v"1.21.8"
