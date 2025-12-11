## Everything to do with Neo's internal state.
## This is stored in Neo's private directory as a LevelDB database.
import std/[json, os, options, tables]
import pkg/[jsony, url]
import ./[neo_directory, filelock]

proc dumpHook(s: var string, fd: File) =
  # FIXME: Stupid hack
  s &= "null"

type
  StateObj* = object
    version*: uint32 = 0 ## Will be useful later.

    package_url_resolved_names*: Table[string, string]
    last_index_sync_time*: float64

    fd: File # the state.json.lock handle

  StateError* = object of ValueError
  StateParseError* = object of StateError

  State* = ref StateObj

proc saveState*(state: StateObj) =
  writeFile(getNeoDir() / "state.json", toJson(state))
  if state.fd != nil:
    unlockFile(state.fd)

proc `=destroy`*(
    state: StateObj
) {.raises: [UnlockError, IOError, KeyError, OSError].} =
  saveState(state)

proc getNeoState*(): State =
  let dir = getNeoDir()
  discard existsOrCreateDir(dir)

  let statePath = dir / "state.json"
  if not fileExists(statePath):
    writeFile(statePath, toJson(default(StateObj)))

  var state = State(fd: open(statePath & ".lock", fmWrite))
  lockFile(state.fd)

  let parsed = fromJson(readFile(statePath))

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
