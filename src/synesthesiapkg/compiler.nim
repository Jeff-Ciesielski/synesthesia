#!/usr/bin/env nimr
import macros
import sequtils
import strformat
import tables
import random

import common
import optimizer

template doWhile*(a: typed, b: untyped): untyped =
  while true:
    b
    if not a:
      break

template loopBlock*(a: typed, b: untyped): untyped =
  if a != 0:
    doWhile(a != 0):
      b

proc readCharacter*(): int =
  var tempMem: array[1, char]
  discard stdin.readChars(tempMem, 0, 1)
  tempMem[0].int

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

proc genMemSet(offset, amt: int): NimNode =
  nnkStmtList.newTree(
    nnkAsgn.newTree(
      nnkBracketExpr.newTree(
        nnkDotExpr.newTree(
          newIdentNode("core"),
          newIdentNode("memory")
        ),
        nnkInfix.newTree(
          newIdentNode("+"),
          nnkDotExpr.newTree(
            newIdentNode("core"),
            newIdentNode("ap")
          ),
          newIntLitNode(offset)
        )
      ),
      newIntLitNode(amt)
    )
  )

proc genMul(x, y: int): NimNode =
  nnkStmtList.newTree(
    nnkInfix.newTree(
      newIdentNode("+="),
      nnkBracketExpr.newTree(
        nnkDotExpr.newTree(
          newIdentNode("core"),
          newIdentNode("memory")
        ),
        nnkInfix.newTree(
          newIdentNode("+"),
          nnkDotExpr.newTree(
            newIdentNode("core"),
            newIdentNode("ap")
          ),
          newIntLitNode(x)
        )
      ),
      nnkInfix.newTree(
        newIdentNode("*"),
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
        newIntLitNode(y)
      )
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


proc genMemAdjust(amount: int, offset: int): NimNode =
  nnkStmtList.newTree(
    nnkInfix.newTree(
      newIdentNode("+="),
      nnkBracketExpr.newTree(
        nnkDotExpr.newTree(
          newIdentNode("core"),
          newIdentNode("memory")
        ),
        nnkInfix.newTree(
          newIdentNode("+"),
          nnkDotExpr.newTree(
            newIdentNode("core"),
            newIdentNode("ap")
          ),
          newLit(offset)
        )
      ),
      newLit(amount)
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

proc genRead(): NimNode =
  nnkStmtList.newTree(
    nnkAsgn.newTree(
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
      nnkCall.newTree(
        newIdentNode("readCharacter")
      )
    )
  )

macro compile*(fileName: string): untyped =
  var
    blockStack = @[genInitialBlock()]
    blockCount: int = 1
  let
    program = slurp(fileName.strVal)
    instructions = toSeq(program.items)
    symbols = map(instructions, proc(x: char): BFSymbol = charToSymbol(x))
    # Order of operations here is important! We're iteratively
    # improving the patterns that are generated!
    optimized = symbols.applyAllOptimizations()

  echo &"Reduced instruction count by {100.0 - (optimized.len/symbols.len)*100}% {symbols.len} => {optimized.len}"
  echo "generating nim AST"
  for sym in optimized:
    case sym.kind
    of bfsApAdjust:
      blockStack[^1] <- genApAdjust(sym.amt)
    of bfsMemAdjust:
      blockStack[^1] <- genMemAdjust(sym.amt, sym.offset)
    of bfsPrint:
      blockStack[^1] <- genPrintMemory()
    of bfsRead:
      blockStack[^1] <- genRead()
    of bfsBlock:
      let blk = genBlock(blockCount)
      blockStack[^1] <- blk
      blockStack &= blk
      inc blockCount
    of bfsBlockEnd:
      blockStack = blockStack[0.. ^2]
    of bfsMemSet:
      blockstack[^1] <- genMemSet(sym.offset, sym.amt)
    of bfsMul:
      blockstack[^1] <- genMul(sym.offset, sym.amt)
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
