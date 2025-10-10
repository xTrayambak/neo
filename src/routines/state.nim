## Everything to do with Neo's internal state.
## This is stored in Neo's private directory as a LevelDB database.
import std/[os, strutils, tables]
import pkg/[leveldb, shakar, jsony, url]
import ./[neo_directory]

type State* = LevelDb

proc getNeoState*(): State =
  let dir = getNeoDir()
  discard existsOrCreateDir(dir)

  leveldb.open(dir / "state")

var state {.threadvar.}: State

proc initNeoState*() =
  state = getNeoState()

proc saveNeoState*() =
  assert(state != nil)

  state.close()

# State-based routines
proc getLastIndexSyncTime*(): float64 =
  let value = state.get("last_index_sync_time")
  if !value:
    return 0'f64 # Force a resync as we've just init'd our state, probably.

  parseFloat(&value)

proc getPackageUrlNames*(): Table[string, string] =
  ## Get a list of URL packages installed as well as their resolved names.
  # E.g, this is what it'd look in a likely case:
  # {
  #  "https://github.com/ferus-web/sanchar": "sanchar",
  #  "https://github.com/xTrayambak/librng": "librng"
  # }
  let value = state.get("package_url_resolved_names")
  if !value:
    return

  fromJson(&value, Table[string, string])

proc addPackageUrlName*(url: string | URL, name: string) =
  # Add a package's name to a list as well as the URL it
  # was resolved from.
  var list = getPackageUrlNames()
  list[$url] = name

  state.put("package_url_resolved_names", toJson(move(list)))

proc setLastIndexSyncTime*(value: float64) =
  state.put("last_index_sync_time", $value)

export LevelDbException
