/*
 * Tui/Key.flix — the `Key` ADT plus a small pure decoder from input code
 * points to keys. This is the seed of milestone M3; the JLine handler in
 * `Tui/Terminal.flix` reads raw code points and hands them here.
 *
 * The decoder is intentionally pure (no I/O, no JLine) so it is unit-testable
 * without a TTY. M3 will widen the CSI coverage (parameters, Home/End/PgUp,
 * modifiers); for now we cover plain characters, the common control keys and
 * the four arrow keys.
 */
pub mod Tui.Key {

    ///
    /// A decoded key press.
    ///
    pub enum Key with Eq, ToString {
        case Char(Char)         // a printable character
        case Enter              // CR or LF
        case Esc                // a lone ESC
        case Tab                // HT
        case Backspace          // BS or DEL
        case Arrow(Direction)   // an arrow key
        case Ctrl(Char)         // Ctrl + letter, e.g. Ctrl('c')
        case Unknown(String)    // anything not yet decoded
    }

    ///
    /// The direction of an arrow key.
    ///
    pub enum Direction with Eq, ToString {
        case Up,
        case Down,
        case Left,
        case Right
    }

    ///
    /// Converts a BMP code point to a `Char`, falling back to `'?'` for
    /// anything outside the basic multilingual plane.
    ///
    def toChar(cp: Int32): Char =
        match CodePoint.toBmpChar(cp) {
            case Some(c) => c
            case None    => '?'
        }

    ///
    /// Decodes a single, standalone code point (i.e. not part of an escape
    /// sequence) into a `Key`.
    ///
    /// Control keys are recognised before the generic `Ctrl(_)` fallback so
    /// that Tab (Ctrl-I), Enter (Ctrl-M) and Backspace (Ctrl-H) decode to
    /// their dedicated cases.
    ///
    pub def fromCodePoint(cp: Int32): Key =
        if (cp == 13 or cp == 10)
            Key.Enter
        else if (cp == 9)
            Key.Tab
        else if (cp == 127 or cp == 8)
            Key.Backspace
        else if (cp == 27)
            Key.Esc
        else if (cp >= 1 and cp <= 26)
            Key.Ctrl(toChar(cp + 96))   // Ctrl-A (1) -> 'a', ... Ctrl-Z (26) -> 'z'
        else if (cp >= 32)
            Key.Char(toChar(cp))
        else
            Key.Unknown(CodePoint.toString(cp))

    ///
    /// Decodes the final byte of an `ESC [` CSI sequence into a `Key`.
    ///
    /// Only the bare arrow keys are handled for now; everything else is
    /// reported as `Unknown`.
    ///
    pub def decodeCsi(finalByte: Int32): Key =
        match finalByte {
            case 65 => Key.Arrow(Direction.Up)      // 'A'
            case 66 => Key.Arrow(Direction.Down)    // 'B'
            case 67 => Key.Arrow(Direction.Right)   // 'C'
            case 68 => Key.Arrow(Direction.Left)    // 'D'
            case _  => Key.Unknown("[${CodePoint.toString(finalByte)}")
        }

}
