## Everything about solving a project's dependencies.
## Currently, we use a very naive recursion-based solver
## but once we introduce version constraints, we'll need a smarter solver,
## similar to how Nimble has a SAT solver.
import std/[os, options, strutils]
import pkg/shakar
import ../types/[project, package_lists]
import
  ../routines/[package_lists, git, neo_directory],
  ../routines/nimble/declarativeparser,
  ../output

type
  SolverError* = object of CatchableError
  PackageNotFound* = object of SolverError
    package*: string

  UnhandledDownloadMethod* = object of SolverError
    meth*: string

  CloneFailed* = object of SolverError

  SolverCache = object
    lists*: seq[PackageList]

  Dependency* = ref object
    project*: Project
    deps*: seq[Dependency]

func packageNotFound*(name: string) {.raises: [PackageNotFound].} =
  var exc = newException(PackageNotFound, "")
  exc.package = name

  raise exc

func unhandledDownloadMethod*(name: string) {.raises: [UnhandledDownloadMethod].} =
  var exc = newException(UnhandledDownloadMethod, "")
  exc.meth = name

  raise exc

proc find(cache: SolverCache, package: string): Option[PackageListItem] {.inline.} =
  for list in cache.lists:
    for pkg in list:
      if pkg.name == package:
        return some(pkg)

proc getDirectoryForPackage*(name: string): string =
  let dir = getNeoDir() / "packages" / name

  dir

proc isDepInstalled*(dep: PackageRef): bool =
  dirExists(getDirectoryForPackage(dep.name))

proc getDepPaths*(deps: seq[Dependency]): seq[string] =
  var paths: seq[string]

  for dep in deps:
    if dep == nil:
      # FIXME: This shouldn't happen. Ever.
      continue

    let base = getDirectoryForPackage(dep.project.name)
    paths &= base

    if dirExists(base / "src"):
      paths &= base / "src"

    paths &= getDepPaths(dep.deps)

  move(paths)

proc downloadPackage*(
    entry: PackageListItem, pkg: PackageRef, ignoreCache: bool = false
) =
  let
    meth = entry.`method`
    dest = getDirectoryForPackage(pkg.name)

  if dirExists(dest) and not ignoreCache:
    return

  case meth
  of "git":
    if not gitClone(entry.url, dest):
      raise newException(
        CloneFailed,
        "Failed to clone repository for dependency <blue>" & pkg.name & "<reset>!",
      )

    displayMessage("<green>Downloaded<reset>", pkg.name)
  else:
    unhandledDownloadMethod(meth)

proc findNimbleFile*(dir: string): Option[string] =
  for kind, path in walkDir(dir):
    if kind != pcFile:
      continue

    if path.endsWith(".nimble"):
      return some(path)

proc handleDep*(cache: SolverCache, root: var Project, dep: PackageRef): Dependency =
  # Firstly, try to find the dep in our solver cache.
  # The first list is guaranteed to be the main
  # Nimble package index.
  if dep.name == "nim":
    return

  let package = cache.find(dep.name)

  if !package:
    packageNotFound(dep.name)

  # If the package is found, then we can
  # clone it via Git
  let pkg = &package

  if not isDepInstalled(dep):
    downloadPackage(pkg, dep)

  # Now, we'll load up a Neo project if it exists for that project.
  # TODO: Load .nimble files as projects too, atleast for now.
  let
    projectDir = getDirectoryForPackage(dep.name)
    neoFilePath = projectDir / "neo.yml"
    nimbleFilePath = findNimbleFile(projectDir)

    neoFileExists = fileExists(neoFilePath)
    hasAnyManifest = neoFileExists or *nimbleFilePath

  if not hasAnyManifest:
    displayMessage(
      "<yellow>warning<reset>",
      "<green>" & dep.name &
        "<reset> does not have a `<blue>neo.yml<reset>` or `<blue>.nimble<reset>` file. Its dependencies will not be resolved.",
    )
    return

  if neoFileExists:
    var project = loadProject(neoFilePath)
    var dependency = Dependency()
    for childDep in dependency.project.getDependencies():
      dependency.deps &= handleDep(cache, project, childDep)

    dependency.project = project
    return move(dependency)
  elif *nimbleFilePath:
    # If this package uses Nimble (very likely right now),
    # we need to parse a minimal subset of its dependencies so that
    # we can atleast infer all the packages we require.
    # FIXME: This can probably be made a little less miserable.
    var info = extractRequiresInfo(&nimbleFilePath)
    var dependency = Dependency()
    var project = Project(name: dep.name)
    for req in info.requires:
      dependency.deps &= handleDep(cache, project, PackageRef(name: req.split(' ')[0]))

    dependency.project = project
    return move(dependency)
  else:
    unreachable

proc solveDependencies*(project: var Project): seq[Dependency] =
  # Prime-up the cache.
  # For now, we'll only include
  # the base Nimble package index but
  # we'll eventually add a config option
  # to add other lists.
  var cache: SolverCache
  cache.lists &= &lazilyFetchPackageList(DefaultPackageList)

  var dependencyVec: seq[Dependency]
  for dep in project.getDependencies():
    let dep = handleDep(cache, project, dep)
    if dep == nil:
      continue

    dependencyVec &= dep

  move(dependencyVec)
