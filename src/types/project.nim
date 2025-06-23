import std/[streams]
import pkg/[yaml]
import ./[toolchain, backend]

type
  ProjectKind* {.pure.} = enum
    Binary
    Library
    Hybrid

  PackageRef* = object
    ## A package ref is an unresolved reference to a package.
    ## It must be solved by Neo at buildtime for compilation
    ## to commence.
    name*: string

  Project* = object
    name*: string
    backend*: Backend
    license*: string
    kind*: ProjectKind
    binaries*: seq[string]
    toolchain*: Toolchain
    dependencies*: seq[string]

    formatter* {.defaultVal: "nimpretty".}: string

func getDependencies*(project: Project): seq[PackageRef] =
  var res = newSeq[PackageRef](project.dependencies.len)

  for i, dep in project.dependencies:
    res[i] = PackageRef(name: dep)

  move(res)

func newProject*(
    name: string, license: string, kind: ProjectKind, toolchain: Toolchain
): Project {.inline.} =
  Project(name: name, license: license, kind: kind, toolchain: toolchain)

proc save*(project: Project, path: string) =
  var stream = newFileStream(path, fmWrite)
  Dumper().dump(project, stream)
  stream.close()

proc loadProject*(file: string): Project {.inline, sideEffect.} =
  var stream = newFileStream(file, fmRead)
  stream.load(result)
