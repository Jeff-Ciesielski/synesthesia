#!/usr/bin/env nimr
import macros
import sequtils
import strformat
import tables

var
  HelloWorld = "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++."

type
  BFCore* = ref object
   memory*: array[1024, uint8]
   pc*, ap*: int


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
    of '.': echo bf.memory[bf.ap].char
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


proc `<-`(a, b: NimNode) =
  if len(a[1]) == 2:
    a[1][1][0][1].add(b)
  else:
    a[1][0][1][0][1][0][0][1].add(b)

proc genInitialBlock(): NimNode =
  newNimNode(nnkBlockStmt).add(
    newIdentNode("bfProg"),
    newStmtList(
      newNimNode(nnkVarSection).add(
        newNimNode(nnkIdentDefs).add(
          newIdentNode("core"),
          newEmptyNode(),
          newNimNode(nnkCall).add(
            newIdentNode("BFCore")
          )
        )
      ),
      newNimNode(nnkIfStmt).add(
        newNimNode(nnkElifBranch).add(
          newIdentNode("true"),
          newStmtList()
        )
      )
    )
  )

proc genIncMemory(): NimNode =
  newNimNode(nnkCommand).add(
    newIdentNode("inc"),
    newNimNode(nnkBracketExpr).add(
      newNimNode(nnkDotExpr).add(
        newIdentNode("core"),
        newIdentNode("memory")
      ),
      newNimNode(nnkDotExpr).add(
        newIdentNode("core"),
        newIdentNode("ap")
      )
    )
  )

proc genDecMemory(): NimNode =
  newNimNode(nnkCommand).add(
    newIdentNode("dec"),
    newNimNode(nnkBracketExpr).add(
      newNimNode(nnkDotExpr).add(
        newIdentNode("core"),
        newIdentNode("memory")
      ),
      newNimNode(nnkDotExpr).add(
        newIdentNode("core"),
        newIdentNode("ap")
      )
    )
  )

proc genPrintMemory(): NimNode =
  newNimNode(nnkCommand).add(
    newIdentNode("echo"),
    newNimNode(nnkDotExpr).add(
      newNimNode(nnkBracketExpr).add(
        newNimNode(nnkDotExpr).add(
          newIdentNode("core"),
          newIdentNode("memory")
        ),
        newNimNode(nnkDotExpr).add(
          newIdentNode("core"),
          newIdentNode("ap")
        )
      ),
      newIdentNode("char")
    )
  )

proc genIncAP(): NimNode =
  newNimNode(nnkCommand).add(
    newIdentNode("inc"),
    newNimNode(nnkDotExpr).add(
        newIdentNode("core"),
        newIdentNode("ap")
      )
  )

proc genDecAP(): NimNode =
  newNimNode(nnkCommand).add(
    newIdentNode("dec"),
    newNimNode(nnkDotExpr).add(
        newIdentNode("core"),
        newIdentNode("ap")
      )
  )

proc genBlock(id: int): NimNode =
  let topBlockIdent = newIdentNode("b" & $(id))
  let innerBlockIdent = newIdentNode("b" & $(id) & "a")
  nnkBlockStmt.newTree(
    topBlockIdent,
    nnkStmtList.newTree(
      nnkWhileStmt.newTree(
        newIdentNode("true"),
        nnkStmtList.newTree(
          nnkBlockStmt.newTree(
            innerBlockIdent,
            nnkStmtList.newTree(
              nnkIfStmt.newTree(
                nnkElifBranch.newTree(
                  nnkInfix.newTree(
                    newIdentNode("!="),
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
                      newLit(0),
                      newIdentNode("uint8")
                    )
                  ),
                  nnkStmtList.newTree()
                )
              ),
              nnkIfStmt.newTree(
                nnkElifBranch.newTree(
                  nnkInfix.newTree(
                    newIdentNode("=="),
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
                      newLit(0),
                      newIdentNode("uint8")
                    )
                  ),
                  nnkStmtList.newTree(
                    nnkBreakStmt.newTree(
                      topBlockIdent
                    )
                  )
                ),
                nnkElse.newTree(
                  nnkStmtList.newTree(
                    nnkBreakStmt.newTree(
                      innerBlockIdent
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  )

#proc genBlock(id: int): NimNode =
#  newNimNode(nnkBlockStmt).add(
#    newIdentNode("bfBlock" & $(id)),
#    newStmtList(
#      newNimNode(nnkIfStmt).add(
#        newNimNode(nnkElifBranch).add(
#          newNimNode(nnkInfix).add(
#            newIdentNode("!="),
#            newNimNode(nnkBracketExpr).add(
#              newNimNode(nnkDotExpr).add(
#                newIdentNode("core"),
#                newIdentNode("memory")
#              ),
#              newNimNode(nnkDotExpr).add(
#                newIdentNode("core"),
#                newIdentNode("ap")
#              )
#            ),
#            newNimNode(nnkDotExpr).add(
#              newIntLitNode(0),
#              newIdentNode("uint8")
#            )
#          ),
#          newStmtList()
#        )
#      )
#    )
#  )

proc closeBlock(blk: NimNode) =
  let tgtIdent = blk[0]
  let closing = nnkIfStmt.newTree(
    nnkElifBranch.newTree(
      nnkInfix.newTree(
        newIdentNode("!="),
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
          newLit(0),
          newIdentNode("uint8")
        )
      ),
      nnkStmtList.newTree(
        nnkBreakStmt.newTree(
          tgtIdent
        )
      )
    )
  )

  blk[1].add(closing)


macro compile*(prog: string): untyped =
  result = newStmtList()
  var blockStack = @[genInitialBlock()]

  let instructions = toSeq(prog.strVal.items)
  var blockCount: int = 1
  for inst in instructions:
    case inst
    of '>':
      blockStack[^1] <- genIncAP()
    of '<':
      blockStack[^1] <- genDecAP()
    of '+':
      blockStack[^1] <- genIncMemory()
    of '-':
      blockStack[^1] <- genDecMemory()
    of '.':
      blockStack[^1] <- genPrintMemory()
    of ',':
      echo "read memory"
    of '[':
      let blk = genBlock(blockCount)
      blockStack[^1] <- blk
      blockStack &= blk
      inc blockCount
    of ']':
      closeBlock(blockStack[^1])
      blockStack = blockStack[0.. ^2]

    else: discard
  result.add(blockStack[0])
  echo result.treeRepr


# +[>+[.]]
#dumpAstGen:
dumpTree:
  block bfProg:
    var
      core = BFCore()
    if true:
      inc core.memory[core.ap]
      block b1:
        while true:
          block b1a:
            if core.memory[core.ap] != 0.uint8:
              inc core.ap
              inc core.memory[core.ap]
              block b2:
                while true:
                  block b2a:
                    if core.memory[core.ap] != 0.uint8:
                      echo core.memory[core.ap].char
                    if core.memory[core.ap] == 0.uint8:
                      break b2
                    else:
                      break b2a
            if core.memory[core.ap] == 0.uint8:
              break b1
            else:
              break b1a

#compile("++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.")
#compile("+[>+[.]]:")
#compile(">++[<+++++++++++++>-]<[[>+>+<<-]>[<+>-]++++++++[>++++++++<-]>.[-]<<>++++++++++[>++++++++++[>++++++++++[>++++++++++[>++++++++++[>++++++++++[>++++++++++[-]<-]<-]<-]<-]<-]<-]<-]++++++++++.")


# block bfProg:
#   var
#     core = BFCore()
#   if true:
#     inc core.memory[core.ap]
#     block b1:
#       while true:
#         block b1a:
#           if core.memory[core.ap] != 0.uint8:
#             inc core.ap
#             inc core.memory[core.ap]
#             block b2:
#               while true:
#                 block b2a:
#                   if core.memory[core.ap] != 0.uint8:
#                     echo core.memory[core.ap].char
#                   if core.memory[core.ap] == 0.uint8:
#                     break b2
#                   else:
#                     break b2a
#           if core.memory[core.ap] == 0.uint8:
#             break b1
#           else:
#             break b1a

when isMainModule:
  var c = BFCore()
  #c.interpret("+[>+[.]]")
  #c.interpret(HelloWorld)
  c.interpret(">++[<+++++++++++++>-]<[[>+>+<<-]>[<+>-]++++++++[>++++++++<-]>.[-]<<>++++++++++[>++++++++++[>++++++++++[>++++++++++[>++++++++++[>++++++++++[>++++++++++[-]<-]<-]<-]<-]<-]<-]<-]++++++++++.")
