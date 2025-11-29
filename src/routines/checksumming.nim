## Routines to checksum a project based off of all of the files in its tree
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import std/[algorithm, os, strutils, sequtils]
import pkg/crunchy/sha256
import ./[dependencies]

proc computeChecksum*(directory: string): string =
  assert(
    dirExists(directory),
    "Cannot compute checksum of directory as it does not exist: " & directory,
  )

  var buffer = newStringOfCap(2048)
  let files = sorted(toSeq(walkDirRec(directory)))

  for file in files:
    buffer &= readFile(file)

  let checksum = sha256(ensureMove(buffer))
  var res = newString(checksum.len)
  for i, b in checksum:
    res[i] = cast[char](b)

  toLowerAscii(toHex(ensureMove(res)))

proc computeChecksum*(name: string, version: string): string =
  computeChecksum(getDirectoryForPackage(name, version))
