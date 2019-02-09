import common

## Our first simple optimization is the coalescing of adjacent memory
## and pointer adjustments.  e.g. +++++ is actually +5, so we can
## execute a single +5 instruction rather than five +1 instructions
## (same goes for memory adjustments > and <)
proc coalesceAdjustments*(symbols: seq[BFSymbol]): seq[BFSymbol] =
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
proc generateMemZeroes*(symbols: seq[BFSymbol]): seq[BFSymbol] =
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

## In long stretches of only AP+Mem adjusts, we can remove unnecessary
## AP movements by instead tabulating a running total offset and
## performing a series of mem adjustments at those offsets, setting
## the final AP adjustment at the end
proc generateDeferredMovements*(symbols: seq[BFSymbol]): seq[BFSymbol] =
  echo "Optimizing out unnecessary AP Movement"
  result = @[]

  var
    i = 0
    totalOffset = 0

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
proc generateMulLoops*(symbols: seq[BFSymbol]): seq[BFSymbol] =
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
                             offset: totalOffset,
                             amt: y)
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

proc removeDeadAdjustments*(symbols: seq[BFSymbol]): seq[BFSymbol] =
  echo "removing zero moves"
  result = @[]

  for i in 0..symbols.high:
    case symbols[i].kind
    of bfsAPAdjust, bfsMemAdjust:
      if symbols[i].amt == 0:
        continue
      else:
        result &= symbols[i]
    else:
      result &= symbols[i]
