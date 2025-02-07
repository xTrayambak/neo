## Everything to do with the Neo (~/.neo) directory
## Everything (and I mean it when I say everything) is compressed here, just to be conservative.
import std/[os]
import pkg/[zippy, curly]
import ./package_lists
import ../[argparser, sugar]

const
  OfficialPackageLists* = [
    "https://nim-lang.org/nimble/packages.json"
  ]

func getNeoDir*(input: Input): string =
  if (let flag = input.flag("neo-directory-override"); *flag):
    &flag
  else:
    getHomeDir() / ".neo"

proc populateNeoDir*(directory: string) =
  ## "Populate" the Neo directory with everything needed for
  ## it to function as intended. Currently, this includes:
  ## - the official package list
  
  # Get the official package list
  let officialPackageList = fetchPackageLists(OfficialPackageLists)

proc initNeoDir*(input: Input) =
  let directory = getNeoDir(input)
  
  if not existsOrCreateDir(directory):
    populateNeoDir(directory)
