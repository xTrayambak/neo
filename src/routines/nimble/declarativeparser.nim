## Utility API for Nim package managers.
## (c) 2021 Andreas Rumpf

## This file has been modified to remove most of the additional baggage
## Neo does not require.

import std/strutils

import compiler/[ast, idents, msgs, syntaxes, options, pathutils, lineinfos]
import compiler/[renderer]
from compiler/nimblecmd import getPathVersionChecksum
import std/[tables, sequtils, strscans, strformat, os, options]

type NimbleFileInfo* = object
  nimbleFile*: string
  requires*: seq[string]
  srcDir*: string
  version*: string
  license*: string
  backend*: string
  tasks*: seq[(string, string)]
  features*: Table[string, seq[string]]
  bin*: Table[string, string]
  hasInstallHooks*: bool
  hasErrors*: bool
  nestedRequires*: bool
    #if true, the requires section contains nested requires meaning that the package is incorrectly defined
  declarativeParserErrorLines*: seq[string]
  #In vnext this means that we will need to re-run sat after selecting nim to get the correct requires

proc eqIdent(a, b: string): bool {.inline.} =
  cmpIgnoreCase(a, b) == 0 and a[0] == b[0]

proc collectRequiresFromNode(n: PNode, result: var seq[string]) =
  case n.kind
  of nkStmtList, nkStmtListExpr:
    for child in n:
      collectRequiresFromNode(child, result)
  of nkCallKinds:
    if n[0].kind == nkIdent and n[0].ident.s == "requires":
      for i in 1 ..< n.len:
        var ch = n[i]
        while ch.kind in {nkStmtListExpr, nkStmtList} and ch.len > 0:
          ch = ch.lastSon
        if ch.kind in {nkStrLit .. nkTripleStrLit}:
          result.add ch.strVal
    else:
      for child in n:
        collectRequiresFromNode(child, result)
  else:
    discard

proc validateNoNestedRequires(
    nfl: var NimbleFileInfo,
    n: PNode,
    conf: ConfigRef,
    hasErrors: var bool,
    nestedRequires: var bool,
    inControlFlow: bool = false,
) =
  case n.kind
  of nkStmtList, nkStmtListExpr:
    for child in n:
      validateNoNestedRequires(
        nfl, child, conf, hasErrors, nestedRequires, inControlFlow
      )
  of nkWhenStmt, nkIfStmt, nkIfExpr, nkElifBranch, nkElse, nkElifExpr, nkElseExpr:
    for child in n:
      validateNoNestedRequires(nfl, child, conf, hasErrors, nestedRequires, true)
  of nkCallKinds:
    if n[0].kind == nkIdent and n[0].ident.s == "requires":
      if inControlFlow:
        nestedRequires = true
        let errorLine =
          &"{nfl.nimbleFile}({n.info.line}, {n.info.col}) 'requires' cannot be nested inside control flow statements"
        nfl.declarativeParserErrorLines.add errorLine
        hasErrors = true
    else:
      for child in n:
        validateNoNestedRequires(
          nfl, child, conf, hasErrors, nestedRequires, inControlFlow
        )
  else:
    discard

proc extractSeqLiteral(n: PNode, conf: ConfigRef, varName: string): seq[string] =
  ## Extracts a sequence literal of the form @["item1", "item2"]
  if n.kind == nkPrefix and n[0].kind == nkIdent and n[0].ident.s == "@":
    if n[1].kind == nkBracket:
      for item in n[1]:
        if item.kind in {nkStrLit .. nkTripleStrLit}:
          result.add item.strVal
        else:
          localError(
            conf, item.info, &"'{varName}' sequence items must be string literals"
          )
    else:
      localError(conf, n.info, &"'{varName}' must be assigned a sequence of strings")
  else:
    localError(conf, n.info, &"'{varName}' must be assigned a sequence with @ prefix")

proc extractFeatures(
    featureNode: PNode, conf: ConfigRef, hasErrors: var bool, nestedRequires: var bool
): seq[string] =
  ## Extracts requirements from a feature declaration
  if featureNode.kind in {nkStmtList, nkStmtListExpr}:
    for stmt in featureNode:
      if stmt.kind in nkCallKinds and stmt[0].kind == nkIdent and
          stmt[0].ident.s == "requires":
        var requires: seq[string]
        collectRequiresFromNode(stmt, requires)
        result.add requires

proc extract(n: PNode, conf: ConfigRef, result: var NimbleFileInfo) =
  validateNoNestedRequires(result, n, conf, result.hasErrors, result.nestedRequires)
  case n.kind
  of nkStmtList, nkStmtListExpr:
    for child in n:
      extract(child, conf, result)
  of nkCallKinds:
    if n[0].kind == nkIdent:
      case n[0].ident.s
      of "requires":
        collectRequiresFromNode(n, result.requires)
      of "feature":
        if n.len >= 3 and n[1].kind in {nkStrLit .. nkTripleStrLit}:
          let featureName = n[1].strVal
          if not result.features.hasKey(featureName):
            result.features[featureName] = @[]
          result.features[featureName] =
            extractFeatures(n[2], conf, result.hasErrors, result.nestedRequires)
      of "dev":
        let featureName = "dev"
        if not result.features.hasKey(featureName):
          result.features[featureName] = @[]
        result.features[featureName] =
          extractFeatures(n[1], conf, result.hasErrors, result.nestedRequires)
      of "task":
        if n.len >= 3 and n[1].kind == nkIdent and
            n[2].kind in {nkStrLit .. nkTripleStrLit}:
          result.tasks.add((n[1].ident.s, n[2].strVal))
      of "before", "after":
        if n.len >= 3 and n[1].kind == nkIdent and n[1].ident.s == "install":
          result.hasInstallHooks = true
      else:
        discard
  of nkAsgn, nkFastAsgn:
    if n[0].kind == nkIdent and eqIdent(n[0].ident.s, "srcDir"):
      if n[1].kind in {nkStrLit .. nkTripleStrLit}:
        result.srcDir = n[1].strVal
      else:
        localError(conf, n[1].info, "assignments to 'srcDir' must be string literals")
        result.hasErrors = true
    elif n[0].kind == nkIdent and eqIdent(n[0].ident.s, "version"):
      if n[1].kind in {nkStrLit .. nkTripleStrLit}:
        result.version = n[1].strVal
      else:
        localError(conf, n[1].info, "assignments to 'version' must be string literals")
        result.hasErrors = true
    elif n[0].kind == nkIdent and eqIdent(n[0].ident.s, "license"):
      if n[1].kind in {nkStrLit .. nkTripleStrLit}:
        result.license = n[1].strVal
      else:
        localError(conf, n[1].info, "assignments to 'license' must be string literals")
        result.hasErrors = true
    elif n[0].kind == nkIdent and eqIdent(n[0].ident.s, "backend"):
      if n[1].kind in {nkStrLit .. nkTripleStrLit}:
        result.backend = n[1].strVal
      else:
        localError(conf, n[1].info, "assignments to 'backend' must be string literals")
        result.hasErrors = true
    elif n[0].kind == nkIdent and eqIdent(n[0].ident.s, "bin"):
      let binSeq = extractSeqLiteral(n[1], conf, "bin")
      for bin in binSeq:
        when defined(windows):
          var bin = bin & ".exe"
          result.bin[bin] = bin
        else:
          result.bin[bin] = bin
    else:
      discard
  else:
    discard

proc isNimbleFileNim(nimbleFilePath: string): bool =
  let file = nimbleFilePath.splitFile
  let nimbleFile = file.name & file.ext
  nimbleFile == "nim.nimble"

proc getNimCompilationPath*(nimbleFile: string): string =
  ## Extracts the path to the Nim compilation.nim file from the nimble file
  var conf = newConfigRef()
  conf.foreignPackageNotes = {}
  conf.notes = {}
  conf.mainPackageNotes = {}
  conf.errorMax = high(int)

  let fileIdx = fileInfoIdx(conf, AbsoluteFile nimbleFile)
  var parser: Parser
  var includePath = ""
  if setupParser(parser, fileIdx, newIdentCache(), conf):
    let ast = parseAll(parser)
    proc findIncludePath(n: PNode) =
      case n.kind
      of nkStmtList, nkStmtListExpr:
        for child in n:
          findIncludePath(child)
      of nkIncludeStmt:
        # Found an include statement
        if n.len > 0 and n[0].kind in {nkStrLit .. nkTripleStrLit}:
          includePath = n[0].strVal
          # echo "Found include: ", includePath
      else:
        for i in 0 ..< n.safeLen:
          findIncludePath(n[i])

    findIncludePath(ast)
    closeParser(parser)

  if includePath.len > 0:
    if includePath.contains("compilation.nim"):
      result = nimbleFile.parentDir / includePath

proc extractNimVersion*(nimbleFile: string): string =
  ## Extracts Nim version numbers from the system's compilation.nim file
  ## using the compiler API.
  var compilationPath = getNimCompilationPath(nimbleFile)

  if not fileExists(compilationPath):
    return ""
  # Now parse the compilation.nim file to get version numbers
  var major, minor, patch = 0

  var conf = newConfigRef()
  conf.foreignPackageNotes = {}
  conf.notes = {}
  conf.mainPackageNotes = {}
  conf.errorMax = high(int)

  let compFileIdx = fileInfoIdx(conf, AbsoluteFile compilationPath)
  var parser: Parser

  if setupParser(parser, compFileIdx, newIdentCache(), conf):
    let ast = parseAll(parser)

    # Process AST to find NimMajor, NimMinor, NimPatch definitions
    proc processNode(n: PNode) =
      case n.kind
      of nkStmtList, nkStmtListExpr:
        for child in n:
          processNode(child)
      of nkConstSection:
        for child in n:
          if child.kind == nkConstDef:
            var identName = ""
            case child[0].kind
            of nkPostfix:
              if child[0][1].kind == nkIdent:
                identName = child[0][1].ident.s
            of nkIdent:
              identName = child[0].ident.s
            of nkPragmaExpr:
              # Handle pragma expression (like NimMajor* {.intdefine.})
              if child[0][0].kind == nkIdent:
                identName = child[0][0].ident.s
              elif child[0][0].kind == nkPostfix and child[0][0][1].kind == nkIdent:
                identName = child[0][0][1].ident.s
            else:
              discard # echo "Unhandled node kind for const name: ", child[0].kind
            # Extract value
            if child.len > 2:
              case child[2].kind
              of nkIntLit:
                let value = child[2].intVal.int
                case identName
                of "NimMajor":
                  major = value
                of "NimMinor":
                  minor = value
                of "NimPatch":
                  patch = value
                else:
                  discard
              else:
                discard
      else:
        discard

    processNode(ast)
    closeParser(parser)
  # echo "Extracted version: ", major, ".", minor, ".", patch
  return &"{major}.{minor}.{patch}"

proc extractRequiresInfo*(nimbleFile: string): NimbleFileInfo =
  ## Extract the `requires` information from a Nimble file. This does **not**
  ## evaluate the Nimble file. Errors are produced on stderr/stdout and are
  ## formatted as the Nim compiler does it. The parser uses the Nim compiler
  ## as an API. The result can be empty, this is not an error, only parsing
  ## errors are reported.
  result.nimbleFile = nimbleFile
  if isNimbleFileNim(nimbleFile):
    let nimVersion = extractNimVersion(nimbleFile)
    result.version = nimVersion
    return result
  var conf = newConfigRef()
  conf.foreignPackageNotes = {}
  conf.notes = {}
  conf.mainPackageNotes = {}
  conf.errorMax = high(int)
  conf.structuredErrorHook = proc(
      config: ConfigRef, info: TLineInfo, msg: string, severity: Severity
  ) {.gcsafe.} =
    localError(config, info, warnUser, msg)

  let fileIdx = fileInfoIdx(conf, AbsoluteFile nimbleFile)
  var parser: Parser
  if setupParser(parser, fileIdx, newIdentCache(), conf):
    let ast = parseAll(parser)
    extract(ast, conf, result)
    closeParser(parser)
  result.hasErrors = result.hasErrors or conf.errorCounter > 0
