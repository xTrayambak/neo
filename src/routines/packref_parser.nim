## Package reference parser machinery
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak@disroot.org)

import std/[options, strutils]
import pkg/[results, semver]
import ../types/[project]

type
  PRefParserState {.size: sizeof(uint8), pure.} = enum
    Name
    Constraint
    Hash
    Version

  PRefParseError* {.size: sizeof(uint8), pure.} = enum
    InvalidConstraint = "invalid constraint"
    InvalidVersion = "version string cannot be parsed"

func parsePackageRefExpr*(expr: string): Result[PackageRef, PRefParseError] =
  var state: PRefParserState
  var i = 0
  var pkg: PackageRef
  pkg.name = newStringOfCap(expr.len - 1) # Best case, expr is unversioned.

  let size = expr.len

  while i < size:
    case state
    of PRefParserState.Name:
      case expr[i]
      of {'>', '<', '='}:
        # If c is in { '>', '<', '=' }, set state to Constraint.
        state = PRefParserState.Constraint
      of '#':
        # If c is a hashtag (#), set state to Hash,
        # and increemnt the pointer by 1.
        state = PRefParserState.Hash
        inc i
      of strutils.Whitespace:
        # If c is whitespace, ignore it and increment the pointer by 1.
        inc i
      else:
        # Otherwise, append c to the name buffer.
        pkg.name &= expr[i]

        # Increment the pointer by 1.
        inc i
    of PRefParserState.Hash:
      # Let buff be a string.
      var buff = newStringOfCap(size - i)

      # While EOF has not been reached, 
      while i < size:
        # Increment the character at the pointer to buff.
        buff &= expr[i]
        inc i

      # Set ref.hash to buffer.
      pkg.hash = some(ensureMove(buff))

      # End the loop.
      break
    of PRefParserState.Constraint:
      # Allocate a constraint buffer, preferrably
      # accounting for the worst-case of 2 bytes.
      var constraintBuffer = newStringOfCap(2)

      # While c is in {'>', '<', '='}:
      while i != size and expr[i] in {'>', '<', '='}:
        # Append c to the constraint buffer.
        constraintBuffer &= expr[i]

        # Increment the pointer by 1.
        inc i

      case constraintBuffer
      of "==":
        # If the buffer is "==", the constraint is Equal.
        pkg.constraint = VerConstraint.Equal
      of ">=":
        # If the buffer is ">=", the constraint is GreaterThanEqual.
        pkg.constraint = VerConstraint.GreaterThanEqual
      of ">":
        # If the buffer is ">", the constraint is GreaterThan.
        pkg.constraint = VerConstraint.GreaterThan
      of "<":
        # If the buffer is "<", the constraint is LesserThan.
        pkg.constraint = VerConstraint.LesserThan
      of "<=":
        # If the buffer is "<=", the constraint is LesserThanEqual.
        pkg.constraint = VerConstraint.LesserThanEqual
      else:
        # Otherwise, report an error.
        return err(PRefParseError.InvalidConstraint)

      # Set the state to Version.
      state = PRefParserState.Version
    of PRefParserState.Version:
      var versionBuffer: string

      # While we have not reached EOF, continually increment every
      # character to the version buffer, and increment
      # the pointer.
      while i != size:
        versionBuffer &= expr[i]
        inc i

      # Trim all left-facing whitespace
      # from the version buffer.
      versionBuffer = strip(move(versionBuffer))

      # Pass the resulting version buffer to a semantic version
      # parsing routine.
      try:
        pkg.version = parseVersion(ensureMove(versionBuffer))
      except semver.ParseError:
        # If version parsing fails, report an error.
        return err(PRefParseError.InvalidVersion)

  # Return `pkg`.
  ok(ensureMove(pkg))
