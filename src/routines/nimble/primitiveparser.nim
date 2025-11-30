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

  func extractStrVecValue(
      line: string, findArrDelims: bool = true
  ): seq[string] {.inline.} =
    # Let index be the place where the first "@[" occurs.
    # Let stop be the place where the final closing-bracket (]) occurs.
    var index = (if findArrDelims: line.find("@[") else: 0) + 2
    let stop =
      if findArrDelims:
        line.rfind(']')
      else:
        line.len

    # Optimization: We can count how many elements we're
    # going to parse up-ahead by counting the number
    # of commas in this line.
    var vec = newSeqOfCap[string](line.count(','))
    var curr: string
    var insideStr = false

    while index < stop:
      let c = line[index]
      case c
      of ',':
        discard
      of '"':
        if insideStr:
          vec &= curr
          curr.reset()
          insideStr = false
        else:
          insideStr = true
      else:
        if insideStr:
          curr &= c

        discard "Not needed"

      inc index

    ensureMove(vec)

  let lines = source.splitLines()
  for i, line in lines:
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
      if not line.contains(','):
        # Fast path: single-require
        pkg.requires &= extractStrValue(line)
      else:
        # Slow path: multiple packages in one require,
        # because for some reason `requires` is varargs (I swear this
        # is extremely stupid)

        # FIXME: Also this is brittle as hell and will probably break
        var reqLines: seq[string]
        for line in lines[i ..< lines.len]:
          let splitted = line.split(',')
          if splitted.len > 1:
            for splittedLine in splitted:
              let stripped = strip(splittedLine)
              if stripped.len < 1:
                continue

              reqLines &= stripped

            continue

          break

        for line in reqLines:
          pkg.requires &= extractStrValue(line)

  ensureMove(pkg)
