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
    of bfsApAdjust, bfsMemAdjust, bfsMul:
      amt*: int
      offset*: int
    of bfsBlock:
      statements*: seq[BFSymbol]
    else: discard

proc charToSymbol*(c: char): BFSymbol =
  case c
  of '>': BFSymbol(kind: bfsApAdjust, amt: 1)
  of '<': BFSymbol(kind: bfsApAdjust, amt: -1)
  of '+': BFSymbol(kind: bfsMemAdjust, amt: 1)
  of '-': BFSymbol(kind: bfsMemAdjust, amt: -1)
  of '.': BFSymbol(kind: bfsPrint)
  of ',': BFSymbol(kind: bfsRead)
  of '[': BFSymbol(kind: bfsBlock, statements: @[])
  of ']': BFSymbol(kind: bfsBlockEnd)
  else:   BFSymbol(kind: bfsNoOp)
