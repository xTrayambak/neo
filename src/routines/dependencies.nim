## Everything about solving a project's dependencies.
## Currently, we use a less-advanced form of the MVS algorithm to handle
## dependency conflicts. The highest version of a dependency is always chosen.
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak at disroot dot org)
import std/[os, options, strutils, tables, tempfiles]
import pkg/[url, results, shakar, semver]
import ../types/[project, package_lists]
import
  ../routines/[package_lists, forge_aliases, git, neo_directory, state],
  ../routines/nimble/declarativeparser,
  ../output

type
  SolverError* = object of CatchableError
  PackageNotFound* = object of SolverError
    package*: string

  UnhandledDownloadMethod* = object of SolverError
    meth*: string

  CloneFailed* = object of SolverError
  CannotInferPackageName* = object of SolverError
  PackageAlreadyDependency* = object of SolverError

  SolverCache = object
    lists*: seq[PackageList]

  Dependency* = ref object
    project*: Project
    pkgRef*: PackageRef
    deps*: seq[Dependency]

  SolvedGraph* = seq[PackageRef]

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

proc getDirectoryForPackage*(name: string, version: string): string =
  let
    version = if version.len < 1: "any" else: version
    dir = getNeoDir() / "packages" / name & '-' & version

  dir

proc findDirectoryForPackage*(name: string): Option[string] =
  for kind, dir in walkDir(getNeoDir() / "packages"):
    if kind != pcDir:
      continue

    if not dir.contains(name & '-'):
      continue

    return some(dir)

proc isDepInstalled*(dep: PackageRef): bool =
  dirExists(getDirectoryForPackage(dep.name, $dep.version))

proc getDepPaths*(graph: SolvedGraph): seq[string] =
  var paths: seq[string]

  for pkgRef in graph:
    let base = getDirectoryForPackage(pkgRef.name, $pkgRef.version)

    if dirExists(base / "src"):
      paths &= base / "src"
    else:
      paths &= base

  move(paths)

proc evaluateProjectDirectory*(
    dest: Option[string]
): tuple[dest: string, deferred: bool] =
  if *dest:
    return (&dest, false)

  (createTempDir("neo-", "-tmpdest"), true)

proc findNimbleFile*(dir: string): Option[string] =
  for kind, path in walkDir(dir):
    if kind != pcFile:
      continue

    if path.endsWith(".nimble"):
      return some(path)

proc inferDestPackageName*(dir: string): string =
  # Firstly, we can check if a .nimble file exists.
  let nimbleFile = findNimbleFile(dir)

  # If so, then we can infer the name off of whatever the value before `.nimble` is.
  if *nimbleFile:
    return splitFile(&nimbleFile).name

  # Else, we'll assume this is a Neo project.
  let neoFilePath = dir / "neo.toml"
  if not fileExists(neoFilePath):
    raise newException(
      CannotInferPackageName,
      "Directory `<blue>" & dir &
        "<reset>` does not seem to be a Nim project. It does not have a Nimble or Neo file.",
    )

  let project = loadProject(neoFilePath)
  project.name

proc downloadPackageFromURL*(
    url: string | URL,
    dest: Option[string] = none(string),
    meth: string = "git",
    pkg: PackageRef,
): string =
  # If this is a URL, we need a temporary place to store the files until we can infer the project's name.
  let (dest, deferred) = evaluateProjectDirectory(dest)
  var extraName: Option[string]
  var finalDest: string = dest

  let
    name = pkg.name
    version = pkg.version
    prettyVersion =
      if pkg.constraint == VerConstraint.None:
        "any"
      else:
        $version

  case meth
  of "git":
    let cloned = gitClone(url, dest)

    if pkg.constraint != VerConstraint.None:
      let checkout = gitCheckout(dest, $version)
      if !checkout:
        # Here, we need to handle a quirk.
        # Some packages made by certain specimen
        # like to tag their versions as 'v<version>'
        # 
        # Examples include araq/libcurl. Why do they do this?
        # I have no clue. We might as well account for their quirky behaviour.
        let quirkyCheckout = gitCheckout(dest, 'v' & $version)

        if !quirkyCheckout:
          # If even that fails, we'll need to use the base version.
          # There's nothing we can do :(
          displayMessage(
            "<yellow>warning<reset>",
            "Using base version; cannot checkout to " & name & '@' & $version,
          )

    if !cloned:
      raise newException(
        CloneFailed,
        "Failed to clone repository for dependency <blue>" & (name) & "<reset>:\n<red>" &
          cloned.error() & "<reset>",
      )

    if deferred:
      let name = inferDestPackageName(dest)
      extraName = some(name)

      finalDest = getDirectoryForPackage(name, $pkg.version)
      moveDir(dest, finalDest)

      addPackageUrlName(url, name)

    displayMessage(
      "<green>Downloaded<reset>",
      (name & '@' & "<green>" & prettyVersion & "<reset>") & (
        if *extraName:
          " (<blue>" & &extraName & "<reset>)"
        else:
          newString(0)
      ),
    )
    return finalDest
  else:
    unhandledDownloadMethod(meth)

proc downloadPackage*(
    entry: PackageListItem, pkg: PackageRef, ignoreCache: bool = false
): string =
  let
    meth = entry.`method`
    dest = getDirectoryForPackage(pkg.name, $pkg.version)

  if dirExists(dest) and not ignoreCache:
    return

  downloadPackageFromURL(entry.url, some(dest), meth, pkg)

proc handleDep*(cache: SolverCache, dep: PackageRef): Dependency =
  # Firstly, try to find the dep in our solver cache.
  # The first list is guaranteed to be the main
  # Nimble package index.
  if dep.name == "nim":
    return

  var url =
    try:
      some(parseUrl(dep.name))
    except URLParsingError:
      none(URL)

  var finalDest: Option[string]
  if !url:
    let package = cache.find(dep.name)

    if !package:
      packageNotFound(dep.name)

    # If the package is found, then we can clone it via Git
    let pkg = &package

    if not isDepInstalled(dep):
      finalDest = some(downloadPackage(pkg, dep))
    else:
      finalDest = some(getDirectoryForPackage(dep.name, $dep.version))
  else:
    # We don't know the package's name, so we need to defer
    # its resolution if it isn't in our known lists either.
    #
    # This way, we don't need to redownload URL-based packages
    # again and again.
    let list = getPackageUrlNames()

    let
      urlObj = &url
      urlString =
        if urlObj.isForgeAlias:
          expandForgeUrl(urlObj)
        else:
          $urlObj

    if urlString in list:
      finalDest = some(getDirectoryForPackage(list[urlString], $dep.version))

    if !finalDest or not dirExists(&finalDest):
      finalDest =
        some(downloadPackageFromURL(urlString, dest = none(string), pkg = dep))

  # Now, we'll load up a Neo project if it exists for that project.
  let
    projectDir = &finalDest
    neoFilePath = projectDir / "neo.toml"
    nimbleFilePath = findNimbleFile(projectDir)

    neoFileExists = fileExists(neoFilePath)
    hasAnyManifest = neoFileExists or *nimbleFilePath

  if not hasAnyManifest:
    displayMessage(
      "<yellow>warning<reset>",
      "<green>" & dep.name &
        "<reset> does not have a `<blue>neo.toml<reset>` or `<blue>.nimble<reset>` file. Its dependencies will not be resolved.",
    )
    return

  if neoFileExists:
    var project = loadProject(neoFilePath)
    var dependency = Dependency(pkgRef: dep)
    for childDep in dependency.project.getPackageRefs():
      dependency.deps &= handleDep(cache, childDep)

    dependency.project = project
    return move(dependency)
  elif *nimbleFilePath:
    # If this package uses Nimble (very likely right now),
    # we need to parse a minimal subset of its dependencies so that
    # we can atleast infer all the packages we require.
    var info = extractRequiresInfo(&nimbleFilePath)
    var dependency = Dependency(pkgRef: dep)
    try:
      dependency.pkgRef.version = parseVersion(info.version)
    except semver.ParseError as exc:
      displayMessage(
        "<yellow>warning<reset>",
        "Cannot parse package's version: <red>" & info.version & "<reset>",
      )

    var project = Project(package: ProjectPackageInfo(name: dep.name))
    for req in info.requires:
      let pref = block:
        let parsed = parsePackageRefExpr(req)
        if parsed.isErr:
          PackageRef(name: req.split(' ')[0])
        else:
          parsed.get()

      dependency.deps &= handleDep(cache, pref)

    dependency.project = project
    return move(dependency)
  else:
    unreachable

proc solveDependencies(list: var seq[PackageRef]) =
  var solved = newSeqOfCap[PackageRef](list.len)

  for dep in list:
    let found = solved.find(dep.name)
    if !found:
      # There's no competing ref.
      solved &= dep
    else:
      let (preExisting, index) = &found

      if preExisting.version < dep.version:
        solved[index] = dep

  list = ensureMove(solved)

proc solveDependencies*(
    project: var Project
): tuple[deps: seq[Dependency], graph: SolvedGraph] =
  # Prime-up the cache.
  # For now, we'll only include
  # the base Nimble package index but
  # we'll eventually add a config option
  # to add other lists.
  var refs = project.getPackageRefs()
  if refs.len < 1:
    return

  var cache: SolverCache
  cache.lists &= &lazilyFetchPackageList(DefaultPackageList)

  var dependencyVec: seq[Dependency]
  var newRefs: seq[PackageRef]

  # Just let the user know that resolution is occurring, in the event that it becomes
  # unbearably slow.
  displayMessage("<green>Resolving<reset>", "dependencies")

  solveDependencies(refs)

  # Now, with the fixed versions, we can go ahead and
  # download all our dependencies
  for dep in refs:
    let dep = handleDep(cache, dep)
    if dep == nil:
      continue

    for child in dep.deps:
      if child == nil:
        continue # FIXME: Please fix this!!!
      newRefs &= child.pkgRef

    dependencyVec &= dep

  refs &= newRefs
  solveDependencies(refs)

  (deps: move(dependencyVec), graph: move(refs))

proc addDependencyForgeAlias*(project: var Project, url: URL) =
  ## This routine checks if an opaque URL is a valid forge alias.
  ##
  ## Forge aliases were a feature I introduced into Nimble, and I liked them
  ## quite a bit (apart from when they broke, because Nimble is a clusterfuck
  ## that breaks if you look at it the wrong way).
  ##
  ## It basically lets you "compress" long Git URLs into small aliases
  ## for common Git forge providers.
  ##
  ## E.g: `https://github.com/xTrayambak/veryfunnypackageyes` is a bit verbose
  ## and gets boiled down to `gh:xTrayambak/veryfunnypackageyes`.
  ##
  ## For self-hostable services, we just redirect to the main instance of that service.
  project.dependencies[$url] = ""

proc addDependency*(project: var Project, package: string): string =
  let url =
    try:
      some(parseUrl(package))
    except URLParsingError:
      none(URL)

  if project.getDependencies().contains(package):
    raise newException(
      PackageAlreadyDependency,
      "The package `<red>" & package & "<reset>` is already a dependency to `<blue>" &
        project.name & "<reset>`!",
    )

  # Download the package's latest version
  # TODO: Ideally, `neo add` should accept versioned inputs
  # (e.g `neo add url@0.1.3`)
  var cache: SolverCache

  if !url:
    # If `package` isn't a URL, we need to prime the solver cache
    # with all the package lists.
    cache.lists &= &lazilyFetchPackageList(DefaultPackageList)

  let dep = handleDep(cache, PackageRef(name: package))
  let version = $dep.pkgRef.version

  if *url:
    project.dependencies[serialize(&url)] = ">= " & version
  else:
    if !cache.find(package):
      packageNotFound(package)

    project.dependencies[package] = ">= " & version

  version
