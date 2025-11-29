## Structures for lockfiles
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak@disroot.org)
import std/tables

type
  LockedPackage* = object
    version*: string
    commit*: string
    url*: string
    checksum*: string

  Lockfile* = object
    version*: uint32
    packages*: Table[string, LockedPackage]
