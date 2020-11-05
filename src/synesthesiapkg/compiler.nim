#!/usr/bin/env nimr
import macros
import sequtils
import strformat

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
proc genInitialBlock(apOffset: int): NimNode =
  let
    core = newIdentNode("core")
  quote do:
      block bfProg:
        var `core`= BFCore(ap:`apOffset`)

## Generates a print instruction
## stdout.write(core.memory[core.ap].char)
proc genPrintMemory(): NimNode =
  quote do:
    stdout.write(core.memory[core.ap].char)

## Generates a memSet instruction
## core.memory[core.ap + <offset>] = <amt>
proc genMemSet(offset, amt: int): NimNode =
  quote do:
    core.memory[core.ap + `offset`] = `amt`

## Generates a multiplication instruction
## core.memory[core.ap + <x>] += core.memory[core.ap + y] * <z>
proc genMul(x, y, z: int): NimNode =
  quote do:
    core.memory[core.ap + `x`] += core.memory[core.ap + `y`] * cast[uint8](`z`)

## Generates a memory add instruction
## core.memory[core.ap + <x>] += core.memory[core.ap + y]
proc genMemAdd(x, y: int): NimNode =
  quote do:
    core.memory[core.ap + `x`] += core.memory[core.ap + `y`]

## Generates an AP adjust
## core.ap += <amount>
proc genApAdjust(amount: int): NimNode =
  quote do:
    core.ap += `amount`

## Generates a memory adjust
## core.memory[core.ap + <offset>] += <amount>
proc genMemAdjust(amount: int, offset: int): NimNode =
  quote do:
    core.memory[core.ap + `offset`] += cast[uint8](`amount`)

## Generates a new loop block
## loopBlock(core.memory[core.ap]):
##   <statements>
proc genBlock(id: int): NimNode =
  let statements = newStmtList()

  quote do:
    loopBlock(core.memory[core.ap]):
      `statements`

## Generates a read instruction
## core.memory[core.ap] = readCharacter()
proc genRead(): NimNode =
  quote do:
    core.memory[core.ap] = readCharacter()

macro compile*(fileName: string): untyped =
  let
    program = slurp(fileName.strVal)
    instructions = toSeq(program.items)
    tokens = map(instructions, proc(x: char): BFToken = charToToken(x))
    optimized = tokens.applyAllOptimizations()

  # TODO: Roll this into the optimization pass?
  # find the lowest offset and offset our initial AP by at least that much
  var minOffset: int = 0
  for sym in optimized:
    case sym.kind
    of bfsApAdjust, bfsMemAdjust, bfsMul, bfsMemSet, bfsMemAdd:
      minOffset = min(minOffset, sym.offset)
      minOffset = min(minOffset, sym.secondOffset)
    else: discard


  echo &"Reduced instruction count by {100.0 - (optimized.len/tokens.len)*100}% {tokens.len} => {optimized.len}"
  echo &"Adjusting initial ap by {abs(minOffset)+1} to account for negative indices"
  var
    blockStack = @[genInitialBlock(abs(minOffset) + 1)]
    blockCount: int = 1

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

  result = newStmtList().add(blockStack[0])
  writeFile("opcodes.bfv", opcodes)
