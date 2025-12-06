## Everything to do with Neo's internal state.
## This is stored in Neo's private directory as a LevelDB database.
import std/[json, os, options, strutils, tables]
import pkg/[shakar, jsony, url]
import ./[neo_directory]

type
  StateObj* = object
    version*: uint32 = 0 ## Will be useful later.

    package_url_resolved_names*: Table[string, string]
    last_index_sync_time*: float64

  StateError* = object of ValueError
  StateParseError* = object of StateError

  State* = ref StateObj

proc `=destroy`*(state: StateObj) =
  writeFile(getNeoDir() / "state.json", toJson(state))

proc getNeoState*(): State =
  let dir = getNeoDir()
  discard existsOrCreateDir(dir)

  let statePath = dir / "state.json"
  if not fileExists(statePath):
    writeFile(statePath, toJson(default(StateObj)))

  var state = State()
  let parsed = fromJson(readFile(dir / "state.json"))

  for key, value in parsed["package_url_resolved_names"].getFields():
    state.packageUrlResolvedNames[key] = getStr(value)

  state.lastIndexSyncTime = parsed["last_index_sync_time"].getFloat()

  return state

proc addPackageUrlName*(state: State, url: string | URL, name: string) =
  # Add a package's name to a list as well as the URL it
  # was resolved from.

  state.packageUrlResolvedNames[
    when url is string:
      url
    elif url is URL:
      serialize(url)
  ] = name
