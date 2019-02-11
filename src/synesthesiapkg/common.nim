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
    bfsNoOp

  BFToken* = object of RootObj
    case kind*: BFTokenKind
    of bfsApAdjust, bfsMemAdjust, bfsMul, bfsMemSet:
      amt*: int
      offset*: int
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
