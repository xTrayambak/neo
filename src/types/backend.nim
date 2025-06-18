type Backend* {.pure.} = enum
  C
  Cpp
  JavaScript
  ObjectiveC

func `$`*(backend: Backend): string =
  case backend
  of Backend.C:
    return "c"
  of Backend.Cpp:
    return "cpp"
  of Backend.JavaScript:
    return "js"
  of Backend.ObjectiveC:
    return "objc"

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
