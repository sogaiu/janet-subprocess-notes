# os/proc-wait

## Information

`(os/proc-wait proc)`

Suspend the current fiber until the subprocess completes. Returns the
subprocess return code.

> info for website docs?

Should not be called twice on the same process.

If cancelled with an error(?), it still finishes in the background.

The process is not cleaned up by the operating system until after
`os/proc-wait` finishes.  Thus, if `os/proc-wait` is not called, a
process becomes a zombie process.

## C Implementation

[`os_proc_wait_impl` in os.c](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/os.c#L579-L617):

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
    // ... elided ...
#endif
}
```

[`janet_await` in ev.c](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/ev.c#L583-L587):

```c
/* Shorthand to yield to event loop */
void janet_await(void) {
    /* Store the fiber in a gobal table */
    janet_signalv(JANET_SIGNAL_EVENT, janet_wrap_nil());
}
```

[`janet_signalv` in `capi.c`](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/capi.c#L60-L75):

```c
void janet_signalv(JanetSignal sig, Janet message) {
    if (janet_vm.return_reg != NULL) {
        *janet_vm.return_reg = message;
        if (NULL != janet_vm.fiber) {
            janet_vm.fiber->flags |= JANET_FIBER_DID_LONGJUMP;
        }
#if defined(JANET_BSD) || defined(JANET_APPLE)
        _longjmp(*janet_vm.signal_buf, sig);
#else
        longjmp(*janet_vm.signal_buf, sig);
#endif
    } else {
        const char *str = (const char *)janet_formatc("janet top level signal - %v\n", message);
        janet_top_level_signal(str);
    }
}
```

[inside `janet_continue_no_check`  in `vm.c`](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/vm.c#L1506-L1524):

```c
    /* Save global state */
    JanetTryState tstate;
    JanetSignal sig = janet_try(&tstate);
    if (!sig) {
        /* Normal setup */
        if (janet_vm.root_fiber == NULL) janet_vm.root_fiber = fiber;
        janet_vm.fiber = fiber;
        janet_fiber_set_status(fiber, JANET_STATUS_ALIVE);
        sig = run_vm(fiber, in);
    }

    /* Restore */
    if (janet_vm.root_fiber == fiber) janet_vm.root_fiber = NULL;
    janet_fiber_set_status(fiber, sig);
    janet_restore(&tstate);
    fiber->last_value = tstate.payload;
    *out = tstate.payload;

    return sig;
```

[`janet_try_init`, and `janet_restore` in `vm.c`](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/vm.c#L1427-L1443):

```c
void janet_try_init(JanetTryState *state) {
    state->stackn = janet_vm.stackn++;
    state->gc_handle = janet_vm.gc_suspend;
    state->vm_fiber = janet_vm.fiber;
    state->vm_jmp_buf = janet_vm.signal_buf;
    state->vm_return_reg = janet_vm.return_reg;
    janet_vm.return_reg = &(state->payload);
    janet_vm.signal_buf = &(state->buf);
}

void janet_restore(JanetTryState *state) {
    janet_vm.stackn = state->stackn;
    janet_vm.gc_suspend = state->gc_handle;
    janet_vm.fiber = state->vm_fiber;
    janet_vm.signal_buf = state->vm_jmp_buf;
    janet_vm.return_reg = state->vm_return_reg;
}
```

[`janet_try` in `janet.h`](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/include/janet.h#L1791-L1795):

```c
#if defined(JANET_BSD) || defined(JANET_APPLE)
#define janet_try(state) (janet_try_init(state), (JanetSignal) _setjmp((state)->buf))
#else
#define janet_try(state) (janet_try_init(state), (JanetSignal) setjmp((state)->buf))
#endif
```

[`JanetTryState` in `janet.h`](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/include/janet.h#L1234-L1245):

```c
/* For janet_try and janet_restore */
typedef struct {
    /* old state */
    int32_t stackn;
    int gc_handle;
    JanetFiber *vm_fiber;
    jmp_buf *vm_jmp_buf;
    Janet *vm_return_reg;
    /* new state */
    jmp_buf buf;
    Janet payload;
} JanetTryState;
```