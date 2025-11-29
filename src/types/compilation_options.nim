type
  CompilationOptions* = object
    outputFile*: string
    extraFlags*: string
    appendPaths*: seq[string]
    version*: string

  CompilationStatistics* = object
    successful*: bool = false
    unitsCompiled*: uint

func `$`*(opts: CompilationOptions): string =
  var appendPaths = " "
  for path in opts.appendPaths:
    appendPaths &= "--path:" & path & ' '

  "--noNimblePath --define:NimblePkgVersion=\"" & opts.version &
    "\" --define:NeoPkgVersion=\"" & opts.version & "\"" & " --out:" & opts.outputFile &
    ' ' & opts.extraFlags & move(appendPaths)
