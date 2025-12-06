## Neo - the new package manager for Nim
## 
## Copyright (C) Trayambak Rai (xtrayambak@disroot.org)
import std/[os, osproc, options, tables, strutils, times]
import pkg/[semver, shakar, floof, results, url]
import ./[argparser, output]
import ./types/[project, toolchain, backend, package_lists]
import
  ./routines/
    [build, initialize, package_lists, forge_aliases, state, dependencies, locking],
  ./routines/nimble/primitiveparser

const
  NeoVersion* {.strdefine: "NimblePkgVersion".} = "0.1.0"

  # For the sake of brevity, only show the first 15 closest matches
  # when searching for packages.
  MaxMatchesDefault* {.intdefine: "NeoSearchMaxMatchesDefault".} = 15

proc initializePackageCommand(args: argparser.Input) {.noReturn.} =
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
    version = askQuestion("Version (0.1.0)", "0.1.0")
    license = askQuestion("License (Optional)")
    desc = askQuestion("Description (Optional)")
    toolchainVersion = askQuestion("Nim Toolchain Version", NimVersion)

    project = newProject(
      name = name,
      kind = ProjectKind(kind),
      license = license,
      toolchain = newToolchain(toolchainVersion),
      description =
        if desc.len > 0:
          some(desc)
        else:
          none(string),
      version = version,
    )

  initializeProject(project)

  quit(QuitSuccess)

proc buildPackageCommand(
    args: argparser.Input, hasColorSupport: bool, state: State
) {.noReturn.} =
  var directory = "src"
  let sourceFile =
    if args.arguments.len > 0:
      directory = args.arguments[0] / "src"
      args.arguments[0] / "neo.toml"
    else:
      getCurrentDir() / "neo.toml"

  if not fileExists(sourceFile):
    error "Cannot find Neo build file at: <red>" & sourceFile & "<reset>"
    quit(QuitFailure)

  var project: Project

  try:
    project = loadProject(sourceFile)
  except TomlError as exc:
    error "Failed to load project: " & exc.msg
    quit(QuitFailure)

  try:
    if not buildBinaries(
      project = project,
      directory = directory,
      args = args,
      opts = BuildOpts(release: args.enabled("release")),
      state = state,
    ):
      error "Failed to compile all binaries. Check the error above for more information."
      quit(QuitFailure)
  except build.BuildError as exc:
    error exc.msg

proc runPackageCommand(args: argparser.Input, useColors: bool, state: State) =
  let sourceFile = getCurrentDir() / "neo.toml"
  let chosenBinary =
    if args.arguments.len > 0:
      some(args.arguments[0])
    else:
      none(string)

  if not fileExists(sourceFile):
    error "Cannot find Neo build file at: <red>" & sourceFile & "<reset>"
    quit(QuitFailure)

  let project = loadProject(sourceFile)
  let binaryName = block:
    if project.package.binaries.len > 1:
      if !chosenBinary:
        error "Expected binary file to run. Choose between the following:"
        for bin in project.package.binaries:
          displayMessage("", "<green>" & bin & "<reset>")

        quit(QuitFailure)

      &chosenBinary
    else:
      project.package.binaries[0]

  try:
    if not buildBinaries(
      project = project,
      directory = getCurrentDir() / "src",
      args = args,
      opts = BuildOpts(
        release: args.enabled("release"),
        installOutputs: false,
        targets: some(@[binaryName]),
      ),
      state = state,
    ):
      error "Failed to compile binary output <red>" & binaryName &
        "<reset>. Please check the error above."
      quit(QuitFailure)

    discard execCmd("./" & binaryName)
  except build.BuildError as exc:
    error exc.msg
    quit(QuitFailure)

proc searchPackageCommand(args: argparser.Input, state: State) =
  if args.arguments.len < 1:
    displayMessage(
      "<red>error<reset>", "This command expects one argument. It was provided none."
    )
    quit(1)

  let package = args.arguments[0]
  let list = lazilyFetchPackageList(state, DefaultPackageList)

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
    args: argparser.Input,
    directory: string,
    project: Project,
    deps: seq[Dependency],
    graph: SolvedGraph,
    useColors: bool = false,
    state: State,
) =
  displayMessage(
    "<green>Installing<reset>",
    "binaries for " & project.name & "@<blue>" & $project.package.version & "<reset>",
  )

  try:
    if not buildBinaries(
      project = project,
      directory = directory,
      args = args,
      opts = BuildOpts(
        release: true,
        installOutputs: true,
        solverOutput: some(SolverOutput(deps: deps, graph: graph)),
      ),
      state = state,
    ):
      error "Failed to compile binary outputs for installation. Please check the error above."
      quit(QuitFailure)
  except build.BuildError as exc:
    error exc.msg
    quit(QuitFailure)

proc installLibraryProject(
    args: argparser.Input, project: Project, directory: string, state: State
) =
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
    directory / "src" / project.name,
    getDirectoryForPackage(state, project.name, versionStr),
  )

proc installPackageCommand(args: argparser.Input, useColors: bool, state: State) =
  var
    directory = "src"
    firstArgumentUsed = false

  let sourceFile =
    if args.arguments.len > 0:
      directory = args.arguments[0] / "src"
      firstArgumentUsed = true
      args.arguments[0] / "neo.toml"
    else:
      getCurrentDir() / "neo.toml"

  if not fileExists(sourceFile):
    error "Cannot find Neo build file at: <red>" & sourceFile & "<reset>"
    quit(QuitFailure)

  var
    project = loadProject(sourceFile)
    deps: seq[Dependency]
    graph: SolvedGraph

  try:
    (deps, graph) = project.solveDependencies(state)
  except CannotResolveDependencies as exc:
    error exc.msg
    quit(QuitFailure)
  except CloneFailed as exc:
    error exc.msg
    quit(QuitFailure)

  case project.package.kind
  of ProjectKind.Binary:
    installBinaryProject(
      args = args,
      directory = directory,
      project = project,
      deps = deps,
      graph = graph,
      useColors = useColors,
      state = state,
    )
  of ProjectKind.Library:
    installLibraryProject(
      args = args, project = project, directory = directory, state = state
    )
  of ProjectKind.Hybrid:
    # Install the library components first, as the binary
    # portions might depend on them.
    installLibraryProject(
      args = args, project = project, directory = directory, state = state
    )
    installBinaryProject(
      args = args,
      directory = directory,
      project = project,
      deps = deps,
      graph = graph,
      useColors = useColors,
      state = state,
    )

proc syncIndicesCommand(args: argparser.Input, state: State) =
  discard fetchPackageList(DefaultPackageList)
  state.lastIndexSyncTime = epochTime()

proc showInfoLegacyCommand(path: string, package: PackageListItem) =
  ## Show the information of a legacy (Nimble-only) package.
  let nimbleFilePath = findNimbleFile(path)
  if !nimbleFilePath:
    error "This package does not seem to have a `<blue>neo.toml<reset>` or a `<blue>.nimble<reset>` file."
    error "Neo cannot display its information."
    quit(QuitFailure)

  let packageName = inferNameFromNimbleFile(&nimbleFilePath)
  let fileInfo = parseNimbleFile(readFile(&nimbleFilePath))

  var tags: seq[string]

  for tag in package.tags:
    tags &= colorTagSubs("<blue>#" & tag & "<reset>")

  echo colorTagSubs("<green>" & packageName & "<reset> " & tags.join(" "))
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

proc showInfoUrlArgument(url: URL, state: State) =
  let url =
    if isForgeAlias(url):
      # If url is a forge alias, we need to expand it from an opaque
      # URL to a proper, serialized URL.
      expandForgeUrl(url)
    else:
      # Else, let url get serialized as-is.
      serialize(url)

  try:
    discard downloadPackageFromURL(url, pkg = PackageRef(name: url), state)
  except CloneFailed as err:
    error err.msg
    quit(QuitFailure)

  # `downloadPackageFromURL()` automatically infers the package's name
  # after it successfully downloads it, so we can get its proper name.
  let
    pkgName = state.packageUrlResolvedNames[url]
    pkgDir = &findDirectoryForPackage(pkgName)

    path = pkgDir / "neo.toml"

  if not fileExists(path):
    # FIXME: Show descriptions. Also, add a description field to neo.toml!
    showInfoLegacyCommand(
      pkgDir,
      PackageListItem(name: pkgName, url: url, description: "Cannot render description"),
    )
    displayMessage(
      "<yellow>notice<reset>",
      "This project only has a `<blue>.nimble<reset>` file. If you own it, consider adding a `<green>neo.toml<reset>` to it as well.",
    )
    return

  # Load the Neo manifest.
  let project = loadProject(path)

  # for tag in pkg.tags:
  #  tags &= colorTagSubs("<blue>#" & tag & "<reset>")

  echo colorTagSubs("<green>" & pkgName & "<reset>")
  if *project.package.description:
    echo &project.package.description
  echo colorTagSubs("<green>version:<reset> " & project.package.version)
  echo colorTagSubs("<green>license:<reset> " & project.package.license)
  echo colorTagSubs("<green>backend:<reset> " & project.package.backend.toHumanString())

proc showInfoCommand(args: argparser.Input, state: State) =
  # TODO: This should search all available lists once we have that working.
  if args.arguments.len > 1:
    error "`<blue>neo info<reset>` expects exactly one argument, got " &
      $args.arguments.len & " instead."
    quit(QuitFailure)

  case args.arguments.len
  of 1:
    let list = &lazilyFetchPackageList(state, DefaultPackageList)
    if (let url = tryParseUrl(args.arguments[0]); *url):
      # TODO: Clean this up. There's no good way to reconcile
      # the `neo info <url>` and `neo info <name>` codepaths.
      showInfoUrlArgument(&url, state)
      return

    let package = list.find(args.arguments[0])

    if !package:
      error "could not find `<red>" & args.arguments[0] & "<reset>` in registry `<blue>" &
        DefaultPackageList & "<reset>`"
      quit(QuitFailure)

    let pkg = &package
    try:
      discard downloadPackage(pkg, PackageRef(name: args.arguments[0]), state)
    except CloneFailed as err:
      error err.msg
      quit(QuitFailure)

    try:
      let
        base = &findDirectoryForPackage(args.arguments[0])
        path = base / "neo.toml"
      if not fileExists(path):
        showInfoLegacyCommand(base, pkg)
        displayMessage(
          "<yellow>notice<reset>",
          "This project only has a `<blue>.nimble<reset>` file. If you own it, consider adding a `<green>neo.toml<reset>` to it as well.",
        )
        return

      # Load the Neo manifest.
      let project = loadProject(path)
      var tags: seq[string]

      for tag in pkg.tags:
        tags &= colorTagSubs("<blue>#" & tag & "<reset>")

      echo colorTagSubs("<green>" & project.package.name & "<reset> " & tags.join(" "))
      echo pkg.description
      echo colorTagSubs("<green>version:<reset> " & project.package.version)
      echo colorTagSubs("<green>license:<reset> " & project.package.license)
      echo colorTagSubs(
        "<green>backend:<reset> " & project.package.backend.toHumanString()
      )
      echo colorTagSubs("<green>documentation:<reset> " & pkg.web)
    except:
      error "Failed to load project manifest for `<red>" & args.arguments[0] &
        "`<reset>."
      error "Perhaps it depends on a Nimble file instead of a Neo file?"
      quit(QuitFailure)
  of 0:
    let
      base = getCurrentDir()
      path = base / "neo.toml"
    if not fileExists(path):
      showInfoLegacyCommand(base, PackageListItem())
      displayMessage(
        "<yellow>notice<reset>",
        "This project only has a `<blue>.nimble<reset>` file. If you own it, consider adding a `<green>neo.toml<reset>` to it as well. It is as simple as running <green>neo migrate<reset>!",
      )
      return

    let project = loadProject(path)
    echo colorTagSubs("<green>" & project.package.name & "<reset>\n")
    if *project.package.description:
      echo &project.package.description
    echo colorTagSubs("<green>version<reset>: " & project.package.version)
    echo colorTagSubs(
      "<green>backend<reset>: " & project.package.backend.toHumanString & " (`" &
        $project.package.backend & "`)"
    )
    echo colorTagSubs(
      "<green>license<reset>: " & (
        if project.package.license.len > 0: project.package.license
        else: "<red>unknown<reset>"
      )
    )

    if project.package.binaries.len > 0:
      echo colorTagSubs("<green>binaries<reset>:")
      for bin in project.package.binaries:
        echo colorTagSubs("  * <blue>" & bin & "<reset>")
  else:
    unreachable

proc addPackageCommand(args: argparser.Input, state: State) =
  if args.arguments.len < 1:
    error "`<red>neo add<reset>` expects atleast one argument, got none instead."
    quit(QuitFailure)

  let path = getCurrentDir() / "neo.toml"
  if not fileExists(path):
    error "No `<blue>neo.toml<reset>` file was found"

  var project = loadProject(path)

  var failed = false
  for package in args.arguments:
    displayMessage("<green>Adding<reset>", package & " to dependencies")

    try:
      let version = addDependency(project, package, state)
      displayMessage(
        "<green>Added<reset>",
        package & '@' & "<blue>" & version & "<reset> to dependencies",
      )
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
      failed = true

  var code = QuitSuccess
  if failed:
    code = QuitFailure
  else:
    project.save(path)

  quit(move(code))

proc migrateCommand(args: argparser.Input) =
  let nimbleFile = findNimbleFile(getCurrentDir())
  if !nimbleFile:
    error "Cannot find any .nimble file in this directory, migration cannot start."
    quit(QuitFailure)

  let
    nimble = &nimbleFile
    data = parseNimbleFile(readFile(nimble))
    projectName = nimble.splitFile().name

  displayMessage("<green>Migrating<reset>", "<blue>" & projectName & "<reset> to Neo")

  # FIXME: Surely we can make this less awful.
  let
    hasBin = data.bin.len > 0
    hasLib = data.hasInstallExt

  let kind =
    if hasBin and hasLib:
      # Hybrid
      ProjectKind.Hybrid
    elif hasBin and not hasLib:
      # Binary
      ProjectKind.Binary
    else:
      # Library
      ProjectKind.Library

  var project = newProject(
    name = projectName,
    license = data.license,
    kind = kind,
    toolchain = Toolchain(),
    version = data.version,
  )

  if data.backend.len > 0:
    project.package.backend = data.backend.toBackend()

  if data.description.len > 0:
    project.package.description = some(data.description)

  for bin, _ in data.bin:
    project.package.binaries &= bin

  for req in data.requires:
    let pkgRefOpt = parsePackageRefExpr(req)
    if !pkgRefOpt:
      error "Can't parse requirement of package: <red>" & req & "<reset>"
      quit(QuitFailure)

    let pkgRef = &pkgRefOpt
    if pkgRef.name == "nim":
      # TODO: Ideally, we should check the constraint here as well.
      # But hey, surely nothing will go wrong.
      project.toolchain.version = $pkgRef.version
    else:
      project.dependencies[pkgRef.name] = $pkgRef.constraint & ' ' & $pkgRef.version

  if data.tasks.len > 0:
    displayMessage(
      "<yellow>warning<reset>",
      "You seem to have some tasks in your Nimble project. Unfortunately, Neo does not support tasks as of now.",
    )

  displayMessage(
    "<green>Migrated<reset>", "<blue>" & projectName & "<reset> to Neo successfully."
  )
  project.save(getCurrentDir() / "neo.toml")

proc metaCommand() =
  echo "Neo " & NeoVersion
  echo "Compiled with Nim " & NimVersion
  echo "Copyright (C) 2025 Trayambak Rai"

proc lockCommand(args: argparser.Input, state: State) =
  let lockfilePath =
    if (let flagArg = args.flag("lockfile"); *flagArg):
      &flagArg
    else:
      "neo.lock"

  if generateLockFile(getCurrentDir(), lockfilePath, state):
    displayMessage("<green>Generated<reset>", "lockfile for project successfully")
    quit(QuitSuccess)

  error "An error occurred while generating the lockfile. Please refer to the errors above."
  quit(QuitFailure)

proc testCommand(args: argparser.Input, state: State) =
  let dir = getCurrentDir()
  let projectOpt = loadProjectInDir(dir)
  if !projectOpt:
    error(
      "Cannot find project manifest (<red>neo.toml<reset>) in the working directory."
    )
    quit(QuitFailure)

  let project = &projectOpt
  # TODO: A `tests` directory option flag in the manifest
  let testsDir = dir / "tests"

  var testList: seq[string]
  for kind, path in walkDir(testsDir):
    let splittedFile = splitFile(path)
    #!fmt: off
    if kind != pcFile or
      splittedFile.ext != ".nim" or
      not splittedFile.name
        .startsWith('t'): continue
    #!fmt: on

    testList &= path

  if testList.len < 1:
    displayMessage("<yellow>warning<reset>", "No test cases found!")
    quit(QuitFailure)

  if buildBinaries(
    project = project,
    directory = newString(0),
    args = args,
    opts = BuildOpts(
      targetKind: BuildTargetKind.Tests,
      targets: some(testList),
      ignoreBuildFailure: false,
      installOutputs: false,
      release: false,
      testing: TestingOpts(runAndCheck: true),
    ),
    state = state,
  ):
    displayMessage(
      "<green>Testing<reset>",
      "has succeeded, with all tests compiling and executing successfully.",
    )
    quit(QuitSuccess)
  else:
    error("One or more tests have failed, please check the errors above.")
    quit(QuitFailure)

proc showHelpCommand() {.noReturn, sideEffect.} =
  echo "Neo is a package manager for Nim"
  displayMessage(
    "<green>Usage<reset>", "neo <yellow>[command]<reset> <blue>[args]<reset>"
  )

  echo """

Commands:
  init   [name]                      Initialize a project.
  build                              Build the project in the current directory, if no path is specified.
  run                                Build and run the project in the current directory, if no path is specified.
  search [name]                      Search the package index for a particular package.
  help                               Show this message.
  install                            Install binaries from the current project.
  sync                               Synchronize the package index.
  info   [name / url / forge alias]  Get more details about a particular package.
  add    [name / url / forge alias]  Add a package as a dependency to your current project.
  meta                               Show the build metadata for Neo.
  lock                               Generate a lockfile with all dependencies, transitive and direct pinned.
  test                               Run all of the specified tests for this project.

Options:
  --colorless, C                  Do not use ANSI-escape codes to color Neo's output. This makes Neo's output easier to parse.
  """

proc main() {.inline.} =
  let state: State =
    try:
      getNeoState()
    except StateParseError:
      error "Cannot open the Neo state."
      error "<yellow>Tip<reset>: The state file seems to be broken or corrupted."
      nil

  if state == nil:
    quit(QuitFailure)

  let args = parseInput()
  output.hasColorSupport = output.hasColorSupport and not args.enabled("colorless", "C")
  case args.command
  of "init":
    initializePackageCommand(args)
  of "build":
    buildPackageCommand(args, output.hasColorSupport, state)
  of "run":
    runPackageCommand(args, output.hasColorSupport, state)
  of "search":
    searchPackageCommand(args, state)
  of "help":
    showHelpCommand()
  of "install":
    installPackageCommand(args, output.hasColorSupport, state)
  of "sync":
    syncIndicesCommand(args, state)
  of "info":
    showInfoCommand(args, state)
  of "add":
    addPackageCommand(args, state)
  of "migrate":
    migrateCommand(args)
  of "meta":
    metaCommand()
  of "lock":
    lockCommand(args, state)
  of "test":
    testCommand(args, state)
  else:
    if args.command.len < 1:
      showHelpCommand()
    else:
      error "invalid command <red>`" & args.command & "`<reset>"
      quit(QuitFailure)

when isMainModule:
  main()
