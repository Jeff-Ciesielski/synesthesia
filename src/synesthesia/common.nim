type
  BFCore* = ref object
   memory*: array[1024, uint8]
   pc*, ap*: int

  BFSymbolKind* = enum
    bfsApAdjust,
    bfsMemAdjust,
    bfsPrint,
    bfsRead,
    bfsBlock,
    bfsBlockEnd,
    bfsMemZero,
    bfsNoOp

  BFSymbol* = object of RootObj
    case kind*: BFSymbolKind
    of bfsApAdjust, bfsMemAdjust:
      amt*: int
    of bfsBlock:
      statements*: seq[BFSymbol]
    else: discard
