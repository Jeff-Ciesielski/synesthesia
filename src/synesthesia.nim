import os
import ospaths
import osproc
import strutils
import strformat

import docopt

import synesthesiapkg/common
import synesthesiapkg/interpreter

let doc = """Brainfuck Compiler/Interpreter
(C) 2019 Jeff Ciesielski <jeffciesielski@gmail.com>

Usage:
  synesthesia (--interpret | --compile) [--check_bounds] [--output=OUTFILE] INPUT

Options:
  -h --help               Show this help message and exit.
  -i --interpret          Interpret the supplied BF file.
  -c --compile            Compile the supplied BF file.
  -o --output OUTFILE     Specify the output file [default: a.out]
  -b --check_bounds       Enable bounds checking for arrays (for debugging)
"""

let bfTemplate = """
import synesthesiapkg/compiler
import synesthesiapkg/common

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
    outFile = absPath($args["--output"])

  if args["--interpret"]:
    BFCore().interpret(readFile($args["INPUT"]), true)

  if args["--compile"]:
    "temp_file.nim".writeFile(expandedTemplate)
    let
      boundCheck = if args["--check_bounds"]:
                     "on"
                   else:
                     "off"
      compileResult = execCmd(&"nim c --gc:stack -x:{boundCheck} -a:off --opt=size -d:release -o:{outFile} temp_file.nim")
    removeFile("temp_file.nim")
    quit compileResult
