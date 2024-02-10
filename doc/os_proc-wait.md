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

[`os/proc-wait` in os.c](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/os.c#L619-L630):

```c
JANET_CORE_FN(os_proc_wait,
              "(os/proc-wait proc)",
              "Suspend the current fiber until the subprocess completes. Returns the subprocess return code.") {
    janet_fixarity(argc, 1);
    JanetProc *proc = janet_getabstract(argv, 0, &ProcAT);
#ifdef JANET_EV
    os_proc_wait_impl(proc);
    return janet_wrap_nil();
#else
    return os_proc_wait_impl(proc);
#endif
}
```