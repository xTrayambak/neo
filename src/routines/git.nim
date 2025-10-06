## Everything to do with git.
## This module's routines act as wrappers over the Git CLI.
import std/[os, osproc]
import pkg/[results, url]

type
  GitError* = object of OSError
  GitNotInstalled* = object of GitError

proc getGitPath*(): string =
  let path = findExe("git")

  if path.len < 1:
    raise newException(GitNotInstalled, "Git was not found in the PATH")

  path

proc gitClone*(
    url: string | URL, dest: string, depth: uint = 1, branch: string = ""
): Result[void, string] =
  let git = getGitPath()
  if dirExists(dest):
    removeDir(dest)

  let
    payload =
      git & " clone " & $url & ' ' & dest & (
        if branch.len > 0:
          " --branch " & branch.quoteShell
        else: newString(0)
      )
    (output, code) = execCmdEx(payload)

  # Go through each path in the destination and remove
  # the executable (X) bit from every single file, if found.
  # There is no sane excuse for any package to require executables,
  # as they're only meant to provide Nim source files, and maybe
  # some extra non-Nim files but NEVER executable code.
  for path in walkDirRec(dest, yieldFilter = {pcFile}):
    exclFilePermissions(path, {fpUserExec, fpGroupExec, fpOthersExec})

  if code == 0:
    return ok()

  err(output)

proc gitCheckout*(dest: string, branch: string = "master"): Result[void, string] =
  let git = getGitPath()
  let (output, code) = execCmdEx(git & " -C " & dest & " checkout " & branch.quoteShell)

  if code == 0:
    return ok()

  err(output)

proc gitInit*(dir: string): bool =
  let git = getGitPath()
  let (_, code) = execCmdEx(git & " init " & dir)

  code == 0
