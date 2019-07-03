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
    bfsMemAdd
    bfsNoOp

  BFSymbol* = object of RootObj
    case kind*: BFSymbolKind
    of bfsApAdjust, bfsMemAdjust, bfsMul, bfsMemSet, bfsMemAdd:
      amt*: int
      offset*: int
      secondOffset*: int
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
    of bfsMul: &"mul {s.offset}, {s.secondOffset}, {s.amt}"
    of bfsMemAdd: &"madd {s.offset}, {s.secondOffset}"
    of bfsNoOp: "noop"
