type
  CompilationOptions* = object
    outputFile*: string
    extraFlags*: string
    appendPaths*: seq[string]

  CompilationStatistics* = object
    successful*: bool = false
    unitsCompiled*: uint

func `$`*(opts: CompilationOptions): string =
  var appendPaths = " "
  for path in opts.appendPaths:
    appendPaths &= "--path:" & path & ' '

  "--out:" & opts.outputFile & ' ' & opts.extraFlags & move(appendPaths)
