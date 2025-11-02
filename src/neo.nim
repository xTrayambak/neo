## Neo - the new package manager for Nim
## 
## Copyright (C) Trayambak Rai (xtrayambak at disroot dot org)
import std/[os, osproc, options, tables, strutils, times]
import pkg/[semver, shakar, floof, results, url]
import ./[argparser, output]
import ./types/[project, toolchain, backend, compilation_options, package_lists]
import
  ./routines/
    [initialize, package_lists, forge_aliases, state, dependencies, neo_directory],
  ./routines/nimble/declarativeparser

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

proc buildPackageCommand(args: argparser.Input, hasColorSupport: bool) {.noReturn.} =
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

  if project.package.binaries.len < 1:
    error "This project has no compilable binaries."
    quit(QuitFailure)

  var toolchain = newToolchain(version = project.toolchain.version)

  var extraFlags: string
  for flag, value in args.flags:
    extraFlags &= "--" & flag & ':' & value & ' '

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
  for binFile in project.package.binaries:
    displayMessage(
      "<yellow>compiling<reset>",
      "<green>" & binFile & "<reset> using the <blue>" &
        project.package.backend.toHumanString() & "<reset> backend",
    )
    let stats = toolchain.compile(
      project.package.backend,
      directory / binFile & ".nim",
      CompilationOptions(
        outputFile: binFile,
        extraFlags:
          extraFlags & " --define:NimblePkgVersion=" & $project.package.version,
        appendPaths: getDepPaths(graph),
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

proc runPackageCommand(args: argparser.Input, useColors: bool) =
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

  var project = loadProject(sourceFile)
  let binaryName = block:
    if project.package.binaries.len > 1:
      let pos = if firstArgumentUsed: 1 else: 0

      if args.arguments.len < pos:
        error "Expected binary file to run. Choose between the following:"
        for bin in project.package.binaries:
          displayMessage("", "<green>" & bin & "<reset>")

        quit(QuitFailure)

      args.arguments[pos]
    else:
      project.package.binaries[0]

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
    "<green>" & binaryName & "<reset> using the <blue>" &
      project.package.backend.toHumanString() & "<reset> backend",
  )

  var extraCompilerFlags: string
  if not hasColorSupport:
    extraCompilerFlags &= "--colors:off "
  else:
    extraCompilerFlags &= "--colors:on "

  let stats = toolchain.compile(
    project.package.backend,
    directory / binaryName & ".nim",
    CompilationOptions(
      outputFile: binaryName,
      extraFlags:
        extraCompilerFlags & " --define:NimblePkgVersion=" & $project.package.version,
      appendPaths: getDepPaths(graph),
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

    saveNeoState()
    discard execCmd("./" & binaryName & ' ' & extraFlags)
  else:
    displayMessage(
      "<red>" & binaryName & "<reset>",
      "has failed to compile. Check the error above for more information.",
    )
    quit(QuitFailure)

proc searchPackageCommand(args: argparser.Input) =
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
    args: argparser.Input,
    directory: string,
    project: Project,
    deps: seq[Dependency],
    graph: SolvedGraph,
    useColors: bool = false,
) =
  if project.package.binaries.len < 1:
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
  for binaryName in project.package.binaries:
    displayMessage(
      "<yellow>compiling<reset>",
      "<green>" & binaryName & "<reset> using the <blue>" &
        project.package.backend.toHumanString() & "<reset> backend",
    )

    var extraFlags: string
    extraFlags &= "--define:release --define:speed "

    if useColors:
      extraFlags &= "--colors:on"
    else:
      extraFlags &= "--colors:off"

    let stats = toolchain.compile(
      project.package.backend,
      directory / binaryName & ".nim",
      CompilationOptions(
        outputFile: getNeoDir() / "bin" / binaryName,
        extraFlags:
          extraFlags & " --define:NimblePkgVersion=" & $project.package.version,
        appendPaths: getDepPaths(graph),
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
    $project.package.binaries.len & " binar" &
      (if project.package.binaries.len == 1: "y" else: "ies") & " successfully.",
  )
  displayMessage(
    "<yellow>warning<reset>",
    "Make sure to add " & (getNeoDir() / "bin") &
      " to your <blue>PATH<reset> environment variable to run these binaries.",
  )

proc installLibraryProject(args: argparser.Input, project: Project, directory: string) =
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

proc installPackageCommand(args: argparser.Input, useColors: bool) =
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
    (deps, graph) = project.solveDependencies()
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
    )
  of ProjectKind.Library:
    installLibraryProject(args = args, project = project, directory = directory)
  of ProjectKind.Hybrid:
    # Install the library components first, as the binary
    # portions might depend on them.
    installLibraryProject(args = args, project = project, directory = directory)
    installBinaryProject(
      args = args,
      directory = directory,
      project = project,
      deps = deps,
      graph = graph,
      useColors = useColors,
    )

proc syncIndicesCommand(args: argparser.Input) =
  discard fetchPackageList(DefaultPackageList)
  setLastIndexSyncTime(epochTime())

proc showInfoLegacyCommand(path: string, package: PackageListItem) =
  ## Show the information of a legacy (Nimble-only) package.
  let nimbleFilePath = findNimbleFile(path)
  if !nimbleFilePath:
    error "This package does not seem to have a `<blue>neo.toml<reset>` or a `<blue>.nimble<reset>` file."
    error "Neo cannot display its information."
    quit(QuitFailure)

  let packageName = inferNameFromNimbleFile(&nimbleFilePath)
  let fileInfo = extractRequiresInfo(&nimbleFilePath)

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

proc showInfoUrlArgument(url: URL) =
  let url =
    if isForgeAlias(url):
      # If url is a forge alias, we need to expand it from an opaque
      # URL to a proper, serialized URL.
      expandForgeUrl(url)
    else:
      # Else, let url get serialized as-is.
      serialize(url)

  try:
    discard downloadPackageFromURL(url, pkg = PackageRef(name: url))
  except CloneFailed as err:
    error err.msg
    quit(QuitFailure)

  # `downloadPackageFromURL()` automatically infers the package's name
  # after it successfully downloads it, so we can get its proper name.
  let
    pkgName = getPackageUrlNames()[url]
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
  # echo pkg.description
  echo colorTagSubs("<green>license:<reset> " & project.package.license)
  echo colorTagSubs("<green>backend:<reset> " & project.package.backend.toHumanString())

proc showInfoCommand(args: argparser.Input) =
  # TODO: This should search all available lists once we have that working.
  if args.arguments.len > 1:
    error "`<blue>neo info<reset>` expects exactly one argument, got " &
      $args.arguments.len & " instead."
    quit(QuitFailure)

  case args.arguments.len
  of 1:
    let list = &lazilyFetchPackageList(DefaultPackageList)
    if (let url = tryParseUrl(args.arguments[0]); *url):
      # TODO: Clean this up. There's no good way to reconcile
      # the `neo info <url>` and `neo info <name>` codepaths.
      showInfoUrlArgument(&url)
      return

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

proc addPackageCommand(args: argparser.Input) =
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
      let version = addDependency(project, package)
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
    data = extractRequiresInfo(nimble)
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
  try:
    initNeoState()
  except LevelDbException:
    error "Cannot open the Neo state."
    error "<yellow>Tip<reset>: Another instance of Neo might be running."
    quit(QuitFailure)

  let args = parseInput()
  output.hasColorSupport = output.hasColorSupport and not args.enabled("colorless", "C")
  case args.command
  of "init":
    initializePackageCommand(args)
  of "build":
    buildPackageCommand(args, output.hasColorSupport)
  of "run":
    runPackageCommand(args, output.hasColorSupport)
  of "search":
    searchPackageCommand(args)
  of "help":
    showHelpCommand()
  of "install":
    installPackageCommand(args, output.hasColorSupport)
  of "sync":
    syncIndicesCommand(args)
  of "info":
    showInfoCommand(args)
  of "add":
    addPackageCommand(args)
  of "migrate":
    migrateCommand(args)
  else:
    if args.command.len < 1:
      showHelpCommand()
    else:
      error "invalid command <red>`" & args.command & "`<reset>"
      quit(QuitFailure)

  saveNeoState()

when isMainModule:
  main()
