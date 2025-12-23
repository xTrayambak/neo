## Everything to do with git.
## This module's routines act as wrappers over the Git CLI.
import std/[os, osproc, options, sequtils, strutils]
import pkg/[results, shakar, url]

type
  GitError* = object of OSError
  GitNotInstalled* = object of GitError

var cachedGitPath {.threadvar, global.}: Option[string]

proc getGitPath*(): string =
  if likely(*cachedGitPath):
    # Fast-path: If we cached the path to the Git binary earlier,
    # we might as well use it. `findExe()` makes a boat load of syscalls,
    # which is.... not good to say the least
    return &cachedGitPath

  # Slow-path: If we haven't cached the path to the Git binary,
  # we must find it (assuming it exists)
  let path = findExe("git")

  if path.len < 1:
    raise newException(GitNotInstalled, "Git was not found in the PATH")

  cachedGitPath = some(path)
  path

proc sanitizeDirectory(dest: string) =
  ## Artifacts downloaded from the internet should be treated _very_
  ## warily. Neo, by default, strips the X bit from all downloaded packages' files,
  ## to ensure that they cannot execute anything. They shouldn't be able to do this
  ## for two distinct, major reasons:
  ##
  ## * Reproducability (the mutations scripts can make is unobservable)
  ## * Security (the user must be aware of everything being executed)

  # Go through each path in the destination and remove
  # the executable (X) bit from every single file, if found.
  # There is no sane excuse for any package to require executables,
  # as they're only meant to provide Nim source files, and maybe
  # some extra non-Nim files but NEVER executable code.
  for path in walkDirRec(dest, yieldFilter = {pcFile}):
    exclFilePermissions(path, {fpUserExec, fpGroupExec, fpOthersExec})

proc gitClone*(
    url: string | URL, dest: string, depth: uint = 1, branch: string = ""
): Result[void, string] =
  let git = getGitPath()
  if dirExists(dest):
    removeDir(dest)

  let payload =
    git & " clone " & $url & ' ' & dest & (
      if branch.len > 0:
        " --branch " & branch.quoteShell
      else: newString(0)
    )

  when not defined(release):
    debugEcho(payload)

  let (output, code) = execCmdEx(payload)

  if code == 0:
    sanitizeDirectory(dest)
    return ok()

  err(output)

proc gitCheckout*(dest: string, branch: string = "master"): Result[void, string] =
  let git = getGitPath()
  let (output, code) = execCmdEx(git & " -C " & dest & " checkout " & branch.quoteShell)

  if code == 0:
    sanitizeDirectory(dest)
    return ok()

  err(output)

proc gitRevParse*(dir: string): Result[string, string] =
  let (output, code) = execCmdEx(getGitPath() & " -C " & dir & " rev-parse HEAD")

  if code != 0:
    return err(output)

  ok(output.strip())

proc gitSyncTags*(dir: string): bool =
  execCmd(getGitPath() & " -C " & dir & " fetch --all --tags") == 0

proc gitPull*(dir: string): bool =
  let res = execCmdEx(getGitPath() & " -C " & dir & " pull --ff-only").exitCode == 0
  sanitizeDirectory(dir)

  res

proc gitListTags*(dir: string): Result[seq[string], string] =
  let (output, code) = execCmdEx(getGitPath() & " -C " & dir & " tag")

  if code != 0:
    return err(output)

  ok(output.split('\n').filterIt(it.len > 0))

proc gitInit*(dir: string): bool =
  let git = getGitPath()
  let (_, code) = execCmdEx(git & " init " & dir)

  code == 0
