## Everything to do with git.
## This module's routines act as wrappers over the Git CLI.
import std/[os, osproc]

type
  GitError* = object of OSError
  GitNotInstalled* = object of GitError

proc getGitPath*(): string =
  let path = findExe("git")

  if path.len < 1:
    raise newException(GitNotInstalled, "Git was not found in the PATH")

  path

proc gitClone*(url: string, dest: string, depth: uint = 1): bool =
  let git = getGitPath()
  if dirExists(dest):
    removeDir(dest)

  let (output, code) = execCmdEx(
    git & " clone " & url & ' ' & dest &
    " --depth=" & $depth
  )

  code == 0
