# os/proc-wait

## Information

(os/proc-wait proc)

Suspend the current fiber until the subprocess completes. Returns the
subprocess return code.

> info for website docs?

Should not be called twice on the same process.

If cancelled with an error(?), it still finishes in the background.

The process is not cleaned up by the operating system until after
`os/proc-wait` finishes.  Thus, if `os/proc-wait` is not called, a
process becomes a zombie process.

## C Implementation

[`os_proc_wait_impl` in os.c](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/os.c#L579-L617)

```c
#ifdef JANET_EV
static JANET_NO_RETURN void
#else
static Janet
#endif
os_proc_wait_impl(JanetProc *proc) {
    if (proc->flags & (JANET_PROC_WAITED | JANET_PROC_WAITING)) {
        janet_panicf("cannot wait twice on a process");
    }
#ifdef JANET_EV
    /* Event loop implementation - threaded call */
    proc->flags |= JANET_PROC_WAITING;
    JanetEVGenericMessage targs;
    memset(&targs, 0, sizeof(targs));
    targs.argp = proc;
    targs.fiber = janet_root_fiber();
    janet_gcroot(janet_wrap_abstract(proc));
    janet_gcroot(janet_wrap_fiber(targs.fiber));
    janet_ev_threaded_call(janet_proc_wait_subr, targs, janet_proc_wait_cb);
    janet_await();
#else
    /* Non evented implementation */
    proc->flags |= JANET_PROC_WAITED;
    int status = 0;
#ifdef JANET_WINDOWS
    WaitForSingleObject(proc->pHandle, INFINITE);
    GetExitCodeProcess(proc->pHandle, &status);
    if (!(proc->flags & JANET_PROC_CLOSED)) {
        proc->flags |= JANET_PROC_CLOSED;
        CloseHandle(proc->pHandle);
        CloseHandle(proc->tHandle);
    }
#else
    waitpid(proc->pid, &status, 0);
#endif
    proc->return_code = (int32_t) status;
    return janet_wrap_integer(proc->return_code);
#endif
}
```

