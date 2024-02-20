# janet-subprocess-notes

## Callables

* [os/execute](doc/os_execute.md)
* [os/spawn](doc/os_spawn.md)
* [os/proc-wait](doc/os_proc-wait.md)
* [os/proc-close](doc/os_proc-close.md)
* [os/proc-kill](doc/os_proc-kill.md)

## Misc Info

* Use `ev/spawn` to run a background task unless the background task
  makes a blocking call. Neither `os/execute` nor `os/spawn` block.

* Don't redirect output to pipes that are never read from. This causes
  things to hang in any language. It's how pipes work on Unix-likes
  and most languages work this way.

* Look to the
  [`sh.janet`](https://github.com/janet-lang/spork/blob/7a4eff4bfb9486a6c6079ee8bb12e6789cce4564/spork/sh.janet)
  examples. They are written that way for a reason [using `ev/gather`
  to avoid race
  conditions](https://github.com/janet-lang/spork/blob/7a4eff4bfb9486a6c6079ee8bb12e6789cce4564/spork/sh.janet#L44-L47). It's
  surprisingly tricky to get this correct - this is why [Python has a
  function
  subprocess.communicate](https://docs.python.org/3/library/subprocess.html#subprocess.Popen.communicate)
  to just "do the IO" after spawning a process.

* If you use `os/spawn`, I would always be sure to use `os/proc-wait`.

Edited content via: https://github.com/janet-lang/janet/issues/1386#issuecomment-1922655204

* The reason you call `os/proc-wait` is to avoid zombies. Same as any
  scripting language - if you want more info on this, read the man
  pages for waitpid(2).

* [Also notice how in `sh.janet`, `os/proc-wait` and `ev/read` run in
  parallel.](https://github.com/janet-lang/spork/blob/7a4eff4bfb9486a6c6079ee8bb12e6789cce4564/spork/sh.janet#L29-L31) (Note that `(:wait ...)` corresponds
  to a call to `os/proc-wait` and similarly that `(:read ...)`
  corresponds to a call to `ev/read` in this example.)

* As far as race conditions, I was mainly talking about the general
  case - depending on what program you run, some things will work,
  some won't. Programs like 'sed' that incrementally read from stdin
  and then output text in no particular manner can do this quite
  easily. There are a number of other bugs in the issue tracker where
  we figured this stuff out and made things work reliably with the
  patterns in `sh.janet`.

Edited content via: https://github.com/janet-lang/janet/issues/1386#issuecomment-1922894977

## Possible Website Doc Changes

* At least on UNIX-like systems, the parent of a process is expected
  to call wait (or similar) and only after this will the operating
  system perform a removal of a process' entry from a certain data
  structure ("process table").  Note that this does not apply to
  Windows.

  A process is not cleaned up by the operating system until after
  "waiting" finishes.  So, if `os/proc-wait` is not called, waiting
  does not occur, and a process becomes a zombie process.

  Thus, it is recommended to use `os/proc-wait` with `os/spawn`.

* Use `ev/gather` to avoid race conditions (see spork's `sh.janet` for
  samples).

* If pipe streams created with :pipe keyword are not closed soon
  enough, a janet process can run out of file descriptors. They can be
  closed individually, or `os/proc-close` can close all pipe streams
  on proc.

* If pipe streams aren't read enough before `os/proc-wait` finishes,
  then pipe buffers can become full, and the process cannot finish
  because the process cannot print more on pipe buffers which are
  already full.  If the process cannot finish, `os/proc-wait` cannot
  finish either.

## Credits

* amano.kenji - code, discussion, feedback
* bakpakin - code, discussion, tips
* llmII - code, discussion, feedback, [spawn-utils](https://github.com/llmII/spawn-utils)
