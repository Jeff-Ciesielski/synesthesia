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
  if a != 0:
    doWhile(a != 0):
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
  var i = 0

  while i < symbols.len:
    if (i < symbols.high and symbols[i].kind == bfsBlock and
        (symbols[i+1].kind == bfsMemAdjust and symbols[i+1].amt == -1) and
        symbols[i+2].kind == bfsBlockEnd):
      result &= BFSymbol(kind: bfsMemZero)
      i += 3
    else:
      result &= symbols[i]
      inc i

proc generateDeferredMovements(symbols: seq[BFSymbol]): seq[BFSymbol] =
  echo "Optimizing out unnecessary AP Movement"
  result = @[]

  var
    i = 0
    totalOffset = 0
    accum: seq[BFSymbol] = @[]

  while i < symbols.len:
    if symbols[i].kind == bfsMemAdjust:
      result &= BFSymbol(kind: bfsMemAdjust,
                         amt: symbols[i].amt,
                         offset: totalOffset)
    elif symbols[i].kind == bfsApAdjust:
      totalOffset += symbols[i].amt
    else:
      result &= BFSymbol(kind: bfsApAdjust,
                         amt: totalOffset)
      totalOffset = 0
      result &= symbols[i]
    inc i

## Condenses multiplication loops into multiplication instructions
## i.e. [->+++>+++<<] becomes two multiplications: Mul 1,3 and Mul 2,3
proc generateMulLoops(symbols: seq[BFSymbol]): seq[BFSymbol] =
  echo "Optimizing Multiply Loops"
  result = @[]
  var
    i = 0
    j = 0
    inLoop = false
    totalOffset = 0
    mulStk: seq[BFSymbol] = @[]

  while i < symbols.len:
    if (i < symbols.high and symbols[i].kind == bfsBlock and
        (symbols[i+1].kind == bfsMemAdjust and symbols[i+1].amt == -1)):
      totalOffset = 0
      mulStk = @[]
      j = i
      i += 2
      inLoop = false
      while true:
        let
          s1 = symbols[i]
          s2 = symbols[i+1]
        if ((s1.kind == bfsApAdjust) and
            (s2.kind == bfsMemAdjust)):
          let y = s2.amt

          totalOffset += s1.amt


          mulStk &= BFSymbol(kind:bfsMul,
                             x: totalOffset,
                             y: y)
          i += 2
          inLoop = true
        elif ((s1.kind == bfsApAdjust and
               (s1.amt + totalOffset == 0)) and
              s2.kind == bfsBlockEnd and inLoop):
          result &= mulStk
          result &= BFSymbol(kind: bfsMemZero)
          i += 2
          break
        else:
          i = j
          result &= symbols[i]
          inc i
          break
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
    optimized = (
      symbols
      .coalesceAdjustments
      .generateMemZeroes
      .generateMulLoops
      .generateDeferredMovements
    )

  echo &"Reduced instruction count by {100.0 - (optimized.len/symbols.len)*100}%"
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
      echo "read memory"
    of bfsBlock:
      let blk = genBlock(blockCount)
      blockStack[^1] <- blk
      blockStack &= blk
      inc blockCount
    of bfsBlockEnd:
      blockStack = blockStack[0.. ^2]
    of bfsMemZero:
      blockstack[^1] <- genMemZero()
    of bfsMul:
      blockstack[^1] <- genMul(sym.x, sym.y)
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
