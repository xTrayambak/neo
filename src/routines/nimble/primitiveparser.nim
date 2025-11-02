## A primitive "parser" for .nimble files.
## It does not require the entire compiler to be imported, but it's
## probably more fragile than the declarative parser.
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import std/[strutils, tables]
import ./fileinfo

export fileinfo

func parseNimbleFile*(source: string): NimbleFileInfo =
  var pkg: NimbleFileInfo

  func extractStrValue(line: string): string {.inline.} =
    # Let index be the place where the first quote occurs.
    # Let stop be the place where the last quote occurs.
    let
      index = line.find('"')
      stop = line.rfind('"')

    line[index + 1 ..< stop]

  func extractStrVecValue(line: string): seq[string] {.inline.} =
    # Let index be the place where the first "@[" occurs.
    # Let stop be the place where the final closing-bracket (]) occurs.
    var index = line.find("@[")
    let stop = line.rfind(']')

    # Optimization: We can count how many elements we're
    # going to parse up-ahead by counting the number
    # of commas in this line.
    var vec = newSeqOfCap[string](line.count(','))
    var curr: string

    while index < stop:
      let c = line[index]
      case c
      of ',':
        vec &= curr
        curr.reset()
      else:
        curr &= c

      inc index

    ensureMove(vec)

  for line in source.splitLines():
    if line.startsWith("version"):
      pkg.version = extractStrValue(line)
    elif line.startsWith("license"):
      pkg.license = extractStrValue(line)
    elif line.startsWith("srcDir"):
      pkg.srcDir = extractStrValue(line)
    elif line.startsWith("bin"):
      for bin in extractStrVecValue(line):
        # CLEANME: Legacy cruft from the Nimble struct.
        pkg.bin[bin] = bin
    elif line.startsWith("backend"):
      pkg.backend = extractStrValue(line)
    elif line.startsWith("task"):
      pkg.tasks.setLen(1)
        # Instead of parsing tasks, we'll just let Neo that they're mentioned.
    elif line.startsWith("description"):
      pkg.description = extractStrValue(line)
    elif line.startsWith("requires"):
      pkg.requires &= extractStrValue(line)

  ensureMove(pkg)
