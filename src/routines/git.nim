## Everything to do with git.
## This module's routines act as wrappers over the Git CLI.
import std/[os, osproc]
import pkg/sanchar/parse/url

type
  GitError* = object of OSError
  GitNotInstalled* = object of GitError

proc getGitPath*(): string =
  let path = findExe("git")

  if path.len < 1:
    raise newException(GitNotInstalled, "Git was not found in the PATH")

  path

proc gitClone*(url: string | URL, dest: string, depth: uint = 1): bool =
  let git = getGitPath()
  if dirExists(dest):
    removeDir(dest)

  let
    payload = git & " clone " & $url & ' ' & dest & " --depth=" & $depth
    (_, code) = execCmdEx(payload)

  code == 0

proc gitInit*(dir: string): bool =
  let git = getGitPath()
  let (_, code) = execCmdEx(git & " init " & dir)

  code == 0
