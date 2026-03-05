## Argument parser for Neo, based on `std/parseopt`
import std/[os, parseopt, tables, strutils, options]
import pkg/[shakar, pretty]

type Input* = object
  command*: string
  arguments*: seq[string]
  flags*: Table[string, string]
  switches*: seq[string]
  
  # Flags not meant for Neo, rather to be passed to whatever program (usually the Nim compiler)
  # which Neo ends up calling.
  forwardedFlags*: Table[string, string]

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

  var parser = initOptParser(params)
  while true:
    parser.next()
    case parser.kind
    of cmdEnd:
      break
    of cmdShortOption, cmdLongOption:
      if parser.val.len < 1:
        input.switches &= parser.key
      else:
        if input.command.len < 1:
          input.flags[parser.key] = parser.val
        else:
          input.forwardedFlags[parser.key] = parser.val
    of cmdArgument:
      if not foundCmd:
        input.command = parser.key
        foundCmd = true
      else:
        input.arguments &= parser.key
  
  print input
  input
