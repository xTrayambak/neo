## Output manager
import std/[strutils, posix]
import pkg/[noise, semver]

var hasColorSupport* {.global.} = isatty(stdout)

const
  ColorTable = {
    "<green>": "\x1b[32m",
    "<red>": "\x1b[38;5;1m",
    "<yellow>": "\x1b[38;5;3m",
    "<blue>": "\x1b[38;5;4m",
    "<reset>": "\x1b[0m",
  }
  ColorTableFallback =
    {"<green>": "", "<red>": "", "<yellow>": "", "<blue>": "", "<reset>": ""}

proc colorTagSubs*(value: string): string {.inline.} =
  value.multiReplace(if hasColorSupport: ColorTable else: ColorTableFallback)

proc displayMessage*(component: string, message: string) {.sideEffect.} =
  let
    component = component.colorTagSubs()
    message = message.colorTagSubs()

  stdout.write ' ' & component & "  " & message & '\n'

proc error*(message: string) {.sideEffect, inline.} =
  displayMessage("<red>error<reset>:", message)

proc askQuestion*[T](question: string, choices: openArray[T], default: uint): uint =
  displayMessage("<yellow>option<reset>", question)

  for i, choice in choices:
    displayMessage("  <green>" & $i & "<reset>.", $choice)

  var noise = Noise.init()
  let prompt = Styler.init(
    fgYellow,
    "Option",
    resetStyle,
    " (0 - " & $(choices.len - 1) & ", defaults to " & $default & "): ",
  )
  noise.setPrompt(prompt)

  if not noise.readLine():
    return default

  if noise.getLine().len < 1:
    return default

  let index =
    try:
      parseUint(noise.getLine())
    except ValueError as exc:
      error "invalid answer; defaulting to choice " & $(default + 1)
      default

  if index > choices.len.uint:
    error "invalid answer; defaulting to choice " & $(default + 1)
    return default

  index

proc askQuestion*(question: string, default: string = ""): string =
  displayMessage("<yellow>question<reset>", question)

  var noise = Noise.init()
  let prompt = Styler.init(
    fgYellow,
    "Answer",
    resetStyle,
    if default.len > 0:
      " (defaults to " & default & "): "
    else:
      ": ",
  )
  noise.setPrompt(prompt)

  if not noise.readLine():
    return default

  let line = noise.getLine()
  if line.len < 1:
    return default
  else:
    return line

proc askVersion*(question: string, default: Version): Version =
  ## Ask for a valid semantic version, retry if a valid one isn't given.

  try:
    return parseVersion(askQuestion(question, $default))
  except semver.ParseError as exc:
    error "cannot parse answer as version: <red>" & exc.msg & "<reset>"
    return askVersion(question, default)
