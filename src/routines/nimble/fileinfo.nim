import std/tables

type NimbleFileInfo* = object
  nimbleFile*: string
  requires*: seq[string]
  srcDir*: string
  version*: string
  description*: string
  license*: string
  backend*: string
  tasks*: seq[(string, string)]
  features*: Table[string, seq[string]]
  bin*: Table[string, string]
  hasInstallHooks*: bool
  hasErrors*: bool
  hasInstallExt*: bool
  nestedRequires*: bool
    #if true, the requires section contains nested requires meaning that the package is incorrectly defined
  declarativeParserErrorLines*: seq[string]
  #In vnext this means that we will need to re-run sat after selecting nim to get the correct requires
