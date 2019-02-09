# Synesthesia - A (mildly) optimizing brainfuck compiler implemented as Nim macros

## How this came about

My career has been mostly in the embedded space, and while this arena
is largely dominated by `C` (which I have a great affinity for), one
thing I've always enjoyed is playing with interesting languages that
work on small targets to scratch my language polyglot itch.

Nim has been my weapon of choice for this lately, but I had been
toying around with the idea of writing a forth interpreter/compiler in
Nim to work on small embedded targets.

While I was working on my first draft (which I don't think will ever
see the light of day since it's so dreadful), it struck me that the
self-modifying and compile-time-evaluation nature of forth programs
were a _very_ good fit for nim's compile time macro system, and that
it would be a really neat project to implement a forth->nim compiler
as nim macros, which could then be compiled targeting embedded devices
to produce efficient native machine code rather than interpreting on
the fly.

To that end, I decided that a proof of concept was in order, and
decided that brainfuck would be a great target for a first attempt
given its simplicity, and the wealth of knowledge on the subject on the
internet and great sites
like [esolangs](https://esolangs.org/wiki/Main_Page).

Once I got started, I found that there was also a bunch of great
information about optimizing BF, so I figured "why not implement some
of that too?" and it just sort of ran away from me.

Whew, sorry about that novel, but before going any further, I'd like
to thank the proprieters of the following sites for their excellent
descriptions of various optimizations as they were critical for the
outcome of this project:

* http://calmerthanyouare.org/2015/01/07/optimizing-brainfuck.html
* https://www.nayuki.io/page/optimizing-brainfuck-compiler


## Requirements

* Nim compiler (v 0.18) (I recommend using the excellent [choosenim](https://github.com/dom96/choosenim))
* Some brainfuck source code you'd like to compile

## Use

### Installation:

* Install the nim compiler (see above)
* Clone the repo
* Type `nimble install`

(I plan to eventually upload this to the nimple package directory)

### Compiling BF files

To compile, use the `-c` flag like so:

`synesthesia -c mendel.bf`

By default, the compiler will generate an a.out file in the current
directory.  If you'd like to specify an alternative output file, one
can be specified with the `-o` flag;

`synesthesia -c mendel.bf -o mendelbrot`

### Interpreting BF files

synesthesia also includes an optimizing brainfuck interpreter.  To
interpret a file, use the `-i` flag:

`synesthesia -i mendel.bf`

## How compilation works

Nim includes a number of useful properties that uniquely position it
for this sort of project.  The first is its hygienic macro system
which allows for compile time code generation.

The second is the ability to execute 'pure' code at compile time (pure
being code that doesn't use FFI).  Not _everything_ works (I've found
nested generators to fail pretty interestingly), but the vast majority
of the nim language can be used.  Combining this with the Macro/AST
generation system allows one to perform interesting transforms on AST
nodes.

Finally, nim allows one to read files at compile time and act on their
contents. In the past, I've used this to generate register defnitions
for microcontrollers from their header files, but in this instance,
this functionality is used to `slurp` the BF source file and iterate
over its contents.

(Note before reading further: I'm hardly an expert on compiler
construction, so please be gentle if I use incorrect terminology :) )

### Step 0: Generate a temp source file

For simplicity, we generate a very simple nim source file containing
the imports required to use the compiler module, and a call to
`synesthesia.compile(<path/to/bf/source>)`.  We then call out to the
nim compiler with this file as the target to begin compilation.

This file is compiled with the release and optimize-for-size flags
applied (size optimization tends to produce faster code than speed
optimization due to the nature of the code generated)

### Step 1: Transformation to a list of symbols

Once a BF source file has been opened and the contents read into a
sequence of characters, this sequence is iterated over and each
relevant character is converted into an object: `BFSymbol`. `BFSymbol`
is a variant type (i.e. it includes a `kind` field, think tagged
unions in c).

For example, the `'>'` character causes the AP (memory cell index) to
be incremented by one, and `'<'` causes it to be decremented by one.

Given that, we can conclude that we need an ApAdjust symbol for +1,
and another for -1.  With variant types, we can simply include an
`amt` field in the `bfsApAdjust` symbol, and generate an appropriate
variant when each symbol is encountered.

(The same idea goes for memory adjustment with the `bfsMemAdjust`
variant)

A full listing of charcter => symbol mappings can be found in
`src/synesthesiapkg/common.nim`

### Step 2: Optimization

synesthesia implements a set of [peephole optimizers](https://en.wikipedia.org/wiki/Peephole_optimization)
that are applied to the resulting list of symbols.  Some of these optimizations are
obvious from the top level BF source (coalescing adjustments for
example), while others work best if applied after other optimizations
have already been made (dead adjustments / combining memory sets)

A full accounting of the optimizations applied can be found in
`src/synesthesiapkg/optimizer.nim`, but to give the reader an idea of
the sorts of things that are going on:

* Adjacent AP and Mem adjustments (i.e. `>>>>>` or `+++`) can be
  squished into single instructions (`ap + 5` and `mem[ap] + 3`
  accordingly).  We use the `amt` field in the object to track the
  total amount. Note that this works by tracking the total amount, so
  `+++---` becomes `mem[ap] + 0`
* Dead adjustments can be eliminated, so any ap or mem adjustment with
  an `amt` of 0 can simply be removed from the set of instructions.
* Clearing the current memory cell is a common pattern in BF `[-]`.
  Rather than sitting in a loop and decrementing the current cell
  until it hits zero, one can simply translate this to `mem[ap] = 0`,
  which is constant time.


More interesting optimizations include things like transforming loops
into multiplication instructions and deferring AP adjustments by using
offsets.

### Step 3: AST Generation

Once all optimizations are applied, AST generation can begin. For the
most part, ast generation is pretty strait forward, symbols are simply
transformed into NimNode objects representing their underlying purpose.

For example:

* bfsApAdjust(amount) => `ap += amount`
* bfsMemAdjust(offset, amount) => `mem[ap + offset] += amount`
* bfsPrint => `putChar(mem[ap])`

One notable exception to this is bfsBlock and bfsBlockEnd (i.e. loops in BF).

synesthesia implements blocks as while loops (sort of, but we
use if => doWhile for performance reasons)

As we need to keep track of loops, we maintain a stack of 'blocks'
during compilation.  As other symbols are decoded, their NimNodes are
added to the top block in the stack (i.e. their statements exist under
the lexical scope of the last known open loop).  When a new block is
encountered (`[` in BF), we generate a while loop scope and push it
onto the stack.  When a block ends (`]`), we pop the block off the
stack and continue on.

Once all AST nodes have been generated, the resulting nim code (which
we never see) is compiled to C, and then to machine code.

## License

The synesthesia compiler is licensed under the GPLv2.  Any resulting
binaries are licensed at the creator's discretion.
