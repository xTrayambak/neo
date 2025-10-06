## Neo - the new package manager for Nim
## 
## Copyright (C) Trayambak Rai (xtrayambak at disroot dot org)
import std/[os, osproc, tables, sequtils, strutils, times]
import pkg/[semver, shakar, floof, results]
import ./[argparser, output]
import ./types/[project, toolchain, backend, compilation_options, package_lists]
import
  ./routines/[initialize, package_lists, state, dependencies, neo_directory],
  ./routines/nimble/declarativeparser

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
    toolchainVersion = askQuestion("Nim Toolchain Version", NimVersion)

    project = newProject(
      name = name,
      kind = ProjectKind(kind),
      license = license,
      toolchain = newToolchain(toolchainVersion),
    )

  initializeProject(project)

  quit(QuitSuccess)

proc buildPackageCommand(args: Input, hasColorSupport: bool) {.noReturn.} =
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

  var project: Project

  try:
    project = loadProject(sourceFile)
  except CatchableError as exc:
    error "Failed to load project: <red>" & exc.msg & "<reset>"
    quit(QuitFailure)

  if project.binaries.len < 1:
    error "This project has no compilable binaries."
    quit(QuitFailure)

  var toolchain = newToolchain(version = project.toolchain.version)

  var extraFlags: string
  for flag, value in args.flags:
    extraFlags &= "--" & flag & ':' & value

  if not hasColorSupport:
    extraFlags &= "--colors:off "
  else:
    extraFlags &= "--colors:on "

  for switch in args.switches:
    extraFlags &= "--" & switch

  var
    deps: seq[Dependency]
    graph: SolvedGraph

  try:
    (deps, graph) = project.solveDependencies()
  except CannotResolveDependencies as exc:
    error exc.msg
    quit(QuitFailure)
  except CloneFailed as exc:
    error exc.msg
    quit(QuitFailure)

  var failure = false
  for binFile in project.binaries:
    displayMessage(
      "<yellow>compiling<reset>",
      "<green>" & binFile & "<reset> using the <blue>" & project.backend.toHumanString() &
        "<reset> backend",
    )
    let stats = toolchain.compile(
      project.backend,
      directory / binFile & ".nim",
      CompilationOptions(
        outputFile: binFile,
        extraFlags: extraFlags,
        appendPaths: getDepPaths(deps, graph),
      ),
    )

    if stats.successful:
      displayMessage(
        "<green>" & binFile & "<reset>",
        "was built successfully, with <green>" & $stats.unitsCompiled &
          "<reset> unit(s) compiled.",
      )
    else:
      displayMessage(
        "<red>" & binFile & "<reset>",
        "has failed to compile. Check the error above for more information.",
      )
      failure = true
      break
        # TODO: add a flag called `--ignore-build-failure` which doesn't cause the entire build process to stop after an error

  if failure:
    quit(QuitFailure)

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
  let binaryName = block:
    if project.binaries.len > 1:
      let pos = if firstArgumentUsed: 1 else: 0

      if args.arguments.len < pos:
        error "Expected binary file to run. Choose between the following:"
        for bin in project.binaries:
          displayMessage("", "<green>" & bin & "<reset>")

        quit(QuitFailure)

      args.arguments[pos]
    else:
      project.binaries[0]

  var toolchain = newToolchain(project.toolchain.version)

  var
    deps: seq[Dependency]
    graph: SolvedGraph

  try:
    (deps, graph) = project.solveDependencies()
  except CannotResolveDependencies as exc:
    error exc.msg
    quit(QuitFailure)
  except CloneFailed as exc:
    error exc.msg
    quit(QuitFailure)

  displayMessage(
    "<yellow>compiling<reset>",
    "<green>" & binaryName & "<reset> using the <blue>" & project.backend.toHumanString() &
      "<reset> backend",
  )

  let stats = toolchain.compile(
    project.backend,
    directory / binaryName & ".nim",
    CompilationOptions(outputFile: binaryName, appendPaths: getDepPaths(deps, graph)),
  )
  if stats.successful:
    displayMessage(
      "<green>" & binaryName & "<reset>",
      "was built successfully, with <green>" & $stats.unitsCompiled &
        "<reset> unit(s) compiled.",
    )

    var extraFlags: string
    for flag, value in args.flags:
      extraFlags &= "--" & flag & ':' & value

    for switch in args.switches:
      extraFlags &= "--" & switch

    saveNeoState()
    discard execCmd("./" & binaryName & ' ' & extraFlags)
  else:
    displayMessage(
      "<red>" & binaryName & "<reset>",
      "has failed to compile. Check the error above for more information.",
    )
    quit(QuitFailure)

proc searchPackageCommand(args: Input) =
  if args.arguments.len < 1:
    displayMessage(
      "<red>error<reset>", "This command expects one argument. It was provided none."
    )
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
    displayMessage(
      "<blue>...<reset>",
      "and <green>" & $(results.len - limit) &
        "<reset> packages more (use --limit:<N> to see more)",
    )

  # stdout.write('\n')
  # displayMessage("<yellow>tip<reset>", "To get more information on a particular package, run `<blue>neo info <package><reset>`")

proc installBinaryProject(
    args: Input,
    directory: string,
    project: Project,
    deps: seq[Dependency],
    graph: SolvedGraph,
) =
  if project.binaries.len < 1:
    error "This project exposes no binary outputs!"
    quit(QuitFailure)

  let version = project.version
  if !version:
    error "Cannot parse the version of project <yellow>" & project.name &
      "<reset>: <red>" & version.error() & "<reset>"
    quit(QuitFailure)

  let versionStr = $(&version)

  displayMessage(
    "<green>Installing<reset>",
    "binaries for " & project.name & "@<blue>" & versionStr & "<reset>",
  )

  var toolchain = newToolchain(project.toolchain.version)

  var fail = false
  for binaryName in project.binaries:
    displayMessage(
      "<yellow>compiling<reset>",
      "<green>" & binaryName & "<reset> using the <blue>" &
        project.backend.toHumanString() & "<reset> backend",
    )

    let stats = toolchain.compile(
      project.backend,
      directory / binaryName & ".nim",
      CompilationOptions(
        outputFile: getNeoDir() / "bin" / binaryName,
        extraFlags: "--define:release --define:speed",
        appendPaths: getDepPaths(deps, graph),
      ),
    )
    if stats.successful:
      displayMessage(
        "<green>" & binaryName & "<reset>",
        "was built successfully, with <green>" & $stats.unitsCompiled &
          "<reset> unit(s) compiled.",
      )

      var extraFlags: string
      for flag, value in args.flags:
        extraFlags &= "--" & flag & ':' & value

      for switch in args.switches:
        extraFlags &= "--" & switch
    else:
      displayMessage(
        "<red>" & binaryName & "<reset>",
        "has failed to compile. Check the error above for more information.",
      )
      fail = true
      break

  if fail:
    error "One or more binaries have failed to compile. Check the error(s) above for more information."
    quit(QuitFailure)

  displayMessage(
    "<green>Installed<reset>",
    $project.binaries.len & " binar" & (if project.binaries.len == 1: "y" else: "ies") &
      " successfully.",
  )
  displayMessage(
    "<yellow>warning<reset>",
    "Make sure to add " & (getNeoDir() / "bin") &
      " to your <blue>PATH<reset> environment variable to run these binaries.",
  )

proc installLibraryProject(args: Input, project: Project, directory: string) =
  let version = project.version
  if !version:
    error "Cannot parse the version of project <yellow>" & project.name &
      "<reset>: <red>" & version.error() & "<reset>"
    quit(QuitFailure)

  let versionStr = $(&version)

  displayMessage(
    "<green>Installing<reset>",
    "library " & project.name & "@<blue>" & versionStr & "<reset>",
  )

  copyDir(
    directory / "src" / project.name, getDirectoryForPackage(project.name, versionStr)
  )

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

  var
    project = loadProject(sourceFile)
    deps: seq[Dependency]
    graph: SolvedGraph

  try:
    (deps, graph) = project.solveDependencies()
  except CannotResolveDependencies as exc:
    error exc.msg
    quit(QuitFailure)
  except CloneFailed as exc:
    error exc.msg
    quit(QuitFailure)

  case project.kind
  of ProjectKind.Binary:
    installBinaryProject(
      args = args, directory = directory, project = project, deps = deps, graph = graph
    )
  of ProjectKind.Library:
    installLibraryProject(args = args, project = project, directory = directory)
  of ProjectKind.Hybrid:
    # Install the library components first, as the binary
    # portions might depend on them.
    installLibraryProject(args = args, project = project, directory = directory)
    installBinaryProject(
      args = args, directory = directory, project = project, deps = deps, graph = graph
    )

proc syncIndicesCommand(args: Input) =
  discard fetchPackageList(DefaultPackageList)
  setLastIndexSyncTime(epochTime())

proc formatProjectCommand(args: Input) =
  # TODO: Global formatter settings that'd live in the user's config
  # at `~/.config/neo/config.yml`. Implement this when the config stuff
  # is implemented.
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

  let project = loadProject(sourceFile)
  let executable = findExe(project.formatter)

  if executable.len < 1:
    error "The formatter <blue>" & project.formatter & "<reset> was not found."
    error "Are you sure that it is installed and in your system's <blue>PATH<reset>?"
    quit(QuitFailure)

  displayMessage(
    "<blue>Formatting<reset>",
    project.name & " via <green>" & project.formatter & "<reset>",
  )

  let code = (
    case project.formatter
    of "nimpretty", "nph":
      execCmd(executable & ' ' & getCurrentDir())
    else:
      error "Unknown formatter: <red>" & project.formatter & "<reset>."
      error "Formatters recognized by Neo are: <blue>nph<reset> and <blue>nimpretty<reset>."
      -1
  )

  if code != 0:
    error "The formatter <red>" & project.formatter &
      "<reset> exited with a non-zero exit code (" & $code & ')'
    quit(QuitFailure)

proc showInfoLegacyCommand(path: string, package: PackageListItem) =
  ## Show the information of a legacy (Nimble-only) package.
  let nimbleFilePath = findNimbleFile(path)
  if !nimbleFilePath:
    error "This package does not seem to have a `<blue>neo.yml<reset>` or a `<blue>.nimble<reset>` file."
    error "Neo cannot display its information."
    quit(QuitFailure)

  let fileInfo = extractRequiresInfo(&nimbleFilePath)

  var tags: seq[string]

  for tag in package.tags:
    tags &= colorTagSubs("<blue>#" & tag & "<reset>")

  echo colorTagSubs("<green>" & package.name & "<reset> " & tags.join(" "))
  echo package.description
  echo colorTagSubs("<green>version:<reset> " & fileInfo.version.split(' ')[0])
  echo colorTagSubs("<green>license:<reset> " & fileInfo.license)
  try:
    echo colorTagSubs(
      "<green>backend:<reset> " & fileInfo.backend.toBackend().toHumanString()
    )
  except ValueError:
    discard
  echo colorTagSubs("<green>documentation:<reset> " & package.web)

proc showInfoCommand(args: Input) =
  # TODO: This should search all available lists once we have that working.
  if args.arguments.len > 1:
    error "`<blue>neo info<reset>` expects exactly one argument, got " &
      $args.arguments.len & " instead."

  case args.arguments.len
  of 1:
    let list = &lazilyFetchPackageList(DefaultPackageList)
    let package = list.find(args.arguments[0])

    if !package:
      error "could not find `<red>" & args.arguments[0] & "<reset>` in registry `<blue>" &
        DefaultPackageList & "<reset>`"
      quit(QuitFailure)

    let pkg = &package
    try:
      discard downloadPackage(pkg, PackageRef(name: args.arguments[0]))
    except CloneFailed as err:
      error err.msg
      quit(QuitFailure)

    try:
      let
        base = &findDirectoryForPackage(args.arguments[0])
        path = base / "neo.yml"
      if not fileExists(path):
        showInfoLegacyCommand(base, pkg)
        displayMessage(
          "<yellow>notice<reset>",
          "This project only has a `<blue>.nimble<reset>` file. If you own it, consider adding a `<green>neo.yml<reset>` to it as well.",
        )
        return

      # Load the Neo manifest.
      let project = loadProject(path)
      var tags: seq[string]

      for tag in pkg.tags:
        tags &= colorTagSubs("<blue>#" & tag & "<reset>")

      echo colorTagSubs("<green>" & project.name & "<reset> " & tags.join(" "))
      echo pkg.description
      echo colorTagSubs("<green>license:<reset> " & project.license)
      echo colorTagSubs("<green>backend:<reset> " & project.backend.toHumanString())
      echo colorTagSubs("<green>documentation:<reset> " & pkg.web)
    except:
      error "Failed to load project manifest for `<red>" & args.arguments[0] &
        "`<reset>."
      error "Perhaps it depends on a Nimble file instead of a Neo file?"
      quit(QuitFailure)
  of 0:
    let path = getCurrentDir() / "neo.yml"
    if not fileExists(path):
      error "No `<blue>neo.yml<reset>` file was found in the current working directory."
      quit(QuitFailure)

    let project = loadProject(path)
    echo colorTagSubs("<green>" & project.name & "<reset>\n")
    echo colorTagSubs(
      "<green>backend<reset>: " & project.backend.toHumanString & " (`" &
        $project.backend & "`)"
    )
    echo colorTagSubs(
      "<green>license<reset>: " &
        (if project.license.len > 0: project.license else: "<red>unknown<reset>")
    )

    if project.binaries.len > 0:
      echo colorTagSubs("<green>binaries<reset>:")
      for bin in project.binaries:
        echo colorTagSubs("  * <blue>" & bin & "<reset>")
  else:
    unreachable

proc addPackageCommand(args: Input) =
  if args.arguments.len < 1:
    error "`<red>neo add<reset>` expects atleast one argument, got none instead."
    quit(QuitFailure)

  let path = getCurrentDir() / "neo.yml"
  if not fileExists(path):
    error "No `<blue>neo.yml<reset>` file was found"

  var project = loadProject(path)

  var failed = false
  for package in args.arguments:
    displayMessage("<green>Adding<reset>", package & " to dependencies")

    try:
      addDependency(project, package)
      displayMessage("<green>Added<reset>", package & " to dependencies")
    except PackageNotFound as err:
      error "the package `<red>" & err.package &
        "<reset>` was not found in any package indices."
      failed = true
      break
    except PackageAlreadyDependency as err:
      displayMessage("<yellow>warning<reset>", err.msg)
    except InvalidForgeAlias as err:
      error "the forge alias `<red>" & err.url &
        "<reset>` could not be resolved into any meaningful forge."
      failed = true
      break
    except SolverError as err:
      error "neo encountered a generic solver invariant: <red>" & err.msg & "<reset>"

  var code = QuitSuccess
  if failed:
    code = QuitFailure
  else:
    project.save(path)

  quit(move(code))

proc showHelpCommand() {.noReturn, sideEffect.} =
  echo "Neo is a package manager for Nim"
  displayMessage(
    "<green>Usage<reset>", "neo <yellow>[command]<reset> <blue>[args]<reset>"
  )

  echo """

Commands:
  init   [name]                   Initialize a project.
  build                           Build the project in the current directory, if no path is specified.
  run                             Build and run the project in the current directory, if no path is specified.
  search [name]                   Search the package index for a particular package.
  help                            Show this message.
  install                         Install binaries from the current project.
  sync                            Synchronize the package index.
  info   [name]                   Get more details about a particular package.

Options:
  --colorless, C                  Do not use ANSI-escape codes to color Neo's output. This makes Neo's output easier to parse.
  """

proc main() {.inline.} =
  initNeoState()

  let args = parseInput()
  output.hasColorSupport = output.hasColorSupport and not args.enabled("colorless", "C")
  case args.command
  of "init":
    initializePackageCommand(args)
  of "build":
    buildPackageCommand(args, output.hasColorSupport)
  of "run":
    runPackageCommand(args)
  of "search":
    searchPackageCommand(args)
  of "help":
    showHelpCommand()
  of "install":
    installPackageCommand(args)
  of "sync":
    syncIndicesCommand(args)
  of "fmt":
    formatProjectCommand(args)
  of "info":
    showInfoCommand(args)
  of "add":
    addPackageCommand(args)
  else:
    if args.command.len < 1:
      showHelpCommand()
    else:
      error "invalid command <red>`" & args.command & "`<reset>"
      quit(QuitFailure)

  saveNeoState()

when isMainModule:
  main()
