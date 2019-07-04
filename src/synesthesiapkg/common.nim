import strformat

type
  BFCore* = ref object
   memory*: array[1024, int]
   pc*, ap*: int

  BFTokenKind* = enum
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

  BFToken* = object of RootObj
    case kind*: BFTokenKind
    of bfsApAdjust, bfsMemAdjust, bfsMul, bfsMemSet, bfsMemAdd:
      amt*: int
      offset*: int
      secondOffset*: int
    of bfsBlock:
      statements*: seq[BFToken]
    else: discard

proc charToToken*(c: char): BFToken =
  case c
  of '>': BFToken(kind: bfsApAdjust, amt: 1)
  of '<': BFToken(kind: bfsApAdjust, amt: -1)
  of '+': BFToken(kind: bfsMemAdjust, amt: 1)
  of '-': BFToken(kind: bfsMemAdjust, amt: -1)
  of '.': BFToken(kind: bfsPrint)
  of ',': BFToken(kind: bfsRead)
  of '[': BFToken(kind: bfsBlock, statements: @[])
  of ']': BFToken(kind: bfsBlockEnd)
  else:   BFToken(kind: bfsNoOp)

proc symbolToOpCode*(s: BFToken): string =
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
