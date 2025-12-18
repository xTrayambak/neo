import std/[tables, options]
import pkg/[parsetoml, results, semver]
import ./[backend, toolchain]

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
    hash*: Option[string]
    constraint*: VerConstraint

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
    description*: Option[string]
    kind*: ProjectKind
    backend*: Backend
    binaries*: seq[string] = @[]

  NativePlatformInfo* = object
    link*: seq[string]
    incl*: seq[string]

  PlatformInfo* = object
    native*: Option[NativePlatformInfo]

  Project* = object
    package*: ProjectPackageInfo
    toolchain*: Toolchain
    dependencies*: Table[string, string]
    platforms*: PlatformInfo

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

func getDependencies*(project: Project): seq[string] {.inline.} =
  var deps = newSeqOfCap[string](project.dependencies.len)
  for key, value in project.dependencies:
    var value = value

    if value.len > 0 and value[0] notin {'>', '=', '<', '#'}:
      # If the package's version constraint doesn't begin
      # with a constraint symbol, automatically prefix it with `>=`
      value = ">= " & value

    deps &= key & ' ' & ensureMove(value)

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
  project.package.version = input

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

func newProject*(
    name: string,
    license: string,
    kind: ProjectKind,
    version: string,
    toolchain: Toolchain,
    description: Option[string] = none(string),
): Project {.inline.} =
  Project(
    package: ProjectPackageInfo(
      name: name,
      license: license,
      kind: kind,
      description: description,
      version: version,
    ),
    toolchain: toolchain,
  )

export TomlError
