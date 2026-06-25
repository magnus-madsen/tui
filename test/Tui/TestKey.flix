/*
 * test/Tui/TestKey.flix — unit tests for the pure `Tui.Key` decoder.
 *
 * The decoder is deliberately free of I/O and JLine, so these run without a
 * terminal. They pin down the code-point -> Key mapping and the CSI arrow
 * decoding that the `Terminal` handler relies on.
 */
use Tui.Key.{Key, Direction, fromCodePoint, decodeCsi}

// -- fromCodePoint: control keys recognised before the generic Ctrl fallback --

@Test
def fromCodePoint_cr_is_enter(): Unit \ Assert = Assert.assertEq(expected = Key.Enter, fromCodePoint(13))

@Test
def fromCodePoint_lf_is_enter(): Unit \ Assert = Assert.assertEq(expected = Key.Enter, fromCodePoint(10))

@Test
def fromCodePoint_tab(): Unit \ Assert = Assert.assertEq(expected = Key.Tab, fromCodePoint(9))

@Test
def fromCodePoint_del_is_backspace(): Unit \ Assert = Assert.assertEq(expected = Key.Backspace, fromCodePoint(127))

@Test
def fromCodePoint_bs_is_backspace(): Unit \ Assert = Assert.assertEq(expected = Key.Backspace, fromCodePoint(8))

@Test
def fromCodePoint_esc(): Unit \ Assert = Assert.assertEq(expected = Key.Esc, fromCodePoint(27))

// -- fromCodePoint: Ctrl-letter range (1..26), minus the keys special-cased above --

@Test
def fromCodePoint_ctrl_a(): Unit \ Assert = Assert.assertEq(expected = Key.Ctrl('a'), fromCodePoint(1))

@Test
def fromCodePoint_ctrl_c(): Unit \ Assert = Assert.assertEq(expected = Key.Ctrl('c'), fromCodePoint(3))

@Test
def fromCodePoint_ctrl_z(): Unit \ Assert = Assert.assertEq(expected = Key.Ctrl('z'), fromCodePoint(26))

// -- fromCodePoint: printable characters --

@Test
def fromCodePoint_lower_a(): Unit \ Assert = Assert.assertEq(expected = Key.Char('a'), fromCodePoint(97))

@Test
def fromCodePoint_space(): Unit \ Assert = Assert.assertEq(expected = Key.Char(' '), fromCodePoint(32))

@Test
def fromCodePoint_digit(): Unit \ Assert = Assert.assertEq(expected = Key.Char('5'), fromCodePoint(53))

// -- decodeCsi: the final byte of an `ESC [` arrow sequence --

@Test
def decodeCsi_up(): Unit \ Assert = Assert.assertEq(expected = Key.Arrow(Direction.Up), decodeCsi(65))

@Test
def decodeCsi_down(): Unit \ Assert = Assert.assertEq(expected = Key.Arrow(Direction.Down), decodeCsi(66))

@Test
def decodeCsi_right(): Unit \ Assert = Assert.assertEq(expected = Key.Arrow(Direction.Right), decodeCsi(67))

@Test
def decodeCsi_left(): Unit \ Assert = Assert.assertEq(expected = Key.Arrow(Direction.Left), decodeCsi(68))

@Test
def decodeCsi_unknown(): Unit \ Assert = Assert.assertEq(expected = Key.Unknown("[Z"), decodeCsi(90))
