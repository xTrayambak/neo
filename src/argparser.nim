## Argument parser for Neo, based on `std/parseopt`
import std/[os, parseopt, logging, tables, strutils, options]
import pkg/[shakar]

type Input* = object
  command*: string
  arguments*: seq[string]
  flags*: Table[string, string]
  switches*: seq[string]

proc enabled*(input: Input, switch: string): bool {.inline.} =
  input.switches.contains(switch)

proc enabled*(input: Input, switchBig, switchSmall: string): bool {.inline.} =
  input.switches.contains(switchBig) or input.switches.contains(switchSmall)

proc flag*(input: Input, value: string): Option[string] {.inline.} =
  if input.flags.contains(value):
    return some(input.flags[value])

proc flagAsInt*(input: Input, value: string): Option[int] {.inline.} =
  let flag = input.flag(value)

  if !flag:
    return none(int)

  try:
    return some(parseInt(&flag))
  except ValueError:
    return none(int)

proc parseInput*(): Input {.inline.} =
  var
    foundCmd = false
    input: Input

  let params = commandLineParams()

  debug "argparser: params string is `" & params & "`"

  var parser = initOptParser(params)
  while true:
    parser.next()
    case parser.kind
    of cmdEnd:
      debug "argparser: hit end of argument stream"
      break
    of cmdShortOption, cmdLongOption:
      if parser.val.len < 1:
        debug "argparser: found switch: " & parser.key
        input.switches &= parser.key
      else:
        debug "argparser: found flag: " & parser.key & '=' & parser.val
        input.flags[parser.key] = parser.val
    of cmdArgument:
      if not foundCmd:
        debug "argparser: found command: " & parser.key
        input.command = parser.key
        foundCmd = true
      else:
        debug "argparser: found argument: " & parser.key
        input.arguments &= parser.key

  input
