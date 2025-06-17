import std/options
import ../output
import ../types/package_lists
import pkg/[curly, jsony]

const
  ## These lists belong to the Nimble packages index.
  InternalPackageLists* = [
    "https://raw.githubusercontent.com/nim-lang/packages/master/packages.json",
    "https://nim-lang.org/nimble/packages.json"
  ]

  DefaultPackageList* = InternalPackageLists[0]

var packageListFetchingPool = newCurly()

proc readPackageList*(response: Response): Option[PackageList] =
  if response.code != 200:
    error "Got non-successful response code (<red>" & $response.code & "<reset>) whilst fetching package list from <green>" & response.url & "<reset>"
    return

  let content = response.body

  try:
    return some(
      fromJson(content, PackageList)
    )
  except JsonError as exc:
    error "Could not parse package list: " & exc.msg

proc fetchPackageList*(url: string): Option[PackageList] =
  displayMessage("<blue>fetching<reset>", "Nim package index")
  let response = packageListFetchingPool.get(url)

  response.readPackageList()

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
      error "Got internal libcURL error whilst fetching package list (<blue>" & urls[pos] & "<reset>): <red>" & error & "<reset>"

    inc pos

  move(lists)
