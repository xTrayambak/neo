import std/[streams, strutils, tables, hashes]
import pkg/[toml_serialization, results, semver, pretty, url]
import ./[toolchain, backend]

type
  ProjectKind* {.pure.} = enum
    Binary
    Library
    Hybrid

  VerConstraint* {.size: sizeof(uint8), pure.} = enum
    None = 0
    Equal
    GreaterThan
    GreaterThanEqual
    LesserThan
    LesserThanEqual

  PackageRef* = object
    ## A package ref is an unresolved reference to a package.
    ## It must be solved by Neo at buildtime for compilation
    ## to commence.
    name*: string
    version*: Version
    constraint*: VerConstraint

  PRefParserState {.size: sizeof(uint8), pure.} = enum
    Name
    Constraint
    Version

  PRefParseError* {.size: sizeof(uint8), pure.} = enum
    InvalidConstraint = "invalid constraint"
    InvalidVersion = "version string cannot be parsed"

  CannotResolveDependencies* = object of ValueError
  ConflictingExactVersions* = object of CannotResolveDependencies
    pkgName*: string
    a*, b*: Version

  UnsolvableConstraints* = object of CannotResolveDependencies
    unsolvable*: string
    a*, b*: Version
    aCons*, bCons*: VerConstraint

  ProjectPackageInfo* = object
    name*: string
    version*: string
    license*: string
    kind*: ProjectKind
    backend*: Backend
    binaries*: seq[string] = @[]

  Project* = object
    package*: ProjectPackageInfo
    toolchain*: Toolchain
    dependencies*: TomlValueRef

func `$`*(constraint: VerConstraint): string {.raises: [], inline.} =
  case constraint
  of VerConstraint.None: ""
  of VerConstraint.Equal: "=="
  of VerConstraint.GreaterThan: ">"
  of VerConstraint.GreaterThanEqual: ">="
  of VerConstraint.LesserThan: "<"
  of VerConstraint.LesserThanEqual: "<="

func name*(project: Project): string {.inline.} =
  project.package.name

func dependencies*(project: Project): seq[string] {.inline.} =
  var deps = newSeqOfCap[string](project.dependencies.tableVal.len - 1)
  for key, value in project.dependencies.tableVal:
    var strV = value.stringVal
    if strV[0] notin {'>', '=', '<'}:
      # If the package's version constraint doesn't begin
      # with a constraint symbol, automatically prefix it with `==`
      strV = "==" & strV

    deps &= key & ' ' & ensureMove(strV)

  ensureMove(deps)

func version*(project: Project): Result[semver.Version, string] {.inline.} =
  try:
    return ok(parseVersion(project.package.version))
  except semver.ParseError as exc:
    return err(exc.msg)

func `version=`*(project: var Project, input: string) {.inline, raises: [].} =
  ## Set the version field of this project to the value
  ## of `input`
  ##
  ## **NOTE**: This routine performs no validation upon the provided input.
  project.version = input

func `==`*(a, b: PackageRef): bool {.inline.} =
  a.name == b.name and a.version == b.version and a.constraint == b.constraint

func unsolvableConstraint*(
    package: string, a, b: Version, aCons, bCons: VerConstraint
) =
  var exc = newException(UnsolvableConstraints, "")
  exc.unsolvable = package
  exc.a = a
  exc.b = b
  exc.aCons = aCons
  exc.bCons = bCons

  raise move(exc)

func find*(
    refs: seq[PackageRef], name: string
): Option[tuple[pref: PackageRef, index: int]] =
  for i, pkgRef in refs:
    if pkgRef.name == name:
      return some((pref: pkgRef, index: i))

func parsePackageRefExpr*(expr: string): Result[PackageRef, PRefParseError] =
  var state: PRefParserState
  var i = 0
  var pkg: PackageRef
  pkg.name = newStringOfCap(expr.len - 1) # Best case, expr is unversioned.

  let size = expr.len

  while i < size:
    case state
    of PRefParserState.Name:
      case expr[i]
      of {'>', '<', '='}:
        # If c is in { '>', '<', '=' }, set state to Constraint.
        state = PRefParserState.Constraint
      of strutils.Whitespace:
        # If c is whitespace, ignore it and increment the pointer by 1.
        inc i
      else:
        # Otherwise, append c to the name buffer.
        pkg.name &= expr[i]

        # Increment the pointer by 1.
        inc i
    of PRefParserState.Constraint:
      # Allocate a constraint buffer, preferrably
      # accounting for the worst-case of 2 bytes.
      var constraintBuffer = newStringOfCap(2)

      # While c is in {'>', '<', '='}:
      while i != size and expr[i] in {'>', '<', '='}:
        # Append c to the constraint buffer.
        constraintBuffer &= expr[i]

        # Increment the pointer by 1.
        inc i

      case constraintBuffer
      of "==":
        # If the buffer is "==", the constraint is Equal.
        pkg.constraint = VerConstraint.Equal
      of ">=":
        # If the buffer is ">=", the constraint is GreaterThanEqual.
        pkg.constraint = VerConstraint.GreaterThanEqual
      of ">":
        # If the buffer is ">", the constraint is GreaterThan.
        pkg.constraint = VerConstraint.GreaterThan
      of "<":
        # If the buffer is "<", the constraint is LesserThan.
        pkg.constraint = VerConstraint.LesserThan
      of "<=":
        # If the buffer is "<=", the constraint is LesserThanEqual.
        pkg.constraint = VerConstraint.LesserThanEqual
      else:
        # Otherwise, report an error.
        return err(PRefParseError.InvalidConstraint)

      # Set the state to Version.
      state = PRefParserState.Version
    of PRefParserState.Version:
      var versionBuffer: string

      # While we have not reached EOF, continually increment every
      # character to the version buffer, and increment
      # the pointer.
      while i != size:
        versionBuffer &= expr[i]
        inc i

      # Trim all left-facing whitespace
      # from the version buffer.
      versionBuffer = strip(move(versionBuffer))

      # Pass the resulting version buffer to a semantic version
      # parsing routine.
      try:
        pkg.version = parseVersion(ensureMove(versionBuffer))
      except semver.ParseError:
        # If version parsing fails, report an error.
        return err(PRefParseError.InvalidVersion)

  # Return `pkg`.
  ok(ensureMove(pkg))

func getDependencies*(project: Project): seq[PackageRef] =
  let deps = project.dependencies()
  var res = newSeqOfCap[PackageRef](deps.len)

  for dep in deps:
    let pref = parsePackageRefExpr(dep)
    if pref.isErr:
      raise newException(
        CannotResolveDependencies,
        "Cannot resolve dependency `<red>" & dep & "`<reset>: " & $pref.error(),
      )

    res &= pref.get()

  move(res)

func newProject*(
    name: string, license: string, kind: ProjectKind, toolchain: Toolchain
): Project {.inline.} =
  Project(
    package: ProjectPackageInfo(name: name, license: license, kind: kind),
    toolchain: toolchain,
  )

proc save*(project: Project, path: string) =
  var buffer = newStringOfCap(512)

  # We _COULD_ use nim_toml_serialization's TomlWriter
  # but its output is hideous. As a consequence,
  # we must update this every time the manifest format changes.
  buffer &= "[package]\n"
  buffer &= "name = \"$1\"\n" % [project.package.name]
  buffer &= "version = \"$1\"\n" % [$project.package.version]
  buffer &= "license = \"$1\"\n" % [project.package.license]
  buffer &= "kind = \"$1\"\n" % [$project.package.kind]
  buffer &= "backend = \"$1\"\n" % [$project.package.backend]

  var bins = newSeq[string](project.package.binaries.len)
  for i, bin in project.package.binaries:
    bins[i] = '"' & bin & '"'

  buffer &= "binaries = [$1]\n" % [move(bins).join(", ")]

  buffer &= "\n[toolchain]\n"
  buffer &= "version = \"$1\"\n" % [project.toolchain.version]

  let depsSize = project.dependencies.tableVal.len
  var currDep = 0
  buffer &= "\ndependencies = {\n"
  for name, cons in project.dependencies.tableVal:
    let processedName =
      if tryParseUrl(name).isOk:
        # If `name` is a URL, we need to quote it.
        '"' & name & '"'
      else:
        # Otherwise, we'll copy it as-is.
        name

    buffer &= "   $1 = \"$2\"" % [processedName, cons.stringVal]

    if currDep < depsSize - 1:
      buffer &= ",\n"
    else:
      buffer &= '\n'
  buffer &= '}'

  writeFile(path, ensureMove(buffer))

proc loadProject*(file: string): Project {.inline, sideEffect.} =
  return Toml.decode(readFile(file), Project, flags = {TomlInlineTableNewline})

export TomlError, TomlFieldReadingError
