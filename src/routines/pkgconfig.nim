## Routines for working with `pkg-config`
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak@disroot.org)
import std/[os, osproc, strutils]
import pkg/[results]

type
  PkgConfError* = object of OSError
  PkgConfNotInstalled* = object of PkgConfError

  PkgConfInfoKind* {.pure, size: sizeof(uint8).} = enum
    Cflags = 0
    Libs = 1

proc getPkgConfPath*(): string =
  let path = findExe("pkg-config")

  if unlikely(path.len < 1):
    raise newException(PkgConfNotInstalled, "pkg-config was not found in the PATH")

  path

proc getLibsInfo*(
    targets: seq[string], infoKind: PkgConfInfoKind, binPath: string = getPkgConfPath()
): Result[string, string] {.sideEffect.} =
  let payload = binPath & " --cflags " & targets.join(" ")

  when not defined(release):
    debugEcho(payload)

  let (output, code) = execCmdEx(payload)

  if code != 0:
    return err(strip(output))

  ok(strip(output))
