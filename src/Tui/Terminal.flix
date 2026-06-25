/*
 * Tui/Terminal.flix — milestone M1.
 *
 * A thin `Terminal` effect wrapping a single JLine `Terminal`, plus its
 * `IO`-reinterpreting handler. This is the ONLY place in the library that
 * touches Java/JLine; every other module (Key, Screen, Widget) is pure Flix
 * and unit-testable without a TTY.
 *
 * The handler is resource-scoped in the same spirit as `Sys.Process.handle`:
 * it builds the terminal once on entry and always tears it down on the way
 * out. Flix has no `try/finally`, so crash-safety is implemented by catching
 * `Throwable` around the body, restoring the terminal, and exiting — a crash
 * inside the app must never leave the user's terminal in raw mode or on the
 * alternate screen.
 */
pub mod Tui.Terminal {

    use Tui.Key.{Key, fromCodePoint, decodeCsi}

    import org.jline.terminal.TerminalBuilder
    import org.jline.terminal.{Terminal => JTerminal}
    import org.jline.terminal.Attributes
    import java.io.IOException
    import java.lang.Throwable
    import java.lang.System
    import java.lang.Runtime
    import java.lang.Thread
    import java.lang.Runnable

    ///
    /// A minimal effect over a single system terminal.
    ///
    /// Keep this surface small and stable: the widget/screen layer is where
    /// features grow. `write` is raw — no newline translation — so callers
    /// stay in full control of cursor movement.
    ///
    pub eff Terminal {

        ///
        /// Returns the current terminal size in character cells.
        ///
        def size(): {rows = Int32, cols = Int32}

        ///
        /// Writes the string `s` verbatim to the terminal (no flush).
        ///
        def write(s: String): Unit

        ///
        /// Flushes any buffered output to the terminal.
        ///
        def flush(): Unit

        ///
        /// Reads and decodes the next key. Blocks until input is available.
        /// Returns `None` at end of input.
        ///
        def readKey(): Option[Key]

        ///
        /// Puts the terminal into raw (non-canonical, no-echo) mode and
        /// remembers the previous attributes so `exitRawMode` can restore them.
        ///
        def enterRawMode(): Unit

        ///
        /// Restores the terminal attributes saved by the last `enterRawMode`.
        ///
        def exitRawMode(): Unit

    }

    ///
    /// Handles the `Terminal` effect of `f` by reinterpreting it with `IO`.
    ///
    /// Builds one JLine terminal on entry, runs `f` against it, and always
    /// tears the terminal down afterwards — on normal return and on any
    /// `Throwable`. On a crash it restores the terminal, reports the error to
    /// stderr, and exits with status 1.
    ///
    pub def handle(f: a -> b \ ef): a -> b \ (ef - Terminal) + IO = x ->
        region rc {
            let term = buildTerminal();
            // Capture the cooked-mode attributes up front and arm a JVM
            // shutdown hook with them, so the terminal is restored even if the
            // process exits without running the teardown below (e.g. SIGTERM,
            // SIGINT delivered externally, or a `System.exit` elsewhere).
            let origAttrs = term.getAttributes();
            let hook = installShutdownHook(term, origAttrs);
            let saved = Ref.fresh(rc, (None: Option[Attributes]));
            try {
                let result = run {
                    f(x)
                } with handler Terminal {
                    def size(k) =
                        let sz = term.getSize();
                        k({rows = sz.getRows(), cols = sz.getColumns()})

                    def write(s, k) = {
                        term.writer().write(s);
                        k()
                    }

                    def flush(k) = {
                        term.flush();
                        k()
                    }

                    def readKey(k) = k(readKeyFrom(term))

                    def enterRawMode(k) = {
                        let prev = term.enterRawMode();
                        Ref.put(Some(prev), saved);
                        k()
                    }

                    def exitRawMode(k) = {
                        restoreAttributes(term, Ref.get(saved));
                        k()
                    }
                };
                removeShutdownHook(hook);
                teardown(term, Ref.get(saved));
                result
            } catch {
                case e: Throwable =>
                    removeShutdownHook(hook);
                    teardown(term, Ref.get(saved));
                    System.err.println("flix-tui: terminal handler aborted: ${e.getMessage()}");
                    unchecked_cast(System.exit(1) as b)
            }
        }

    ///
    /// Registers a JVM shutdown hook that restores the terminal (`origAttrs`
    /// are the cooked-mode attributes captured before raw mode). It runs only
    /// if the process exits without the normal teardown; on a clean exit the
    /// hook is removed first by `removeShutdownHook`. Returns the hook thread.
    ///
    def installShutdownHook(term: JTerminal, origAttrs: Attributes): Thread \ IO =
        let hook = new Runnable {
            def $run(_this: Runnable): Unit \ IO = teardown(term, Some(origAttrs))
        };
        let t = new Thread(hook);
        Runtime.getRuntime().addShutdownHook(t);
        t

    ///
    /// Best-effort removal of the shutdown hook on a clean exit. Throws if the
    /// JVM is already shutting down, which we swallow — in that case the hook
    /// is meant to run anyway.
    ///
    def removeShutdownHook(t: Thread): Unit \ IO =
        try {
            let _ = Runtime.getRuntime().removeShutdownHook(t);
            ()
        } catch {
            case _: Throwable => ()
        }

    ///
    /// Runs the `Terminal` effect of `f`, reinterpreting it with `IO`.
    ///
    @DefaultHandler
    pub def runWithIO(f: Unit -> a \ ef): a \ (ef - Terminal) + IO = handle(f)()

    ///
    /// Opens the system terminal, allowing JLine to fall back to a "dumb"
    /// terminal when no console is available (e.g. piped input, CI) rather
    /// than throwing. Exits with status 1 if even that fails.
    ///
    def buildTerminal(): JTerminal \ IO =
        try {
            TerminalBuilder.builder().system(true).dumb(true).build()
        } catch {
            case e: IOException =>
                System.err.println("flix-tui: failed to open system terminal: ${e.getMessage()}");
                unchecked_cast(System.exit(1) as JTerminal)
        }

    ///
    /// Reads the next key from `term`. A lone ESC, or `ESC [ <final>` arrow
    /// sequences, are decoded by peeking with a short timeout so a real
    /// Escape press is distinguished from the start of a CSI sequence.
    ///
    def readKeyFrom(term: JTerminal): Option[Key] \ IO =
        let reader = term.reader();
        let c0 = reader.read();                 // blocking; -1 at EOF
        if (c0 == -1)
            None
        else if (c0 == 27) {
            // Possible CSI sequence. read(timeout) returns -1 at EOF and
            // -2 (READ_EXPIRED) when the timeout elapses with no input.
            let c1 = reader.read(20i64);
            if (c1 < 0)
                Some(Key.Esc)
            else if (c1 == 91) {                // '['
                let c2 = reader.read(20i64);
                if (c2 < 0) Some(Key.Esc) else Some(decodeCsi(c2))
            } else
                Some(Key.Unknown("ESC ${CodePoint.toString(c1)}"))
        } else
            Some(fromCodePoint(c0))

    ///
    /// Restores the previously-saved terminal attributes, if any. Best effort:
    /// swallows any failure so teardown can continue.
    ///
    def restoreAttributes(term: JTerminal, saved: Option[Attributes]): Unit \ IO =
        try {
            match saved {
                case Some(a) => term.setAttributes(a)
                case None    => ()
            }
        } catch {
            case _: Throwable => ()
        }

    ///
    /// Best-effort teardown: show the cursor, leave the alternate screen,
    /// restore cooked-mode attributes, and close the terminal. Each step is
    /// guarded so a failure in one never skips the rest.
    ///
    def teardown(term: JTerminal, saved: Option[Attributes]): Unit \ IO =
        try {
            term.writer().write("\u001B[?25h\u001B[?1049l");
            term.flush()
        } catch {
            case _: Throwable => ()
        };
        restoreAttributes(term, saved);
        try {
            term.close()
        } catch {
            case _: Throwable => ()
        }

}
