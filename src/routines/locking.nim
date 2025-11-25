## Everything to do with lockfiles (`neo.lock`)
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak@disroot.org)
import std/[os, tables, json]
#!fmt: off
import ../output,
       ../types/[lockfile, project],
       ./[checksumming, dependencies]
#!fmt: on
import pkg/[url, shakar, semver, pretty]

proc lockfileExists*(dir: string): bool =
  fileExists(dir / "neo.lock")

proc emitFlattenedDeps(project: Project, lock: var Lockfile, pathsBuffer: out string) =
  let (_, graph) = solveDependencies(project)
  let cache = initSolverCache()

  pathsBuffer = newStringOfCap(512)
  pathsBuffer &= "--noNimblePath"

  for node in graph:
    var lockedPkg: LockedPackage

    lockedPkg.checksum = computeChecksum(node.name, $node.version)
    lockedPkg.version = $node.version
    lockedPkg.url = serialize(&getDownloadURL(cache, node))

    lock.packages[node.name] = ensureMove(lockedPkg)

  for path in getDepPaths(graph):
    pathsBuffer &= "\n--path:\"" & path & '"'

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

  return true
