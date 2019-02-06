#!/usr/bin/env nimr
import macros
import sequtils
import strformat
import tables
import common

template doWhile*(a: typed, b: untyped): untyped =
  while true:
    b
    if not a:
      break

template loopBlock*(a: typed, b: untyped): untyped =
  if a != 0.uint8:
    doWhile(a != 0.uint8):
      b

proc `<-`(a, b: NimNode) =
  case a.kind
  of nnkBlockStmt:
    a[1].add(b)
  of nnkCall:
    a[2].add(b)
  else:
    echo "wtf"

proc genInitialBlock(): NimNode =
  nnkBlockStmt.newTree(
    newIdentNode("bfProg"),
    nnkStmtList.newTree(
      nnkVarSection.newTree(
        nnkIdentDefs.newTree(
          newIdentNode("core"),
          newEmptyNode(),
          nnkCall.newTree(
            newIdentNode("BFCore")
          )
        )
      )
    )
  )

proc genPrintMemory(): NimNode =
  nnkCommand.newTree(
    nnkDotExpr.newTree(
      newIdentNode("stdout"),
        newIdentNode("write")
      ),
      nnkDotExpr.newTree(
        nnkBracketExpr.newTree(
          nnkDotExpr.newTree(
            newIdentNode("core"),
            newIdentNode("memory")
          ),
          nnkDotExpr.newTree(
            newIdentNode("core"),
            newIdentNode("ap")
          )
        ),
        newIdentNode("char")
      )
    )

proc genMemZero(): NimNode =
  nnkInfix.newTree(
    newIdentNode("="),
    nnkBracketExpr.newTree(
      nnkDotExpr.newTree(
        newIdentNode("core"),
        newIdentNode("memory")
      ),
      nnkDotExpr.newTree(
        newIdentNode("core"),
        newIdentNode("ap")
      )
    ),
    newIntLitNode(0)
  )

proc genApAdjust(amount: int): NimNode =
  nnkInfix.newTree(
    newIdentNode("+="),
    nnkDotExpr.newTree(
      newIdentNode("core"),
      newIdentNode("ap")
    ),
    newLit(amount)
  )

proc intToU8(a: int): int =
  if a > 255:
    result = (a mod 256)
  elif a < 0:
    result = (256 + a)
  else:
    result = a

proc genMemAdjust(amount: int): NimNode =
  nnkInfix.newTree(
    newIdentNode("+="),
    nnkBracketExpr.newTree(
      nnkDotExpr.newTree(
        newIdentNode("core"),
        newIdentNode("memory")
      ),
      nnkDotExpr.newTree(
        newIdentNode("core"),
        newIdentNode("ap")
      )
    ),
    nnkDotExpr.newTree(
      newIntLitNode(amount.intToU8()),
      newIdentNode("uint8")
    )
  )

proc genBlock(id: int): NimNode =
  nnkCall.newTree(
    newIdentNode("loopBlock"),
    nnkBracketExpr.newTree(
      nnkDotExpr.newTree(
        newIdentNode("core"),
        newIdentNode("memory")
      ),
      nnkDotExpr.newTree(
        newIdentNode("core"),
        newIdentNode("ap")
      )
    ),
    newStmtList()
  )

proc charToSymbol(c: char): BFSymbol =
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

## Our first simple optimization is the coalescing of adjacent memory
## and pointer adjustments.  e.g. +++++ is actually +5, so we can
## execute a single +5 instruction rather than five +1 instructions
## (same goes for memory adjustments > and <)
proc coalesceAdjustments(symbols: seq[BFSymbol]): seq[BFSymbol] =
  echo "Coalescing memory adjustments"
  result = @[]

  result &= symbols[0]

  for sym in symbols[1.. ^1]:
    case sym.kind
    of bfsApAdjust, bfsMemAdjust:
      if sym.kind == result[^1].kind:
        result[^1].amt += sym.amt
      else:
        result &= sym
    else: result &= sym

## Our next optimizaiton is the generation of 'MemZero' commands. The
## pattern `[-]` is very common in BF programming, and essentially
## means loop on the current memory location until it reaches zero,
## and then continue.  We can skip all those nasty branches with a simple set
proc generateMemZeroes(symbols: seq[BFSymbol]): seq[BFSymbol] =
  echo "Optimizing memory zero-sets"
  result = @[]
  var
    i = 0

  while i < symbols.len - 2:
    let scratch = symbols[i..i+2]
    if (scratch[0].kind == bfsBlock and
        (scratch[1].kind == bfsMemAdjust and scratch[1].amt == -1) and
        scratch[2].kind == bfsBlockEnd):
      result &= BFSymbol(kind: bfsMemZero)
      i += 3
    else:
      result &= symbols[i]
      inc i

macro compile*(fileName: string): untyped =
  var
    blockStack = @[genInitialBlock()]
    blockCount: int = 1
  let
    program = slurp(fileName.strVal)
    instructions = toSeq(program.items)
    symbols = map(instructions, proc(x: char): BFSymbol = charToSymbol(x))
    coalesced = coalesceAdjustments(symbols)
    withMemZero = generateMemZeroes(coalesced)

  echo "generating nim AST"
  for sym in withMemZero:
    case sym.kind
    of bfsApAdjust:
      blockStack[^1] <- genApAdjust(sym.amt)
    of bfsMemAdjust:
      blockStack[^1] <- genMemAdjust(sym.amt)
    of bfsPrint:
      blockStack[^1] <- genPrintMemory()
    of bfsRead:
      echo "read memory"
    of bfsBlock:
      let blk = genBlock(blockCount)
      blockStack[^1] <- blk
      blockStack &= blk
      inc blockCount
    of bfsBlockEnd:
      blockStack = blockStack[0.. ^2]
    of bfsMemZEro:
      blockstack[^1] <- genMemZero()
    of bfsNoOp: discard
    else: discard

  result = newStmtList().add(blockStack[0])
  #echo result.treeRepr


# +[>+[.]]
#dumpAstGen:
#dumpTree:
#  block bfProg:
#    var
#      core = BFCore()
#      register: int
#    inc core.memory[core.ap]
#    loopBlock(b1, core.memory[core.ap]):
#      core.ap += 1
#      register = 1
#      core.memory[core.ap] += register.uint8
#      loopBlock(b2, core.memory[core.ap]):
#        stdout.write core.memory[core.ap].char
#        stdout.flushFile()
