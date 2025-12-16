type
  CompilationOptions* = object
    outputFile*: string
    extraFlags*: string
    appendPaths*: seq[string]
    version*: string
    passC*: seq[string]
    passL*: seq[string]

  CompilationStatistics* = object
    successful*: bool = false
    unitsCompiled*: uint

func `$`*(opts: CompilationOptions): string =
  var appendPaths = " "
  for path in opts.appendPaths:
    appendPaths &= "--path:" & path & ' '

  var linkerAndCompilerFlags = newStringOfCap(512)
  for passC in opts.passC:
    linkerAndCompilerFlags &= " --passC:\"" & passC & '"'

  for passL in opts.passL:
    linkerAndCompilerFlags &= " --passL:\"" & passL & '"'

  "--noNimblePath --define:NimblePkgVersion=\"" & opts.version &
    "\" --define:NeoPkgVersion=\"" & opts.version & "\"" & " --out:" & opts.outputFile &
    ' ' & opts.extraFlags & move(appendPaths) & ' ' & move(linkerAndCompilerFlags)
