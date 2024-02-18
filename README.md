# janet-subprocess-notes

## Callables

* [os/execute](doc/os_execute.md)
* [os/spawn](doc/os_spawn.md)
* [os/proc-wait](doc/os_proc-wait.md)
* [os/proc-close](doc/os_proc-close.md)
* [os/proc-kill](doc/os_proc-kill.md)
* [ev/with-deadline](doc/ev_with-deadline.md)
* [ev/deadline](doc/ev_deadline.md)

## Glossary

* channel - one of two methods of communication between tasks.  (See
  stream for another.)

  * ordinary, non-threaded - allows the programmer to communicate by
    sending any Janet value as messages, and only work inside a
    thread - they do not allow communication between threads,
    processes, or over the network.

  * threaded - allows the programmer to communicate Janet values
    between threads.  XXX: limits of the sorts of things that can be
    transferred is not so clear.

* event loop - provides concurrency within a single thread by allowing
  cooperating fibers to yield instead of blocking forward progress.

* fiber - allows a process to stop and resume execution later,
  essentially enabling multiple returns from a function.

  * ordinary, non-root - the programmer can resume this type of fiber.

  * task - a fiber that will be automatically resumed when an event
    (or sequence of events) that it is waiting for occurs.  The
    programmer should not try to resume this type of fiber.  Note that
    in a standard janet build, a task is the same as a root fiber.
    The root fiber for the current fiber is the oldest ancestor that
    does not have a parent.  It is obtainable via the `root/fiber`
    function.  A task is sometimes referred to as "a fiber that was
    scheduled to run by the event loop" or "a fiber on the event
    loop".

* stream - one of two methods of communication between tasks.  (See
  channel for anotrher.)  They are wrappers around file descriptors
  and operate on streams of bytes.  Streams can communicate across
  threads, processes, and across the network.

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

## Possible Website Doc Tweaks

* Regarding channels, the text: "and only work inside a thread"
  appears in the Task Communication section of the Event Loop page.
  There are threaded channels now so the text seems a bit off.

* Add something about catching errors that result from using `cancel`
  or `ev/cancel`.  For example, the code:

    ```janet
    (def fib
      (coro
        (try
          (yield 1)
          ([e]
            (eprint "nifty")))))

    (resume fib)

    (cancel fib :error)
    ```

  results in the output "nifty".

## Questions

* What does it mean for one fiber to be a child fiber of another
  (from the perspective of Janet's C source code)?

* What are all of the functions that can block apart from the
  following?

  * all(?) functions in `file/`
    * file/close
    * file/flush
    * file/lines
    * file/open
    * file/read
    * file/seek
    * file/tell
    * file/temp
    * file/write
  * `os/sleep`
  * `getline`

## Resolved Questions

* There appear to be at least two types of fibers in Janet.  Those
  that end up on the event loop and those that don't.  Is it fair to
  make this distinction using the term "task" to describe the fibers
  that end up on the event loop and may be "non-task" for those that
  don't?

  > The distinction between "task" fibers and normal fibers is now
  > kept by a flag that is set when a fiber is resumed - if it is the
  > outermost fiber on the stack, it is considered a root fiber. All
  > fibers scheduled with ev/go or by the event loop are root fibers,
  > and thus cannot be cancelled or resumed with `cancel` or `resume`
  > \- instead, use `ev/cancel` or `ev/go`.

  (source: text from [commit addressing #920](https://github.com/janet-lang/janet/commit/a9f38dfce4e892dad370efe768bb3f59eb2b79ab))

  ```c
  /* If a "task" fiber is trying to be used as a normal fiber, detect that. See bug #920.
   * Fibers must be marked as root fibers manually, or by the ev scheduler. */
  ```

  (source: [comment in vm.c](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/vm.c#L1401-L1402))

* Are the terms "root-fiber" and "task" equivalent?  It seems they are
  at least close.  (Peripheral case: if janet is compiled without ev
  support, are there tasks?  There may be root-fibers...).

## Official Doc Snippets

* Each root-fiber, or task, is a fiber that will be automatically
  resumed when an event (or sequence of events) that it is waiting for
  occurs.  Generally, one should not manually resume tasks - the event
  loop will call resume when the completion event occurs. (source:
  event loop page)

* To be precise, a task is just any fiber that was scheduled to run by
  the event loop. (source: event loop page)

* A default Janet program has a single task that will run until
  complete.  To create new tasks, Janet provides two built-in
  functions - `ev/go` and `ev/call`. (source: event loop page)

* You can get the currently executing task in Janet with
  `(fiber/root)`. (source: event loop page)

* The root fiber is the oldest ancestor that does not have a parent.
  (source: the `fiber/root` docstring)

## Credits

* amano.kenji - code, discussion, feedback
* bakpakin - code, discussion, tips
* llmII - discussion, feedback, [spawn-utils](https://github.com/llmII/spawn-utils)
