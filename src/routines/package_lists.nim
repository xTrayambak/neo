import std/[os, times, options, base64]
import ../output
import ../types/package_lists, ./[state, neo_directory]
import pkg/[curly, jsony, shakar]

const
  ## These lists belong to the Nimble packages index.
  InternalPackageLists* = [
    "https://raw.githubusercontent.com/nim-lang/packages/master/packages.json",
    "https://nim-lang.org/nimble/packages.json",
  ]

  DefaultPackageList* = InternalPackageLists[0]

var packageListFetchingPool = newCurly()

proc readPackageList*(response: Response): Option[PackageList] =
  if response.code != 200:
    error "Got non-successful response code (<red>" & $response.code &
      "<reset>) whilst fetching package list from <green>" & response.url & "<reset>"
    return

  let content = response.body

  try:
    return some(fromJson(content, PackageList))
  except JsonError as exc:
    error "Could not parse package list: " & exc.msg

proc cachePackageList*(url: string, list: string) =
  let filename = base64.encode(url, safe = true)

  initNeoDir()
  let fullPath = getNeoDir() / "indices" / filename & ".json"

  writeFile(fullPath, list)

proc fetchPackageList*(url: string): Option[PackageList] =
  displayMessage(
    "<blue>fetching<reset>",
    if InternalPackageLists.contains(url):
      "Nim package index"
    else:
      "Package index from <green>" & url & "<reset>",
  )
  let response = packageListFetchingPool.get(url)

  let list = response.readPackageList()
  if *list:
    cachePackageList(url, response.body)

  list

proc getCachedPackageList*(url: string): Option[PackageList] =
  let filename = base64.encode(url, safe = true)

  initNeoDir()
  let fullPath = getNeoDir() / "indices" / filename & ".json"

  if fileExists(fullPath):
    try:
      return some(fromJson(readFile(fullPath), PackageList))
    except OSError as exc:
      error "Failed to read cached package index: " & exc.msg
    except JsonError as exc:
      error "Failed to parse cached package index: " & exc.msg

proc lazilyFetchPackageList*(state: State, url: string): Option[PackageList] =
  let
    currTime = epochTime()
    lastSync = state.lastIndexSyncTime

  # Our current threshold is 4 hours (14400 seconds)
  # TODO: Make this threshold customizable.
  if (currTime - lastSync) < 14400:
    let cached = getCachedPackageList(url)

    if *cached:
      return cached

  state.lastIndexSyncTime = currTime
  fetchPackageList(url)

proc fetchPackageLists*(urls: openArray[string]): seq[Option[PackageList]] =
  ## Fetch package lists from multiple URLs in parallel.
  ## NOTE: The output of this function will always be in the same order as the URLs provided in `urls`.
  displayMessage("<blue>fetching<reset>", $urls.len & " package list(s) in parallel")

  var batch: RequestBatch
  for url in urls:
    batch.get(url)

  var
    lists = newSeq[Option[PackageList]](urls.len)
    pos: uint16

  for (response, error) in packageListFetchingPool.makeRequests(batch):
    if error.len < 1:
      lists[pos] = readPackageList(response)
    else:
      error "Got internal libcURL error whilst fetching package list (<blue>" & urls[
        pos
      ] & "<reset>): <red>" & error & "<reset>"

    inc pos

  move(lists)
