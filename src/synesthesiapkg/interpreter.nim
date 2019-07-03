import common
import tables
import sequtils
import optimizer

proc interpret*(bf: BFCore, program: string, optimize:bool=false) =
  var
    jumpTbl = initTable[int, int]()
    jumpStk: seq[int] = @[]
    symbols = if optimize:
                (map(program, proc(x: char): BFSymbol = charToSymbol(x))
                .applyAllOptimizations)
              else:
                map(program, proc(x: char): BFSymbol = charToSymbol(x))    
    tempMem: array[1, char]

  # Before we start, pre-compute a jump table
  for pc, sym in symbols:
    case sym.kind
    of bfsBlock:
      jumpStk &= pc
    of bfsBlockEnd:
      let fjp = jumpStk[^1]
      jumpStk = jumpStk[0.. ^2]
      jumpTbl[pc] = fjp
      jumpTbl[fjp] = pc
    else: discard

  # Clear out our core state
  bf.pc = 0
  bf.ap = 0
  for cell in bf.memory.mitems:
    cell = 0

  # Do the business
  while bf.pc <= symbols.high:
    case symbols[bf.pc].kind
    of bfsApAdjust:
      bf.ap += symbols[bf.pc].amt
    of bfsMemAdjust:
      bf.memory[bf.ap + symbols[bf.pc].offset] += symbols[bf.pc].amt
    of bfsPrint:
      stdout.write bf.memory[bf.ap].char
    of bfsRead:
      discard stdin.readChars(tempMem, 0, 1)
      bf.memory[bf.ap] = tempMem[0].int
    of bfsBlock:
      if bf.memory[bf.ap] == 0:
        bf.pc = jumpTbl[bf.pc]
    of bfsBlockEnd:
      if bf.memory[bf.ap] != 0:
        bf.pc = jumpTbl[bf.pc]
    of bfsMemSet:
      bf.memory[bf.ap + symbols[bf.pc].offset] = symbols[bf.pc].amt
    of bfsMul:
      bf.memory[bf.ap + symbols[bf.pc].offset] += bf.memory[bf.ap + symbols[bf.pc].secondOffset] * symbols[bf.pc].amt
    of bfsMemAdd:
      bf.memory[bf.ap + symbols[bf.pc].offset] += bf.memory[bf.ap + symbols[bf.pc].secondOffset]
    of bfsNoOp: discard
    inc bf.pc

  stdout.flushFile()

when isMainModule:
  var c = BFCore()
  c.interpret(readFile("helloworld.bf"))
