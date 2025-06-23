import std/strutils

type Backend* {.pure.} = enum
  C
  Cpp
  JavaScript
  ObjectiveC

func toBackend*(value: string): Backend =
  case toLowerAscii(value)
  of "c":
    Backend.C
  of "cpp":
    Backend.Cpp
  of "js":
    Backend.JavaScript
  of "objc":
    Backend.ObjectiveC
  else:
    raise newException(ValueError, "Invalid backend string: `" & value & '`')

func `$`*(backend: Backend): string =
  case backend
  of Backend.C:
    return "C"
  of Backend.Cpp:
    return "Cpp"
  of Backend.JavaScript:
    return "JavaScript"
  of Backend.ObjectiveC:
    return "ObjectiveC"

func toHumanString*(backend: Backend): string =
  case backend
  of Backend.C:
    return "C"
  of Backend.Cpp:
    return "C++"
  of Backend.JavaScript:
    return "JavaScript"
  of Backend.ObjectiveC:
    return "Objective C"
