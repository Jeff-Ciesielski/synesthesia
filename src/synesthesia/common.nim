type
  BFCore* = ref object
   memory*: array[1024, int]
   pc*, ap*: int

  BFSymbolKind* = enum
    bfsApAdjust,
    bfsMemAdjust,
    bfsPrint,
    bfsRead,
    bfsBlock,
    bfsBlockEnd,
    bfsMemZero,
    bfsMul,
    bfsNoOp

  BFSymbol* = object of RootObj
    case kind*: BFSymbolKind
    of bfsApAdjust, bfsMemAdjust:
      amt*: int
    of bfsBlock:
      statements*: seq[BFSymbol]
    of bfsMul:
      x*: int
      y*: int
    else: discard
