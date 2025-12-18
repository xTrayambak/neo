import std/[options, os, sequtils, strutils, tables]
#!fmt: off
import ../types/[backend, project],
       ./[packref_parser]
#!fmt: on
import pkg/[parsetoml, results, shakar, url]

func getPackageRefs*(project: Project): seq[PackageRef] =
  let deps = project.getDependencies()
  var res = newSeqOfCap[PackageRef](deps.len)

  for dep in deps:
    let pref = parsePackageRefExpr(dep)
    if pref.isErr:
      raise newException(
        CannotResolveDependencies,
        "Cannot resolve dependency `<red>" & dep & "`<reset>: " & $pref.error(),
      )

    res &= pref.get()

  move(res)

proc save*(project: Project, path: string) =
  var buffer = newStringOfCap(1024)

  # We _COULD_ use nim_toml_serialization's TomlWriter
  # but its output is hideous. As a consequence,
  # we must update this every time the manifest format changes.
  buffer &= "[package]\n"
  buffer &= "name = \"$1\"\n" % [project.package.name]
  if *project.package.description:
    buffer &= "description = \"$1\"\n" % [&project.package.description]

  buffer &= "version = \"$1\"\n" % [$project.package.version]
  buffer &= "license = \"$1\"\n" % [project.package.license]
  buffer &= "kind = \"$1\"\n" % [$project.package.kind]
  buffer &= "backend = \"$1\"\n" % [$project.package.backend]

  var bins = newSeq[string](project.package.binaries.len)
  for i, bin in project.package.binaries:
    bins[i] = '"' & bin & '"'

  buffer &= "binaries = [$1]\n" % [move(bins).join(", ")]

  buffer &= "\n[toolchain]\n"
  buffer &= "version = \"$1\"\n" % [project.toolchain.version]

  let depsSize = project.dependencies.len
  var currDep = 0
  buffer &= "\n[dependencies]\n"
  for name, cons in project.dependencies:
    let processedName =
      if tryParseUrl(name).isOk:
        # If `name` is a URL, we need to quote it.
        '"' & name & '"'
      else:
        # Otherwise, we'll copy it as-is.
        name

    buffer &= "$1 = \"$2\"" % [processedName, cons]

    if currDep < depsSize - 1:
      buffer &= "\n"

  if *project.platforms.native:
    let nativeData = &project.platforms.native

    buffer &= "\n[platforms.native]\n"
    buffer &= "include = [" & nativeData.incl.mapIt('"' & it & '"').join(", ") & ']'
    buffer &= "\nlink = [" & nativeData.link.mapIt('"' & it & '"').join(", ") & ']'

  writeFile(path, ensureMove(buffer))

func readProjectKind*(data: string): ProjectKind =
  case data
  of "Binary":
    ProjectKind.Binary
  of "Hybrid":
    ProjectKind.Hybrid
  of "Library":
    ProjectKind.Library
  else:
    raise newException(ValueError, "Invalid project kind: " & data)

proc readPlatformsData(project: var Project, data: TomlValueRef) =
  if "native" in data:
    let cPlatData = data["native"]

    var cPlatformInfo: NativePlatformInfo
    cPlatformInfo.link = (
      if "link" in cPlatData:
        cPlatData["link"].getElems().mapIt(it.getStr())
      else:
        newSeq[string](0)
    )
    cPlatformInfo.incl = (
      if "include" in cPlatData:
        cPlatData["include"].getElems().mapIt(it.getStr())
      else:
        newSeq[string](0)
    )

    project.platforms.native = some(ensureMove(cPlatformInfo))

proc loadProject*(file: string): Project {.sideEffect.} =
  let
    data = parseString(readFile(file))
    packageData = data["package"]
    toolchainData = data["toolchain"]
    depsData = data["dependencies"]

  var project: Project
  project.package.name = packageData["name"].getStr()
  project.package.version = packageData["version"].getStr()
  project.package.license = packageData["license"].getStr()
  project.package.kind = readProjectKind(packageData["kind"].getStr())
  project.package.backend = packageData["backend"].getStr().toBackend()
  project.package.binaries = block:
    let data = packageData["binaries"].getElems()
    var list = newSeqOfCap[string](data.len)

    for bin in data:
      list &= bin.getStr()

    ensureMove(list)

  if "description" in packageData:
    project.package.description = some(packageData["description"].getStr())

  project.toolchain.version = toolchainData["version"].getStr()

  for dep, cons in depsData.getTable():
    project.dependencies[dep] = cons.getStr()

  if "platforms" in data:
    readPlatformsData(project, data["platforms"])

  ensureMove(project)

proc loadProjectInDir*(dir: string): Option[Project] {.inline.} =
  if fileExists(dir / "neo.toml"):
    return some(loadProject(dir / "neo.toml"))

  none(Project)
