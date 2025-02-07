# Package

version = "0.1.0"
author = "xTrayambak"
description = "A new package manager for Nim with an intelligible codebase"
license = "BSD-3-Clause"
srcDir = "src"
bin = @["neo"]

# Dependencies

requires "nim >= 2.2.0"
requires "zippy >= 0.10.16"
requires "curly >= 1.1.1"
requires "noise >= 0.1.10"
requires "yaml >= 2.1.1"
requires "semver >= 1.2.3"

requires "jsony >= 1.1.5"