#!/usr/bin/env nimr
import macros
import sequtils
import strformat
import tables
import common

template doWhile(a: typed, b: untyped): untyped =
  while true:
    b
    if not a:
      break

template loopBlock(a: typed, b: untyped): untyped =
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

proc coalesceAdjustments(symbols: seq[BFSymbol]): seq[BFSymbol] =
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

macro compile*(fileName: string): untyped =
  var
    blockStack = @[genInitialBlock()]
    blockCount: int = 1
  let
    program = slurp(fileName.strVal)
    instructions = toSeq(program.items)
    symbols = map(instructions, proc(x: char): BFSymbol = charToSymbol(x))
    coalesced = coalesceAdjustments(symbols)

  for sym in coalesced:
    case sym.kind
    of bfsApAdjust:
      blockStack[^1] <- genApAdjust(sym.amt)
    of bfsMemAdjust:
      let memAdj = genMemAdjust(sym.amt)
      blockStack[^1] <- memAdj
    of bfsPrint:
      let print = genPrintMemory()
      blockStack[^1] <- print
    of bfsRead:
      echo "read memory"
    of bfsBlock:
      let blk = genBlock(blockCount)
      blockStack[^1] <- blk
      blockStack &= blk
      inc blockCount
    of bfsBlockEnd:
      blockStack = blockStack[0.. ^2]
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

when isMainModule:
  compile("mendelbrot.bf")
