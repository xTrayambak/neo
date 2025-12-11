## Routines to build and install a project
## This exists to unify all the different commands (`build`, `install`, `run`)
## build logic into one set of routines.
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak@disroot.org)
import std/[os, osproc, options, tables]
import
  ../types/[backend, compilation_options, project, toolchain], ../[argparser, output]
import ./[dependencies, locking, neo_directory, state]
import pkg/shakar

type
  BuildError* = object of IOError
  NoBinaries* = object of BuildError
  IllegalSetup* = object of BuildError

  SolverOutput* = object
    deps*: seq[Dependency]
    graph*: SolvedGraph

  BuildTargetKind* {.pure, size: sizeof(uint8).} = enum
    Binaries = 0
    Tests = 1

  TestingOpts* = object
    runAndCheck*: bool

  BuildOpts* = object
    targets*: Option[seq[string]]
    ignoreBuildFailure*: bool

    solverOutput*: Option[SolverOutput]
    installOutputs*: bool

    release*: bool
    targetKind*: BuildTargetKind

    testing*: TestingOpts

proc buildBinaries*(
    project: Project,
    directory: string,
    args: argparser.Input,
    opts: BuildOpts,
    state: State,
): bool =
  if opts.targetKind == BuildTargetKind.Binaries and
      project.package.kind == ProjectKind.Library:
    raise newException(
      IllegalSetup,
      "A <blue>Library<reset> project cannot build binary outputs. Please switch your project to a <green>Hybrid<reset> project in <green>neo.toml<reset> to continue.",
    )

  if opts.targetKind == BuildTargetKind.Binaries and project.package.binaries.len < 1:
    raise newException(
      NoBinaries, "Project <red>" & project.name & "<reset> has no binary outputs."
    )

  var toolchain = newToolchain(version = project.toolchain.version)

  var extraFlags: string
  for flag, value in args.flags:
    extraFlags &= "--" & flag & ':' & value & ' '

  if not hasColorSupport:
    extraFlags &= "--colors:off "
  else:
    extraFlags &= "--colors:on "

  for switch in args.switches:
    extraFlags &= "--" & switch & ' '

  if opts.release:
    extraFlags &= "--define:release "

  var
    deps: seq[Dependency]
    graph: SolvedGraph

    appendPaths: seq[string]

  if !opts.solverOutput:
    try:
      (deps, graph) = project.solveDependencies(state)
    except CannotResolveDependencies as exc:
      error exc.msg
      return false
    except CloneFailed as exc:
      error exc.msg
      return false
    except InvalidCommitHash as exc:
      error exc.msg
      return false
  else:
    let output = &opts.solverOutput
    deps = output.deps
    graph = output.graph

  if opts.targetKind == BuildTargetKind.Tests:
    assert(
      *opts.targets,
      "BuildOpts::targets must be defined if tests are to be built (the build routines cannot figure out which tests to compile on their own!)",
    )

  let buildList =
    if *opts.targets:
      &opts.targets
    else:
      project.package.binaries

  let parentDirectory = parentDir(directory)
  if lockfileExists(parentDirectory):
    # If a lockfile exists:

    # 1. Reconstruct the dependency graph using the lock.

    try:
      graph = buildGraphFromLock(&loadLockFile(parentDirectory), state)
    except locking.LockError as exc:
      raise newException(BuildError, exc.msg)

    # 2. Regenerate `neo.paths` so the compiler knows
    # what locked versions of dependencies it needs to pull in.
    writeFile("neo.paths", generateLockedDepPaths(state, graph))
  else:
    appendPaths = getDepPaths(graph, state)

  if opts.testing.runAndCheck:
    saveState(state[])

  var failure = false
  var nBins: uint = 0
  for binFile in buildList:
    displayMessage(
      "<yellow>compiling<reset>",
      "<green>" & binFile & "<reset> using the <blue>" &
        project.package.backend.toHumanString() & "<reset> backend",
    )

    let stats = toolchain.compile(
      project.package.backend,
      directory / binFile,
      CompilationOptions(
        outputFile: (
          if opts.installOutputs:
            getNeoDir() / "bin" / binFile.changeFileExt(newString(0))
          else:
            binFile.changeFileExt(newString(0))
        ),
        extraFlags: extraFlags,
        appendPaths: appendPaths,
        version: $project.package.version,
      ),
    )

    if stats.successful:
      displayMessage(
        "<green>" & binFile & "<reset>",
        "was built successfully, with <green>" & $stats.unitsCompiled &
          "<reset> unit(s) compiled.",
      )

      if opts.testing.runAndCheck:
        let testName = splitPath(binFile).tail

        displayMessage("<green>Testing<reset>", testName)
        if execCmd(binFile.changeFileExt(newString(0))) != 0:
          failure = true
          displayMessage("<red>Failed<reset>", testName)
          break # TODO: Add TestingOpts::ignoreFailure
        else:
          displayMessage("<green>Success<reset>", testName)

      inc nBins
    else:
      displayMessage(
        "<red>" & binFile & "<reset>",
        "has failed to compile. Check the error above for more information.",
      )

      if not opts.ignoreBuildFailure:
        failure = true
        break
      else:
        displayMessage("<yellow>warning<reset>", "ignoring build failure")

  if opts.installOutputs:
    displayMessage(
      "<green>Installed<reset>",
      $nBins & " binar" & $(if nBins == 1: "y" else: "ies") & " successfully.",
    )

  return not failure
