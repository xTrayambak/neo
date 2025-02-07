type
  PackageListItem* = object
    name*, url*, `method`*: string
    tags: seq[string]
    description*: string
    license*: string
    web*: string

  PackageList* = seq[PackageListItem]
