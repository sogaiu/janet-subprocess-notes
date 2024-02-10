# os/proc-close

## Information

(os/proc-close proc)

Close pipes created by `os/spawn` if they have not been closed, then
wait on `proc` if it hasn't been waited on already.  Returns nil.

## C Implementation

[`os/proc-close` in os.c](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/os.c#L772-L797):

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

