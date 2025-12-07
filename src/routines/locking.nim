## Everything to do with lockfiles (`neo.lock`)
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak@disroot.org)
import std/[os, options, tables, json]
#!fmt: off
import ../output,
       ../types/[lockfile, project],
       ./[checksumming, dependencies, git, state]
#!fmt: on
import pkg/[jsony, url, results, shakar, semver]

type
  LockError* = object of CatchableError
  CannotComputeCommitHash* = object of LockError

  ValidationError* = object of LockError
  CommitMismatch* = object of ValidationError
  ChecksumMismatch* = object of ValidationError

proc lockfileExists*(dir: string): bool =
  fileExists(dir / "neo.lock")

proc generateLockedDepPaths*(state: State, graph: SolvedGraph): string =
  var paths = newStringOfCap(512)
  paths &= "--noNimblePath\n"

  for path in getDepPaths(graph, state):
    paths &= "\n--path:\"" & path & '"'

  ensureMove(paths)

proc generateLockedDepPaths*(project: Project, state: State): string {.inline.} =
  generateLockedDepPaths(state, solveDependencies(project, state).graph)

proc getCommitHash*(
    name: string, version: string, state: State
): Result[string, string] =
  gitRevParse(getDirectoryForPackage(state, name, version))

proc buildLockedPackagesFromGraph*(
    graph: SolvedGraph, cache: SolverCache, state: State
): Table[string, LockedPackage] =
  var packages: Table[string, LockedPackage]

  for node in graph:
    var lockedPkg: LockedPackage

    lockedPkg.checksum = computeChecksum(state, node.name, $node.version)
    lockedPkg.version = $node.version

    let commitHash = getCommitHash(node.name, $node.version, state)
    if !commitHash:
      raise newException(CannotComputeCommitHash, node.name)

    lockedPkg.commit = &commitHash
    lockedPkg.url = serialize(&getDownloadURL(cache, node))

    packages[node.name] = ensureMove(lockedPkg)

  ensureMove(packages)

proc emitFlattenedDeps(
    project: Project,
    lock: var Lockfile,
    pathsBuffer: out string,
    graph: SolvedGraph,
    cache: SolverCache,
    state: State,
) {.inline.} =
  lock.packages = buildLockedPackagesFromGraph(graph, cache, state)
  pathsBuffer = generateLockedDepPaths(state, graph)

proc loadLockFile*(dir: string): Option[Lockfile] =
  if not lockfileExists(dir):
    return none(Lockfile)

  try:
    return some(fromJson(readFile(dir / "neo.lock"), Lockfile))
  except jsony.JsonError:
    return none(Lockfile)

proc validateNodeIntegrity*(
    cache: SolverCache, locked: LockedPackage, node: PackageRef, state: State
) =
  let dir = getDirectoryForPackage(state, node.name, $node.version)
  if not dirExists(dir):
    # The package is not installed, try installing it.
    discard downloadPackageFromURL(
      url = &getDownloadURL(cache, node), dest = some(dir), pkg = node, state = state
    )

  # First, check if the SHA256 checksum matches what the lockfile expects.
  let checksum = computeChecksum(dir)

  if checksum != locked.checksum:
    raise newException(
      ChecksumMismatch,
      "failed to verify the integrity of <yellow>" & node.name & "<reset>@<blue>" &
        $node.version & "<reset>\n" & "  <red>expected<reset>: " & locked.checksum &
        "\n  <red>found<reset>: " & checksum,
    )

  let revision = gitRevParse(dir)
  if !revision:
    raise newException(
      CannotComputeCommitHash,
      "Failed to get Git revision of package <red>" & node.name & "<reset>: " &
        revision.error(),
    )

  if &revision != locked.commit:
    # If we're not on the correct commit, try to forcefully get to it.
    if !gitCheckout(&revision):
      # If even that fails, throw an error.
      raise newException(
        CommitMismatch,
        "failed to check-out to the expected revision of <yellow>" & node.name &
          "<reset>@<blue>" & $node.version & "<reset>\n" & "  <red>expected<reset>: " &
          locked.commit & "\n  <red>stuck at<reset>: " & &revision,
      )

proc buildGraphFromLock*(lockfile: Lockfile, state: State): SolvedGraph =
  var graph: SolvedGraph
  let cache = initSolverCache(state)

  for name, data in lockfile.packages:
    let pkgRef = PackageRef(
      name: name,
      version: parseVersion(data.version),
      hash: some(data.commit),
      constraint: VerConstraint.Equal,
    )
    validateNodeIntegrity(cache, data, pkgRef, state)
    graph &= pkgRef

  ensureMove(graph)

proc constructLockFileStruct(
    project: Project, state: State
): tuple[lockfile: Lockfile, pathsBuffer: string] =
  var
    lock: Lockfile
    pathsBuffer: string

  lock.version = 0'u32

  let (_, graph) = solveDependencies(project, state)
  let cache = initSolverCache(state)

  emitFlattenedDeps(project, lock, pathsBuffer, graph, cache, state)

  (lockfile: ensureMove(lock), pathsBuffer: ensureMove(pathsBuffer))

proc emitLockfile*(lockfile: Lockfile, path: string) {.inline.} =
  writeFile(path, pretty(%*lockfile))

proc generateLockFile*(dir: string, lockfilePath: string, state: State): bool =
  let projectOpt = loadProjectInDir(dir)
  if !projectOpt:
    error "Cannot generate lockfile; no <yellow>neo.toml<reset> was found!"
    return false

  let project = &projectOpt
  displayMessage(
    "<yellow>Locking<reset>", "dependencies for <green>" & project.name & "<reset>"
  )

  let (lockfile, pathsBuffer) = constructLockFileStruct(project, state)
  try:
    emitLockfile(lockfile, dir / lockfilePath)

    writeFile(dir / "neo.paths", pathsBuffer)
    writeFile(
      dir / "config.nims",
      """
## Neo lockfile config

--noNimblePath
when withDir(thisDir(), system.fileExists("neo.paths")):
  include "neo.paths"

## End of Neo lockfile config
    """,
    )
  except IOError, OSError:
    error "Cannot write files: " & getCurrentException().msg
    return false
  except CannotComputeCommitHash as exc:
    error "Cannot compute commit hash of dependency <red>" & exc.msg & "<reset>!"
    return false

  return true
