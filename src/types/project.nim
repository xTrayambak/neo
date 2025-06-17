import std/[streams]
import pkg/[yaml]
import ./[toolchain, backend]

type
  ProjectKind* {.pure.} = enum
    Binary
    Library
    Hybrid

  Project* = object
    name*: string
    backend*: Backend
    license*: string
    kind*: ProjectKind
    binaries*: seq[string]
    toolchain*: Toolchain
    dependencies*: seq[Package]

func newProject*(
    name: string, license: string, kind: ProjectKind, toolchain: Toolchain
): Project {.inline.} =
  Project(name: name, license: license, kind: kind, toolchain: toolchain)

proc loadProject*(
  file: string
): Project {.inline, sideEffect.} =
  var stream = newFileStream(file, fmRead)
  stream.load(result)
