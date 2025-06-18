## Everything about solving a project's dependencies.
## Currently, we use a very naive recursion-based solver
## but once we introduce version constraints, we'll need a smarter solver,
## similar to how Nimble has a SAT solver.
import std/[os, options]
import pkg/shakar
import ../types/[
  project, package_lists
]
import ../routines/[
  package_lists,
  git,
  neo_directory
]
import ../output

type
  SolverError* = object of CatchableError
  PackageNotFound* = object of SolverError
    package*: string

  UnhandledDownloadMethod* = object of SolverError
    meth*: string

  CloneFailed* = object of SolverError

  SolverCache = object
    lists*: seq[PackageList]

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

proc handleDep*(cache: SolverCache, root: var Project, dep: PackageRef) =
  # Firstly, try to find the dep in our solver cache.
  # The first list is guaranteed to be the main
  # Nimble package index.
  let package = cache.find(dep.name)

  if !package:
    packageNotFound(dep.name)
  
  # If the package is found, then we can
  # clone it via Git
  let
    pkg = &package
    meth = pkg.`method`
    dest = getDirectoryForPackage(dep.name)
  
  case meth
  of "git":
    if not gitClone(pkg.url, dest):
      raise newException(
        CloneFailed, 
        "Failed to clone repository for dependency <blue>" &
        dep.name & "<reset>!"
      )

    displayMessage("<green>Downloaded<reset>", dep.name)
  else:
    unhandledDownloadMethod(meth)

proc solveDependencies*(project: var Project) =
  # Prime-up the cache.
  # For now, we'll only include
  # the base Nimble package index but
  # we'll eventually add a config option
  # to add other lists.
  var cache: SolverCache
  cache.lists &=
    &lazilyFetchPackageList(DefaultPackageList)

  for dep in project.getDependencies():
    handleDep(cache, project, dep)
