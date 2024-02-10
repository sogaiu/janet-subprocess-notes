# os/proc-kill

## Information

`(os/proc-kill proc &opt wait signal)`

Kill a subprocess by sending `SIGKILL` to it on POSIX systems, or
by closing the process handle on Windows.

If `proc` was already finished or closed (on Windows), raises an
error.

If `signal` is specified (on POSIX), send it instead of `SIGKILL`.  Signal
keywords are named after their C counterparts but in lowercase
with the leading `SIG` stripped.  Signals are ignored on Windows.

If `wait` is truthy, will wait for the process to finish and
return the exit code.  Otherwise, returns `proc`.

## C Implementation

[`os/proc-kill` in os.c](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/os.c#L729-L770):

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
