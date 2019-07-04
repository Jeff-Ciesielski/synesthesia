#!/usr/bin/env nimr
import macros
import sequtils
import strformat
import tables
import random

import common
import optimizer

# A bit of a hack, but doWhile and loopBlock unroll to the following:
# if a != 0:
#   while true:
#     b
#     if not a:
#       break # (breaks out beyond the while true)

# This was found to be much faster than simply wrapping the entire
# statement in `while a != 0`.  I believe that this is a quirk of nim
# 0.18, and will investigate in the future.

template doWhile*(a: typed, b: untyped): untyped =
  while true:
    b
    if not a:
      break

template loopBlock*(a: typed, b: untyped): untyped =
  if a != 0:
    doWhile(a != 0):
      b

## Helper code that is used by the compiler to simplify AST generation
proc readCharacter*(): int =
  var tempMem: array[1, char]
  discard stdin.readChars(tempMem, 0, 1)
  tempMem[0].int

## A helper for adding additional child statements to specific nimnode
## types. (cleans up the AST generating code)
proc `<-`(a, b: NimNode) =
  case a.kind
  of nnkBlockStmt:
    a[1].add(b)
  of nnkCall:
    a[2].add(b)
  else:
    echo "wtf"

## Generates a lexical block that all other code will live inside
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

## Generates a print instruction
## stdout.write(core.memory[core.ap].char)
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

## Generates a memSet instruction
## core.memory[core.ap + <offset>] = <amt>
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

## Generates a multiplication instruction
## core.memory[core.ap + <x>] += core.memory[core.ap + y] * <z>
proc genMul(x, y, z: int): NimNode =
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
          nnkInfix.newTree(
            newIdentNode("+"),
            nnkDotExpr.newTree(
              newIdentNode("core"),
              newIdentNode("ap")
            ),
            newIntLitNode(y)
          )
        ),
        newIntLitNode(z)
      )
    )
  )


## Generates a memory add instruction
## core.memory[core.ap + <x>] += core.memory[core.ap + y]
proc genMemAdd(x, y: int): NimNode =
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
          newIntLitNode(y)
        )
      )
    )
   )

## Generates an AP adjust
## core.ap += <amount>
proc genApAdjust(amount: int): NimNode =
  nnkInfix.newTree(
    newIdentNode("+="),
    nnkDotExpr.newTree(
      newIdentNode("core"),
      newIdentNode("ap")
    ),
    newLit(amount)
  )

## Generates a memory adjust
## core.memory[core.ap + <offset>] += <amount>
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

## Generates a new loop block
## loopBlock(core.memory[core.ap]):
##   <statements>
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

## Generates a read instruction
## core.memory[core.ap] = readCharacter()
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
    tokens = map(instructions, proc(x: char): BFToken = charToToken(x))
    optimized = tokens.applyAllOptimizations()

  echo &"Reduced instruction count by {100.0 - (optimized.len/tokens.len)*100}% {tokens.len} => {optimized.len}"
  echo "generating nim AST"
  var opcodes = ""
  for sym in optimized:
    opcodes &= &"{sym.symbolToOpCode()}\n"
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
      blockstack[^1] <- genMul(sym.offset, sym.secondOffset, sym.amt)
    of bfsMemAdd:
      blockstack[^1] <- genMemAdd(sym.offset, sym.secondOffset)
    of bfsNoOp: discard
    else: discard

  result = newStmtList().add(blockStack[0])
  writeFile("opcodes.bfv", opcodes)

# Example output:
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
