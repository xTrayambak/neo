## Everything to do with Neo's internal state.
## This is stored in Neo's private directory as a LevelDB database.
import std/[os, strutils]
import pkg/[leveldb, shakar]
import ./[neo_directory]

type State* = LevelDb

# TODO: On Linux, we should ideally store this state in `~/.local/state/neo`
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

proc setLastIndexSyncTime*(value: float64) =
  state.put("last_index_sync_time", $value)
