# janet-subprocess-notes

## (os/execute args &opt flags env)

Execute a program on the system.

`args` is a tuple or array of strings representing an invocation of a
prorgram with its arguments.

`flags` is a keyword that modifies how the program will execute.

* :e - enables passing an environment to the program. Without :e, the
  current environment is inherited.

* :p - allows searching the current PATH for the binary to execute.
  Without this flag, binaries must use absolute paths.

* :x - raise error if exit code is non-zero.

* :d - Don't try and terminate the process on garbage collection
  (allow spawning zombies).

`env` is a table or struct mapping environment variables to values.
It can also contain the keys :in, :out, and :err, which allow
redirecting stdio in the subprocess. The values associated with these
keys should be core/file or core/stream values. For better results,
close these values explicitly.

Returns the exit code of the program.

```janet
(def fpath "/tmp/fun.log")
(def of (file/open fpath :w))
(os/execute ["ls" "-al"] :p {:out of})
# XXX: can work without closing (sometimes?), but better to close
(file/close of)
(print (slurp fpath))
```

```janet
(def [rs ws] (os/pipe))
(os/execute ["ls"] :p {:out ws})
# close ws before reading from rs
(ev/close ws)
(print (ev/read rs :all))
(ev/close rs)
```

## (os/spawn args &opt flags env)

Execute a program on the system and return a handle to the process.

Otherwise, takes the same arguments as `os/execute`.

Does not wait for the process.

For each of the :in, :out, and :err keys of the `env` argument, one
can also pass in the keyword :pipe to get streams for standard IO of
the subprocess that can be read from and written to.

The returned value proc has the fields :in, :out, :err, and the
additional field :pid on unix-like platforms.  Use `(os/proc-wait
proc)` to rejoin the subprocess. After waiting completes, proc gains a
new field, :return-code.

> info for website docs?

If :x flag is used, a non-zero exit code will cause `os/proc-wait` to
raise an error.

If pipe streams created with :pipe keyword are not closed soon enough,
a janet process can run out of file descriptors. They can be closed
individually, or `os/proc-close` can close all pipe streams on proc.

> is it always true that "pipe buffers become full", or is it that
> it's a likely risk?  see for example
> [this](https://unix.stackexchange.com/questions/11946/how-big-is-the-pipe-buffer)

If pipe streams aren't read before `os/proc-wait` finishes, then pipe
buffers become full, and the process cannot finish because the process
cannot print more on pipe buffers which are already full. If the
process cannot finish, `os/proc-wait` cannot finish either.

## (os/proc-wait proc)

Suspend the current fiber until the subprocess completes. Returns the
subprocess return code.

> info for website docs?

Should not be called twice on the same process.

If cancelled with an error(?), it still finishes in the background.

The process is not cleaned up by the operating system until after
`os/proc-wait` finishes.  Thus, if `os/proc-wait` is not called, a
process becomes a zombie process.

## (os/proc-close proc)

Close pipes created by `os/spawn` if they have not been closed, then
wait on `proc` if it hasn't been waited on already.  Returns nil.

---

[`os/proc-close` implementation](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/os.c#L772-L797):

```c
JANET_CORE_FN(os_proc_close,
              "(os/proc-close proc)",
              "Wait on a process if it has not been waited on, and close pipes created by `os/spawn` "
              "if they have not been closed. Returns nil.") {
    janet_fixarity(argc, 1);
    JanetProc *proc = janet_getabstract(argv, 0, &ProcAT);
#ifdef JANET_EV
    if (proc->flags & JANET_PROC_OWNS_STDIN) janet_stream_close(proc->in);
    if (proc->flags & JANET_PROC_OWNS_STDOUT) janet_stream_close(proc->out);
    if (proc->flags & JANET_PROC_OWNS_STDERR) janet_stream_close(proc->err);
#else
    if (proc->flags & JANET_PROC_OWNS_STDIN) janet_file_close(proc->in);
    if (proc->flags & JANET_PROC_OWNS_STDOUT) janet_file_close(proc->out);
    if (proc->flags & JANET_PROC_OWNS_STDERR) janet_file_close(proc->err);
#endif
    proc->flags &= ~(JANET_PROC_OWNS_STDIN | JANET_PROC_OWNS_STDOUT | JANET_PROC_OWNS_STDERR);
    if (proc->flags & (JANET_PROC_WAITED | JANET_PROC_WAITING)) {
        return janet_wrap_nil();
    }
#ifdef JANET_EV
    os_proc_wait_impl(proc);
    return janet_wrap_nil();
#else
    return os_proc_wait_impl(proc);
#endif
}
```

## (os/proc-kill proc &opt wait signal)

Kill a subprocess by sending `SIGKILL` to it on POSIX systems, or
by closing the process handle on Windows.

If `proc` was already finished or closed (on Windows), raises an
error.

If `signal` is specified (on POSIX), send it instead of `SIGKILL`.  Signal
keywords are named after their C counterparts but in lowercase
with the leading `SIG` stripped.  Signals are ignored on Windows.

If `wait` is truthy, will wait for the process to finish and
return the exit code.  Otherwise, returns `proc`.

---

[`os/proc-kill` implementation](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/os.c#L729-L770):

```c
JANET_CORE_FN(os_proc_kill,
              "(os/proc-kill proc &opt wait signal)",
              "Kill a subprocess by sending SIGKILL to it on posix systems, or by closing the process "
              "handle on windows. If `wait` is truthy, will wait for the process to finish and "
              "returns the exit code. Otherwise, returns `proc`. If signal is specified send it instead."
              "Signal keywords are named after their C counterparts but in lowercase with the leading "
              "`SIG` stripped. Signals are ignored on windows.") {
    janet_arity(argc, 1, 3);
    JanetProc *proc = janet_getabstract(argv, 0, &ProcAT);
    if (proc->flags & JANET_PROC_WAITED) {
        janet_panicf("cannot kill process that has already finished");
    }
#ifdef JANET_WINDOWS
    if (proc->flags & JANET_PROC_CLOSED) {
        janet_panicf("cannot close process handle that is already closed");
    }
    proc->flags |= JANET_PROC_CLOSED;
    TerminateProcess(proc->pHandle, 1);
    CloseHandle(proc->pHandle);
    CloseHandle(proc->tHandle);
#else
    int signal = -1;
    if (argc == 3) {
        signal = get_signal_kw(argv, 2);
    }
    int status = kill(proc->pid, signal == -1 ? SIGKILL : signal);
    if (status) {
        janet_panic(strerror(errno));
    }
#endif
    /* After killing process we wait on it. */
    if (argc > 1 && janet_truthy(argv[1])) {
#ifdef JANET_EV
        os_proc_wait_impl(proc);
        return janet_wrap_nil();
#else
        return os_proc_wait_impl(proc);
#endif
    } else {
        return argv[0];
    }
}
```

## misc info

* you don't need `ev/spawn-thread`. This is just going to cause you
  headaches. Use `ev/spawn` to run a background task unless the
  background task makes a blocking call. Neither `os/execute` nor
  `os/spawn` block. I write medium sized, complete programs without
  using threads at all if I can avoid it.

* don't redirect output to pipes that are never read from. This causes
  things to hang in any language. It's how pipes work on Unix-likes
  and most languages work this way.

* look to the
  [`sh.janet`](https://github.com/janet-lang/spork/blob/7a4eff4bfb9486a6c6079ee8bb12e6789cce4564/spork/sh.janet)
  examples. They are written that way for a reason, [using `ev/gather`
  to avoid race
  conditions](https://github.com/janet-lang/spork/blob/7a4eff4bfb9486a6c6079ee8bb12e6789cce4564/spork/sh.janet#L44-L47). It's
  surprisingly tricky to get this correct - this is why [Python has a
  function
  subprocess.communicate](https://docs.python.org/3/library/subprocess.html#subprocess.Popen.communicate)
  to just "do the IO" after spawning a process.

* if you use `os/spawn`, I would always be sure to use `os/proc-wait`.

edited content via: https://github.com/janet-lang/janet/issues/1386#issuecomment-1922655204
