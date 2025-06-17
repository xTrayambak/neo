## Everything to do with the Neo (~/.local/share/neo) directory
## Everything (and I mean it when I say everything) is compressed here, just to be conservative.
import std/[os]
import pkg/[zippy, curly, shakar]
import ../[argparser]

const
  OfficialPackageLists* = [
    "https://nim-lang.org/nimble/packages.json"
  ]

when defined(linux):
  proc getDataDir(): string =
    getHomeDir() / ".local" / "share"

proc getNeoDir*(input: Input = default(Input)): string =
  if (let flag = input.flag("neo-directory-override"); *flag):
    &flag
  else:
    when defined(linux):
      # We can respect XDG base directories here, just to be nice.
      let dir = getDataDir()
      discard existsOrCreateDir(dir)

      dir / "neo"
    else:
      getHomeDir() / ".neo"

proc populateNeoDir*(directory: string) =
  ## "Populate" the Neo directory with everything needed for
  ## it to function as intended.
  
  discard existsOrCreateDir(directory / "indices")

proc initNeoDir*(input: Input = default(Input)) =
  let directory = getNeoDir(input)
  populateNeoDir(directory)
