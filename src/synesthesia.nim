import os
import ospaths
import osproc
import strutils
import strformat

import docopt



import synesthesia/common
import synesthesia/interpreter

let doc = """Brainfuck Compiler/Interpreter
Usage:
  synesthesia (--interpret | --compile) [--output=OUTFILE] INPUT

Options:
  -h --help               Show this help message and exit.
  -i --interpret          Interpret the supplied BF file.
  -c --compile            Compile the supplied BF file.
  -o --output OUTFILE     Specify the output file [default: a.out]
"""

let bfTemplate = """
import synesthesia/compiler
import synesthesia/common

compile(SOURCEFILE)
"""

proc abspath(p: string): string =
  getCurrentDir() / p

when isMainModule:
  let
    args = docopt(doc)
    inFilePath = $args["INPUT"]
    absInFile = abspath(inFilePath)
    (dir, name, ext) = splitFile(absInFile)
    expandedTemplate = bfTemplate.replace("SOURCEFILE", &"\"{absInFile}\"")

  echo args
  echo name

  if args["--interpret"]:
    BFCore().interpret(readFile($args["INPUT"]), true)

  if args["--compile"]:
    "temp_file.nim".writeFile(expandedTemplate)
    let compileResult = execCmd("nim c --opt=size -d:release temp_file.nim")
    quit compileResult
