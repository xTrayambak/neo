## Everything to do with lockfiles (`neo.lock`)
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak@disroot.org)
import std/[os, osproc, options, strutils, tables, json]
#!fmt: off
import ../output,
       ../types/[lockfile, project],
       ./[checksumming, dependencies, git]
#!fmt: on
import pkg/[jsony, url, results, shakar, semver, pretty]

type
  LockError* = object of CatchableError
  CannotComputeCommitHash* = object of LockError

  ValidationError* = object of LockError
  CommitMismatch* = object of ValidationError
  ChecksumMismatch* = object of ValidationError

proc lockfileExists*(dir: string): bool =
  fileExists(dir / "neo.lock")

proc generateLockedDepPaths*(graph: SolvedGraph): string =
  var paths = newStringOfCap(512)
  paths &= "--noNimblePath\n"

  for path in getDepPaths(graph):
    paths &= "\n--path:\"" & path & '"'

  ensureMove(paths)

proc generateLockedDepPaths*(project: Project): string {.inline.} =
  generateLockedDepPaths(solveDependencies(project).graph)

proc getCommitHash*(name: string, version: string): Result[string, string] =
  gitRevParse(getDirectoryForPackage(name, version))

proc emitFlattenedDeps(project: Project, lock: var Lockfile, pathsBuffer: out string) =
  let (_, graph) = solveDependencies(project)
  let cache = initSolverCache()

  for node in graph:
    var lockedPkg: LockedPackage

    lockedPkg.checksum = computeChecksum(node.name, $node.version)
    lockedPkg.version = $node.version

    let commitHash = getCommitHash(node.name, $node.version)
    if !commitHash:
      raise newException(CannotComputeCommitHash, node.name)

    lockedPkg.commit = &commitHash
    lockedPkg.url = serialize(&getDownloadURL(cache, node))

    lock.packages[node.name] = ensureMove(lockedPkg)

  pathsBuffer = generateLockedDepPaths(graph)

proc loadLockFile*(dir: string): Option[Lockfile] =
  if not lockfileExists(dir):
    return none(Lockfile)

  try:
    return some(fromJson(readFile(dir / "neo.lock"), Lockfile))
  except jsony.JsonError:
    return none(Lockfile)

proc validateNodeIntegrity*(
    cache: SolverCache, locked: LockedPackage, node: PackageRef
) =
  let dir = getDirectoryForPackage(node.name, $node.version)
  if not dirExists(dir):
    # The package is not installed, try installing it.
    discard downloadPackageFromURL(
      url = &getDownloadURL(cache, node), dest = some(dir), pkg = node
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

proc buildGraphFromLock*(lockfile: Lockfile): SolvedGraph =
  var graph: SolvedGraph
  let cache = initSolverCache()

  for name, data in lockfile.packages:
    let pkgRef = PackageRef(
      name: name,
      version: parseVersion(data.version),
      hash: some(data.commit),
      constraint: VerConstraint.None,
    )
    validateNodeIntegrity(cache, data, pkgRef)
    graph &= pkgRef

  ensureMove(graph)

proc constructLockFileStruct(
    project: Project
): tuple[lockfile: Lockfile, pathsBuffer: string] =
  var
    lock: Lockfile
    pathsBuffer: string

  lock.version = 0'u32

  emitFlattenedDeps(project, lock, pathsBuffer)

  (lockfile: ensureMove(lock), pathsBuffer: ensureMove(pathsBuffer))

proc generateLockFile*(dir: string, lockfilePath: string): bool =
  let projectOpt = loadProjectInDir(dir)
  if !projectOpt:
    error "Cannot generate lockfile; no <yellow>neo.toml<reset> was found!"
    return false

  let project = &projectOpt
  displayMessage(
    "<yellow>Locking<reset>", "dependencies for <green>" & project.name & "<reset>"
  )

  let (lockfile, pathsBuffer) = constructLockFileStruct(project)
  try:
    #!fmt: off
    writeFile(dir / lockfilePath, pretty(%* lockfile))
    #!fmt: on

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
