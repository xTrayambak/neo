## Package reference parsing machinery tests
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak@disroot.org)
import std/unittest
import routines/packref_parser, types/project
import pkg/[results, shakar, pretty]

suite "package reference parser":
  test "warmup tests":
    let
      xr1 = parsePackageRefExpr("flatty >= 0.1.0")
      xr2 = parsePackageRefExpr("gh:foo/bar#pretendthatthisisacommithash")
      xr3 = parsePackageRefExpr("etf <= 0.3.0")
      xr4 = parsePackageRefExpr("url == 0.6.33")
      xr5 = parsePackageRefExpr("https://github.com/ferus-web/bali >= 0.8.2")

    check(*xr1)
    check(*xr2)
    check(*xr3)
    check(*xr4)
    check(*xr5)

    let x1 = &xr1
    check(x1.name == "flatty")
    check(x1.constraint == VerConstraint.GreaterThanEqual)
    check(x1.version.major == 0)
    check(x1.version.minor == 1)
    check(x1.version.patch == 0)

    let x2 = &xr2
    check(x2.name == "gh:foo/bar")
    check(x2.version.major == 0)
    check(x2.constraint == VerConstraint.None)
    check(*x2.hash)
    check(&x2.hash == "pretendthatthisisacommithash")

    let x3 = &xr3
    check(x3.name == "etf")
    check(x3.version.minor == 3)
    check(x3.constraint == VerConstraint.LesserThanEqual)

    let x4 = &xr4
    check(x4.name == "url")
    check(x4.constraint == VerConstraint.Equal)
    check(x4.version.patch == 33)

    let x5 = &xr5
    check(x5.name == "https://github.com/ferus-web/bali")
    check(x5.constraint == VerConstraint.GreaterThanEqual)
    check(x5.version.major == 0)
    check(x5.version.minor == 8)
    check(x5.version.patch == 2)

  test "whitespace quirk tests":
    let
      xr1 = parsePackageRefExpr("   whitespace#   shouldbetrimmed")
      xr2 = parsePackageRefExpr("foo >=     0.3.21")

    check(*xr1)
    check(*xr2)

    let x1 = &xr1
    check(x1.name == "whitespace")
    check(&x1.hash == "shouldbetrimmed")

    let x2 = &xr2
    check(x2.name == "foo")
    check(x2.version.major == 0)
    check(x2.version.minor == 3)
    check(x2.version.patch == 21)

  test "erroneous tests":
    let
      # If a hash (#) is encountered, there must be atleast 1 succeeding character ahead.
      xr1 = parsePackageRefExpr("thing#")

      # This is an error, but not for the reason you might think:
      # the parser parses the package's name as "foo0.1.0",
      # but reports an error because no constraint expectation was parsed.
      xr2 = parsePackageRefExpr("foo 0.1.0")

      # (o_O)
      xr3 = parsePackageRefExpr("foo >= 0.4.1#eb3cm2")

      xr4 = parsePackageRefExpr("foo#eb3cm2 >= 0.4.1")

    check(!xr1)
    check(!xr2)
    check(!xr3)
    check(!xr4)

    let x1 = xr1.error()
    check(x1 == PRefParseError.ExpectedCommitHash)

    let x2 = xr2.error()
    check(x2 == PRefParseError.ExpectedConstraint)

    let x3 = xr3.error()
    check(x3 == PRefParseError.InvalidVersion)

    let x4 = xr4.error()
    check(x4 == PRefParseError.InvalidCommitHash)
