type
  CompilationOptions* = object
    outputFile*: string
    extraFlags*: string

  CompilationStatistics* = object
    successful*: bool
    unitsCompiled*: uint

func `$`*(opts: CompilationOptions): string =
  "--out:" & opts.outputFile & ' ' & opts.extraFlags
