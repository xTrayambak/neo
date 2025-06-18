import std/options

type
  PackageListItem* = object
    name*, url*, `method`*: string
    tags*: seq[string]
    description*: string
    license*: string
    web*: string

  PackageList* = seq[PackageListItem]

func find*(list: PackageList, name: string): Option[PackageListItem] {.inline.} =
  for item in list:
    if item.name != name:
      continue

    return some(item)
