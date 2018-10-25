import common
import tables

proc interpret*(bf: BFCore, program: string) =
  # Before we start, we need to pre-calculate our jump table
  var
    jumpTbl = initTable[int, int]()
    jumpStk: seq[int] = @[]

  for pc, inst in program:
    case inst
    of '[':
      jumpStk &= pc
    of ']':
      let fjp = jumpStk[^1]
      jumpStk = jumpStk[0.. ^2]
      jumpTbl[pc] = fjp
      jumpTbl[fjp] = pc
    else: discard

  # Clear out our core state
  bf.pc = 0
  bf.ap = 0
  for cell in bf.memory.mitems:
    cell = 0.uint8

  while bf.pc <= program.high:
    case program[bf.pc]
    of '>': inc bf.ap
    of '<': dec bf.ap
    of '+': inc bf.memory[bf.ap]
    of '-': dec bf.memory[bf.ap]
    of '.':
      stdout.write bf.memory[bf.ap].char
      stdout.flushFile()
    of ',':
      var tempMem: array[1, char]
      discard stdin.readChars(tempMem, 0, 1)
      bf.memory[bf.ap] = tempMem[0].uint8
    of '[':
      if bf.memory[bf.ap] == 0.uint8:
        bf.pc = jumpTbl[bf.pc]
    of ']':
      if bf.memory[bf.ap] != 0.uint8:
        bf.pc = jumpTbl[bf.pc]
    else: discard
    inc bf.pc
    
when isMainModule:
  var c = BFCore()
  c.interpret(readFile("helloworld.bf"))
