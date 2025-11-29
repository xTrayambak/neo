## Routines to build and install a project
## This exists to unify all the different commands (`build`, `install`, `run`)
## build logic into one set of routines.
##
## Copyright (C) 2025 Trayambak Rai (xtrayambak@disroot.org)
import std/[os, options, tables]
import
  ../types/[backend, compilation_options, project, toolchain], ../[argparser, output]
import ./[dependencies, neo_directory]
import pkg/shakar

type
  BuildError* = object of IOError
  NoBinaries* = object of BuildError
  IllegalSetup* = object of BuildError

  SolverOutput* = object
    deps*: seq[Dependency]
    graph*: SolvedGraph

  BuildOpts* = object
    targets*: Option[seq[string]]
    ignoreBuildFailure*: bool

    solverOutput*: Option[SolverOutput]
    installOutputs*: bool

proc buildBinaries*(
    project: Project, directory: string, args: argparser.Input, opts: BuildOpts
): bool =
  if project.package.kind == ProjectKind.Library:
    raise newException(
      IllegalSetup,
      "A <blue>Library<reset> project cannot build binary outputs. Please switch your project to a <green>Hybrid<reset> project in <green>neo.toml<reset> to continue.",
    )

  if project.package.binaries.len < 1:
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
    extraFlags &= "--" & switch

  var
    deps: seq[Dependency]
    graph: SolvedGraph

  if !opts.solverOutput:
    try:
      (deps, graph) = project.solveDependencies()
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

  let buildList =
    if *opts.targets:
      &opts.targets
    else:
      project.package.binaries

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
      directory / binFile & ".nim",
      CompilationOptions(
        outputFile: (
          if opts.installOutputs:
            getNeoDir() / "bin" / binFile
          else:
            binFile
        ),
        extraFlags: extraFlags,
        appendPaths: getDepPaths(graph),
        version: $project.package.version,
      ),
    )

    if stats.successful:
      displayMessage(
        "<green>" & binFile & "<reset>",
        "was built successfully, with <green>" & $stats.unitsCompiled &
          "<reset> unit(s) compiled.",
      )

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
