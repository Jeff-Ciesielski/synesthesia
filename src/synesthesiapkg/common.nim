import strformat

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
    bfsMemSet,
    bfsMul,
    bfsNoOp

  BFSymbol* = object of RootObj
    case kind*: BFSymbolKind
    of bfsApAdjust, bfsMemAdjust, bfsMul, bfsMemSet:
      amt*: int
      offset*: int
      mulOffs*: int
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

proc symbolToOpCode*(s: BFSymbol): string =
  case s.kind
    of bfsApAdjust: &"pa {s.amt}"
    of bfsMemAdjust: &"ma {s.offset}, {s.amt}"
    of bfsPrint: "p"
    of bfsRead: "r"
    of bfsBlock: "bs"
    of bfsBlockEnd: "be"
    of bfsMemSet: &"ms {s.offset}, {s.amt}"
    of bfsMul: &"mul {s.offset}, {s.mulOffs}, {s.amt}"
    of bfsNoOp: "noop"
