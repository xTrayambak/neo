import std/[os, osproc, strutils, options]
import ./[compilation_options, backend]
import pkg/[yaml, semver, shakar]

type
  NimInvokation* = object

  Toolchain* {.ignore: ["cachedNimPath"].} = object
    version*: string
    cachedNimPath* {.defaultVal: none(string).}: Option[string]

func getVersion*(toolchain: Toolchain): Version =
  toolchain.version.parseVersion()

proc findNimExe*(toolchain: var Toolchain) {.sideEffect.} =
  if *toolchain.cachedNimPath:
    return

  # Try the Nim executable in the system path
  let nim = findExe("nim")
  if nim.len > 0:
    # Run `nim -v`
    let
      output = execCmdEx(nim & " -v").output

      # Nim Compiler Version 2.0.4 [Linux: amd64]
      # Compiled at 2024-03-28
      # Copyright (c) 2006-2023 by Andreas Rumpf
      #
      # git hash: b47747d31844c6bd9af4322efe55e24fefea544c
      # active boot switches: -d:release
      version = parseVersion(
        output.splitLines()[0].split("Nim Compiler Version ")[1].split(
          " [Linux: amd64]"
        )[0]
      )

    if version == toolchain.getVersion():
      # We found a match.
      toolchain.cachedNimPath = some(nim)
      return

  # TODO: implement a case for this
  assert off, "Unreachable/Not implemented"

proc invoke*(
    toolchain: var Toolchain, command: string
): bool {.
    tags: [
      NimInvokation, ReadEnvEffect, ReadDirEffect, ReadIOEffect, ExecIOEffect,
      RootEffect,
    ],
    discardable,
    sideEffect
.} =
  if *toolchain.cachedNimPath:
    return execCmd(&toolchain.cachedNimPath & ' ' & command) == 0

  toolchain.findNimExe()
  toolchain.invoke(command)

proc compile*(
    toolchain: var Toolchain,
    backend: Backend,
    file: string,
    options: CompilationOptions,
): CompilationStatistics =
  toolchain.findNimExe()
  let payload =
    &toolchain.cachedNimPath & ' ' & ($backend & ' ' & $options & ' ' & file)

  let res = execCmdEx(payload)
  var output = res.output.splitLines()

  for line in output:
    if line.startsWith("CC: "):
      continue # Don't print out the Nim CC debug lines

    echo line

  var stats: CompilationStatistics
  stats.unitsCompiled = uint(res.output.count("CC: "))
  stats.successful = res.exitCode == 0

  move(stats)

func newToolchain*(version: string = NimVersion): Toolchain =
  Toolchain(version: version)
