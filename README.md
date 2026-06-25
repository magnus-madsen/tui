# flix-tui

**flix-tui** is a small, standalone terminal-UI library for [Flix](https://flix.dev): a [JLine](https://github.com/jline/jline3)-backed `Terminal` effect plus a pure-Flix decoding layer on top. The `Terminal` effect is the only place that touches Java/JLine — raw-mode I/O, the alternate screen, and the cursor are all driven through it — while everything above it (key decoding today, a screen/widget layer later) stays pure Flix and unit-testable without a TTY.

## The `Terminal` effect

The whole Java boundary is this one effect — six operations, all in `Tui.Terminal`:

```flix
pub eff Terminal {
    def size(): {rows = Int32, cols = Int32}    // current terminal size, in cells
    def write(s: String): Unit                  // write `s` verbatim (raw, no flush)
    def flush(): Unit                           // flush buffered output
    def readKey(): Option[Key]                  // read+decode next key; None at EOF (blocks)
    def enterRawMode(): Unit                    // non-canonical, no-echo; saves prior attrs
    def exitRawMode(): Unit                     // restore the attrs saved by enterRawMode
}
```

Keys come back as the pure `Tui.Key.Key` ADT — `Char`, `Enter`, `Esc`, `Tab`, `Backspace`, `Arrow(Direction)`, `Ctrl(Char)`, `Unknown` — decoded without any I/O, so the decoder is unit-testable without a TTY.

## A complete example

The program below is the whole stack in motion: it opens a terminal, switches to raw mode, and draws a solid block you move around with the arrow keys (`q` or `Ctrl-C` to quit). The package ships as a library with no `main` of its own — drop this into a project's `src/` to run it.

```flix
// Main.flix — a small interactive demo for the flix-tui `Terminal` effect.
use Tui.Terminal.Terminal
use Tui.Key.{Key, Direction}

/// The square's size in cells. Wider than tall so it looks roughly square,
/// since terminal cells are about twice as tall as they are wide.
def squareH(): Int32 = 3
def squareW(): Int32 = 6

/// The current terminal size, falling back to 80x24 when JLine cannot detect
/// it (a dumb terminal reports 0x0), so the demo still behaves off-TTY.
def currentSize(): {rows = Int32, cols = Int32} \ Terminal =
    let sz = Terminal.size();
    { rows = if (sz#rows <= 0) 24 else sz#rows,
      cols = if (sz#cols <= 0) 80 else sz#cols }

///
/// `main` carries the `Terminal` effect directly; Flix installs the effect's
/// default handler (`Terminal.runWithIO`, annotated `@DefaultHandler`)
/// automatically, so there is no explicit `run ... with` block. It sets up the
/// alternate screen, centers the square, runs the event loop, then restores
/// the terminal.
///
def main(): Unit \ Terminal =
    Terminal.enterRawMode();
    Terminal.write("\u001B[?1049h\u001B[?25l");     // enter alt screen, hide cursor
    Terminal.flush();
    let sz = currentSize();
    let startRow = clampRow(sz#rows, (sz#rows - squareH()) / 2 + 1);
    let startCol = clampCol(sz#cols, (sz#cols - squareW()) / 2 + 1);
    eventLoop(startRow, startCol);
    Terminal.write("\u001B[?25h\u001B[?1049l");     // show cursor, leave alt screen
    Terminal.exitRawMode();
    Terminal.flush()

///
/// Draws the current frame, reads one key, and either quits or recurses with
/// an updated square position. Arrow keys nudge the square one cell, clamped
/// so it always stays fully on screen.
///
def eventLoop(row: Int32, col: Int32): Unit \ Terminal =
    // Re-query the size every frame so a window resize is picked up on the
    // next keystroke; the square is re-clamped to stay fully on screen.
    let sz = currentSize();
    let rows = sz#rows;
    let cols = sz#cols;
    let r = clampRow(rows, row);
    let c = clampCol(cols, col);
    draw(rows, cols, r, c);
    match Terminal.readKey() {
        case None                             => ()                  // EOF
        case Some(Key.Char('q'))              => ()                  // quit
        case Some(Key.Ctrl('c'))              => ()                  // quit
        case Some(Key.Arrow(Direction.Up))    => eventLoop(clampRow(rows, r - 1), c)
        case Some(Key.Arrow(Direction.Down))  => eventLoop(clampRow(rows, r + 1), c)
        case Some(Key.Arrow(Direction.Left))  => eventLoop(r, clampCol(cols, c - 1))
        case Some(Key.Arrow(Direction.Right)) => eventLoop(r, clampCol(cols, c + 1))
        case Some(_)                          => eventLoop(r, c)     // ignore
    }

///
/// Clears the screen, paints the square at `(row, col)`, and writes a hint on
/// the bottom line.
///
def draw(rows: Int32, cols: Int32, row: Int32, col: Int32): Unit \ Terminal =
    let cell = String.repeat(squareW(), "█");  // a row of U+2588 FULL BLOCK
    Terminal.write("\u001B[2J");                    // clear screen
    drawRows(row, col, cell, squareH());
    Terminal.write("\u001B[${rows};1H\u001B[0marrow keys move the square, q quits");
    let _ = cols;
    Terminal.flush()

///
/// Paints `remaining` rows of the square, each a run of full-block characters, starting
/// at `(row, col)`.
///
def drawRows(row: Int32, col: Int32, cell: String, remaining: Int32): Unit \ Terminal =
    if (remaining <= 0)
        ()
    else {
        Terminal.write("\u001B[${row};${col}H${cell}");
        drawRows(row + 1, col, cell, remaining - 1)
    }

/// Clamps the square's top row so it stays fully on screen (1-based).
def clampRow(rows: Int32, row: Int32): Int32 =
    let hi = Int32.max(1, rows - squareH() + 1);
    Int32.max(1, Int32.min(hi, row))

/// Clamps the square's left column so it stays fully on screen (1-based).
def clampCol(cols: Int32, col: Int32): Int32 =
    let hi = Int32.max(1, cols - squareW() + 1);
    Int32.max(1, Int32.min(hi, col))
```

## Running

To properly run the example you have to build a fatjar and run that. First save the example above as `src/Main.flix` (the package ships as a library with no `main` of its own); then build and run in a **real terminal** — raw mode needs a TTY:

```sh
$ flix build
$ flix build-fatjar
$ java -jar artifact/tui.jar
```
