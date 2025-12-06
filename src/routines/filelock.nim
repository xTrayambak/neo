## Filelocking abstractions
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak@disroot.org)

# TODO: Mature these abstractions and move them into a package.

when defined(unix):
  import std/posix

  {.push importc, header: "<sys/file.h>".}
  proc flock(fd: int32, op: int32): int32
  let
    LOCK_SH: int32
    LOCK_EX: int32
    LOCK_UN: int32

  {.pop.}
elif defined(windows):
  # NOTE: Not tested.
  import std/winlean

  proc LockFile(
    hFile: DWORD,
    dwFileOffsetLow: DWORD,
    dwFileOffsetHigh: DWORD,
    nNumberOfBytesToLockHigh: DWORD,
    nNumberOfBytesToLockHigh: DWORD,
  ): BOOL {.importc, header: "<fileapi.h>".}

type
  LockError* = object of OSError
  UnlockError* = object of OSError

proc lockFile*(file: File) =
  when defined(unix):
    if flock(cast[int32](file.getOsFileHandle()), LOCK_EX) != 0:
      raise newException(
        LockError,
        "Failed to lock file: " & $strerror(errno) & " (errno " & $errno & ')',
      )
  else:
    # TODO: Implement file locking for Windows.
    discard

proc unlockFile*(file: File) =
  when defined(unix):
    if flock(cast[int32](file.getOsFileHandle()), LOCK_UN) != 0:
      raise newException(
        UnlockError,
        "Failed to unlock file: " & $strerror(errno) & " (errno " & $errno & ')',
      )
  else:
    # TODO: Implement file unlocking for Windows.
    discard
