## Neo - the new package manager for Nim
import std/[os, osproc, tables, sequtils, strutils]
import pkg/[semver, shakar, floof, pretty]
import ./[argparser, output]
import ./types/[project, toolchain, backend, compilation_options, package_lists]
import ./routines/[initialize, package_lists, state, dependencies, neo_directory]

const
  NeoVersion* {.strdefine: "NimblePkgVersion".} = "0.1.0"

  # For the sake of brevity, only show the first 15 closest matches
  # when searching for packages.
  MaxMatchesDefault* {.intdefine: "NeoSearchMaxMatchesDefault".} = 15

proc initializePackageCommand(args: Input) {.noReturn.} =
  if args.arguments.len < 1:
    error "<green>neo init<reset> expects 1 argument, got 0"
    quit(QuitFailure)

  setControlCHook(
    proc() {.noconv.} =
      error "<red>interrupted by user<reset>"
      quit(QuitFailure)
  )

  let
    name = args.arguments[0]
    kind = askQuestion("Project Type", ["Binary", "Library", "Hybrid"], 0)
    license = askQuestion("License (Optional)")
    toolchainVersion =
      askQuestion("Nim Toolchain Version", NimVersion)

    project = newProject(
      name = name,
      kind = ProjectKind(kind),
      license = license,
      toolchain = newToolchain(toolchainVersion),
    )

  initializeProject(project)

  quit(QuitSuccess)

proc buildPackageCommand(args: Input) {.noReturn.} =
  var directory = "src"
  let sourceFile =
    if args.arguments.len > 0:
      directory = args.arguments[0] / "src"
      args.arguments[0] / "neo.yml"
    else:
      getCurrentDir() / "neo.yml"

  if not fileExists(sourceFile):
    error "Cannot find Neo build file at: <red>" & sourceFile & "<reset>"
    quit(QuitFailure)

  var project = loadProject(sourceFile)
  
  if project.binaries.len < 1:
    error "This project has no compilable binaries."
    quit(QuitFailure)

  var toolchain = newToolchain(version = project.toolchain.version)

  var extraFlags: string
  for flag, value in args.flags:
    extraFlags &= "--" & flag & ':' & value

  for switch in args.switches:
    extraFlags &= "--" & switch
  
  var deps: seq[Dependency]
  try:
    deps = project.solveDependencies()
  except CatchableError as exc:
    error "Failed to solve dependencies: " & exc.msg
    quit(1)

  for binFile in project.binaries:
    displayMessage("<yellow>compiling<reset>", "<green>" & binFile & "<reset> using the <blue>" & project.backend.toHumanString() & "<reset> backend")
    let stats = toolchain.compile(project.backend, directory / binFile & ".nim", CompilationOptions(outputFile: binFile, extraFlags: extraFlags, appendPaths: getDepPaths(deps)))

    if stats.successful:
      displayMessage("<green>" & binFile & "<reset>", "was built successfully, with <green>" & $stats.unitsCompiled & "<reset> unit(s) compiled.")
    else:
      displayMessage("<red>" & binFile & "<reset>", "has failed to compile. Check the error above for more information.")
      break # TODO: add a flag called `--ignore-build-failure` which doesn't cause the entire build process to stop after an error

proc runPackageCommand(args: Input) =
  var 
    directory = "src"
    firstArgumentUsed = false

  let sourceFile =
    if args.arguments.len > 0:
      directory = args.arguments[0] / "src"
      firstArgumentUsed = true
      args.arguments[0] / "neo.yml"
    else:
      getCurrentDir() / "neo.yml"

  if not fileExists(sourceFile):
    error "Cannot find Neo build file at: <red>" & sourceFile & "<reset>"
    quit(QuitFailure)

  var project = loadProject(sourceFile)
  let
    binaryName = block:
      if project.binaries.len > 1:
        let pos =
          if firstArgumentUsed: 1
          else: 0

        if args.arguments.len < pos:
          error "Expected binary file to run. Choose between the following:"
          for bin in project.binaries:
            displayMessage("", "<green>" & bin & "<reset>")

          quit(QuitFailure)

        args.arguments[pos]
      else:
        project.binaries[0]

  var toolchain = newToolchain(project.toolchain.version)

  var deps: seq[Dependency]
  try:
    deps = project.solveDependencies()
  except CatchableError as exc:
    error "Failed to solve dependencies: " & exc.msg
    quit(1)

  displayMessage("<yellow>compiling<reset>", "<green>" & binaryName & "<reset> using the <blue>" & project.backend.toHumanString() & "<reset> backend")
  
  let stats = toolchain.compile(project.backend, directory / binaryName & ".nim", CompilationOptions(outputFile: binaryName, appendPaths: getDepPaths(deps)))
  if stats.successful:
    displayMessage("<green>" & binaryName & "<reset>", "was built successfully, with <green>" & $stats.unitsCompiled & "<reset> unit(s) compiled.")

    var extraFlags: string
    for flag, value in args.flags:
      extraFlags &= "--" & flag & ':' & value

    for switch in args.switches:
      extraFlags &= "--" & switch
    
    discard execCmd("./" & binaryName & ' ' & extraFlags)
  else:
    displayMessage("<red>" & binaryName & "<reset>", "has failed to compile. Check the error above for more information.")

proc searchPackageCommand(args: Input) =
  if args.arguments.len < 1:
    displayMessage("<red>error<reset>", "This command expects one argument. It was provided none.")
    quit(1)

  let package = args.arguments[0]
  let list = lazilyFetchPackageList(DefaultPackageList)
  
  if !list:
    # TODO: better errors
    displayMessage("<red>error<reset>", "Failed to fetch package index!")
    quit(1)
  
  let index = &list

  stdout.write('\n')

  var limit = MaxMatchesDefault

  if args.flagAsInt("limit") ?= customLimit:
    limit = customLimit
  
  let pkgs = block:
    var res = newSeq[string](index.len)
    for i, pkg in index:
      res[i] = pkg.name

    move(res)

  let results = search(package, pkgs)

  for i, pkg in results:
    # OPTIMIZE: We're currently doing two lookups per match. We should ideally do one.
    let package = &index.find(pkg.text)

    if i > limit - 1:
      continue

    displayMessage("<green>" & pkg.text & "<reset>", package.description)
  
  if limit < results.len:
    stdout.write('\n')
    displayMessage("<blue>...<reset>", "and <green>" & $(results.len - limit) & "<reset> packages more (use --limit:<N> to see more)")

  # stdout.write('\n')
  # displayMessage("<yellow>tip<reset>", "To get more information on a particular package, run `<blue>neo info <package><reset>`")

proc installPackageCommand(args: Input) =
  var 
    directory = "src"
    firstArgumentUsed = false

  let sourceFile =
    if args.arguments.len > 0:
      directory = args.arguments[0] / "src"
      firstArgumentUsed = true
      args.arguments[0] / "neo.yml"
    else:
      getCurrentDir() / "neo.yml"

  if not fileExists(sourceFile):
    error "Cannot find Neo build file at: <red>" & sourceFile & "<reset>"
    quit(QuitFailure)

  var project = loadProject(sourceFile)
  if project.binaries.len < 1:
    error "This project exposes no binary outputs!"
    quit(QuitFailure)

  var toolchain = newToolchain(project.toolchain.version)

  var deps: seq[Dependency]
  try:
    deps = project.solveDependencies()
  except CatchableError as exc:
    error "Failed to solve dependencies: " & exc.msg
    quit(1)
  
  var fail = false
  for binaryName in project.binaries:
    displayMessage("<yellow>compiling<reset>", "<green>" & binaryName & "<reset> using the <blue>" & project.backend.toHumanString() & "<reset> backend")
    
    let stats = toolchain.compile(project.backend, directory / binaryName & ".nim", CompilationOptions(
      outputFile: getNeoDir() / "bin" / binaryName,
      extraFlags: "--define:release --define:speed",
      appendPaths: getDepPaths(deps))
    )
    if stats.successful:
      displayMessage("<green>" & binaryName & "<reset>", "was built successfully, with <green>" & $stats.unitsCompiled & "<reset> unit(s) compiled.")

      var extraFlags: string
      for flag, value in args.flags:
        extraFlags &= "--" & flag & ':' & value

      for switch in args.switches:
        extraFlags &= "--" & switch
    else:
      displayMessage("<red>" & binaryName & "<reset>", "has failed to compile. Check the error above for more information.")
      fail = true
      break

  if fail:
    error "One or more binaries have failed to compile. Check the error(s) above for more information."
    quit(QuitFailure)

  displayMessage("<green>Installed<reset>", $project.binaries.len & " binar" & (if project.binaries.len == 1: "y" else: "ies") & " successfully.")
  displayMessage("<yellow>warning<reset>", "Make sure to add " & (getNeoDir() / "bin") & " to your <blue>PATH<reset> environment variable to run these binaries.")

proc showHelpCommand() {.noReturn, sideEffect.} =
  echo "Neo is a package manager for Nim"
  displayMessage("<green>Usage<reset>", "neo <yellow>[command]<reset> <blue>[args]<reset>")

  echo """

Commands:
init   [name]                   Initialize a project.
build                           Build the project in the current directory, if no path is specified.
run                             Build and run the project in the current directory, if no path is specified.
search [name]                   Search the package index for a particular package.
help                            Show this message.
install                         Install binaries from the current project.
  """

proc main() {.inline.} =
  initNeoState()

  let args = parseInput()
  case args.command
  of "init":
    initializePackageCommand(args)
  of "build":
    buildPackageCommand(args)
  of "run":
    runPackageCommand(args)
  of "search":
    searchPackageCommand(args)
  of "help":
    showHelpCommand()
  of "install":
    installPackageCommand(args)
  else:
    if args.command.len < 1:
      showHelpCommand()
    else:
      error "invalid command <red>`" & args.command & "`<reset>"
      quit(QuitFailure)

  saveNeoState()

when isMainModule:
  main()
