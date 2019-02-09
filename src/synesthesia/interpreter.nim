import common
import tables
import sequtils
import optimizer

proc interpret*(bf: BFCore, program: string, optimize:bool=false) =
  # Before we start, we need to pre-calculate our jump table
  var
    jumpTbl = initTable[int, int]()
    jumpStk: seq[int] = @[]
    symbols = if optimize:
                (
                  map(program, proc(x: char): BFSymbol = charToSymbol(x))
                  .coalesceAdjustments
                  .generateMemZeroes
                  .generateMulLoops
                  .generateDeferredMovements
                )
              else:
                map(program, proc(x: char): BFSymbol = charToSymbol(x))    

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

  while bf.pc <= symbols.high:
    let sym = symbols[bf.pc]
    case sym.kind
    of bfsApAdjust: bf.ap += sym.amt
    of bfsMemAdjust: bf.memory[bf.ap + sym.offset] += sym.amt
    of bfsPrint:
      stdout.write bf.memory[bf.ap].char
      stdout.flushFile()
    of bfsRead:
      var tempMem: array[1, char]
      discard stdin.readChars(tempMem, 0, 1)
      bf.memory[bf.ap] = tempMem[0].int
    of bfsBlock:
      if bf.memory[bf.ap] == 0:
        bf.pc = jumpTbl[bf.pc]
    of bfsBlockEnd:
      if bf.memory[bf.ap] != 0:
        bf.pc = jumpTbl[bf.pc]
    of bfsMemZero: bf.memory[bf.ap] = 0
    of bfsMul: bf.memory[bf.ap + sym.x] += bf.memory[bf.ap] * sym.y
      
    else: discard
    inc bf.pc
    
when isMainModule:
  var c = BFCore()
  c.interpret(readFile("helloworld.bf"))
