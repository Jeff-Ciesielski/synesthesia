import common

## Our first simple optimization is the coalescing of adjacent memory
## and pointer adjustments.  e.g. +++++ is actually +5, so we can
## execute a single +5 instruction rather than five +1 instructions
## (same goes for memory adjustments > and <)
proc coalesceAdjustments*(tokens: seq[BFToken]): seq[BFToken] =
  echo "Coalescing memory adjustments"
  result = @[]

  result &= tokens[0]

  for sym in tokens[1.. ^1]:
    case sym.kind
    of bfsApAdjust, bfsMemAdjust:
      if sym.kind == result[^1].kind:
        result[^1].amt += sym.amt
      else:
        result &= sym
    else: result &= sym

## Our next optimizaiton is the generation of 'MemSet(0, 0)' commands. The
## pattern `[-]` is very common in BF programming, and essentially
## means loop on the current memory location until it reaches zero,
## and then continue.  We can skip all those nasty branches with a simple set
proc generateMemZeroes*(tokens: seq[BFToken]): seq[BFToken] =
  echo "Optimizing memory zero-sets"
  result = @[]
  var i = 0

  while i < tokens.len:
    if (i < tokens.high and tokens[i].kind == bfsBlock and
        (tokens[i+1].kind == bfsMemAdjust and tokens[i+1].amt == -1) and
        tokens[i+2].kind == bfsBlockEnd):
      result &= BFToken(kind: bfsMemSet)
      i += 3
    else:
      result &= tokens[i]
      inc i

## In long stretches of only AP+Mem adjusts, we can remove unnecessary
## AP movements by instead tabulating a running total offset and
## performing a series of mem adjustments at those offsets, setting
## the final AP adjustment at the end
proc generateDeferredMovements*(tokens: seq[BFToken]): seq[BFToken] =
  echo "Optimizing out unnecessary AP Movement"
  result = @[]

  var
    i = 0
    totalOffset = 0

  while i < tokens.len:
    if tokens[i].kind == bfsMemAdjust:
      result &= BFToken(kind: bfsMemAdjust,
                         amt: tokens[i].amt,
                         offset: tokens[i].offset + totalOffset)
    elif tokens[i].kind == bfsMemSet:
      result &= BFToken(kind: bfsMemSet,
                         amt: tokens[i].amt,
                         offset: tokens[i].offset + totalOffset)
    elif tokens[i].kind == bfsMul:
      result &= BFToken(kind: bfsMul,
                         amt: tokens[i].amt,
                         offset: tokens[i].offset + totalOffset,
                         secondOffset: totalOffset)
    elif tokens[i].kind == bfsApAdjust:
      totalOffset += tokens[i].amt
    else:
      result &= BFToken(kind: bfsApAdjust,
                         amt: totalOffset)
      totalOffset = 0
      result &= tokens[i]
    inc i

## Condenses multiplication loops into multiplication instructions
## i.e. [->+++>+++<<] becomes two multiplications: Mul 1,3 and Mul 2,3
proc generateMulLoops*(tokens: seq[BFToken]): seq[BFToken] =
  echo "Optimizing Multiply Loops"
  result = @[]
  var
    i = 0
    j = 0
    inLoop = false
    totalOffset = 0
    mulStk: seq[BFToken] = @[]

  while i < tokens.len:
    if (i < tokens.high and tokens[i].kind == bfsBlock and
        (tokens[i+1].kind == bfsMemAdjust and tokens[i+1].amt == -1)):
      totalOffset = 0
      mulStk = @[]
      j = i
      i += 2
      inLoop = false
      while true:
        let
          s1 = tokens[i]
          s2 = tokens[i+1]
        if ((s1.kind == bfsApAdjust) and
            (s2.kind == bfsMemAdjust)):
          let y = s2.amt

          totalOffset += s1.amt

          mulStk &= BFToken(kind:bfsMul,
                             offset: totalOffset,
                             amt: y)
          i += 2
          inLoop = true
        elif ((s1.kind == bfsApAdjust and
               (s1.amt + totalOffset == 0)) and
              s2.kind == bfsBlockEnd and inLoop):
          result &= mulStk
          result &= BFToken(kind: bfsMemSet)
          i += 2
          break
        else:
          i = j
          result &= tokens[i]
          inc i
          break
    else:
      result &= tokens[i]
      inc i

## Occasionally after a few rounds of optimization, you'll see a mem
## or ap adjust with a zero amount. If that happens, they can just be
## excluded as they're effectively a no-op
proc removeDeadAdjustments*(tokens: seq[BFToken]): seq[BFToken] =
  echo "removing zero moves"
  result = @[]

  for i in 0..tokens.high:
    case tokens[i].kind
    of bfsAPAdjust, bfsMemAdjust:
      if tokens[i].amt == 0:
        continue
      else:
        result &= tokens[i]
    else:
      result &= tokens[i]

## If we see back to back memSet => memAdjust, and they share an
## offset, we can combine them into a single memset.
proc combineMemSets*(tokens: seq[BFToken]): seq[BFToken] =
  echo "Combining adjascent memZero + memAdjust"
  result = @[]

  var i = 0
  while i < tokens.len:
    if (i < tokens.high and
        tokens[i].kind == bfsMemSet and
        tokens[i].amt == 0 and
        tokens[i+1].kind == bfsMemAdjust and
        (tokens[i].offset == tokens[i+1].offset)):
      result &= BFToken(kind: bfsMemSet,
                         offset: tokens[i].offset,
                         amt: tokens[i+1].amt + tokens[i].amt)
      i += 2
    else:
      result &= tokens[i]
      i += 1

## If a multiplication has a zero mulOffset and a 1 amount, we can perform a memAdd
proc simplifyMultiplications*(tokens: seq[BFToken]): seq[BFToken] =
  echo "Converting mul * 1 to an add"
  result = @[]
  var i = 0
  while i < tokens.len:
    if (tokens[i].kind == bfsMul and
        tokens[i].amt == 1):
      result &= BFToken(kind: bfsMemAdd,
                        offset: tokens[i].offset,
                        secondOffset: tokens[i].secondOffset)
    else:
      result &= tokens[i]
    inc i


proc applyAllOptimizations*(tokens: seq[BFToken]): seq[BFToken] =
  result = (tokens
            .coalesceAdjustments
            .generateMemZeroes
            .generateMulLoops
            .generateDeferredMovements
            .removeDeadAdjustments
            .combineMemSets
            .simplifyMultiplications
  )
