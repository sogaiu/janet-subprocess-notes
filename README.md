# janet-subprocess-notes

## Callables

* [os/execute](doc/os_execute.md)
* [os/spawn](doc/os_spawn.md)
* [os/proc-wait](doc/os_proc-wait.md)
* [os/proc-close](doc/os_proc-close.md)
* [os/proc-kill](doc/os_proc-kill.md)
* [ev/with-deadline](doc/ev_with-deadline.md)
* [ev/deadline](doc/ev_deadline.md)

## Official Doc Snippets

* Each root-fiber, or task, is a fiber that will be automatically
  resumed when an event (or sequence of events) that it is waiting for
  occurs.  Generally, one should not manually resume tasks - the event
  loop will call resume when the completion event occurs.

* To be precise, a task is just any fiber that was scheduled to run by
  the event loop.

* A default Janet program has a single task that will run until
  complete.  To create new tasks, Janet provides two built-in
  functions - `ev/go` and `ev/call`.

## Questions

* What does it mean for one fiber to be a child fiber of another
  (from the perspective of Janet's C source code)?

* What are all of the functions that can block apart from the
  following?

  * all functions in `file/`
  * `os/sleep`
  * `getline`

* There appear to be at least two types of fibers in Janet.  Those
  that end up on the event loop and those that don't.  Is it fair to
  make this distinction using the term "task" to describe the fibers
  that end up on the event loop and may be "non-task" for those that
  don't?

* Are the terms "root-fiber" and "task" equivalent?

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

* [Also notice how in sh.janet, `os/proc-wait` and `ev/read` run in
  parallel.](https://github.com/janet-lang/spork/blob/7a4eff4bfb9486a6c6079ee8bb12e6789cce4564/spork/sh.janet#L29-L31) (Note that `(:wait ...)` corresponds
  to a call to `os/proc-wait` and similarly that `(:read ...)`
  corresponds to a call to `ev/read` in this example.)

* As far as race conditions, I was mainly talking about the general
  case - depending on what program you run, some things will work,
  some won't. Programs like 'sed' that incrementally read from stdin
  and then output text in no particular manner can do this quite
  easily. There are a number of other bugs in the issue tracker where
  we figured this stuff out and made things work reliably with the
  patterns in sh.janet.

Edited content via: https://github.com/janet-lang/janet/issues/1386#issuecomment-1922894977

## Credits

* amano.kenji - code, discussion, feedback
* bakpakin - code, discussion, tips
* llmII - discussion, feedback, [spawn-utils](https://github.com/llmII/spawn-utils)
