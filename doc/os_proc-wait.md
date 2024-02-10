# os/proc-wait

## Information

`(os/proc-wait proc)`

Suspend the current fiber until the subprocess completes. Returns the
subprocess return code.

> info for website docs?

Should not be called twice on the same process.

> not sure what this means, but also for website docs?

If cancelled with an error(?), it still finishes in the background.

> the claim of the first sentence below seems to be referring to the
> following -- at least on unix-like systems, the parent of a process
> is expected to call wait (or similar) and only after this will the
> operating system perform a removal of a process' entry from a
> certain data structure ("process table").  this is generic info that
> may not be relevant for windows.

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

[`janet_ev_threaded_call` in ev.c](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/ev.c#L1998-L2027):

```c
void janet_ev_threaded_call(JanetThreadedSubroutine fp, JanetEVGenericMessage arguments, JanetThreadedCallback cb) {
    JanetEVThreadInit *init = janet_malloc(sizeof(JanetEVThreadInit));
    if (NULL == init) {
        JANET_OUT_OF_MEMORY;
    }
    init->msg = arguments;
    init->subr = fp;
    init->cb = cb;

#ifdef JANET_WINDOWS
    init->write_pipe = janet_vm.iocp;
    HANDLE thread_handle = CreateThread(NULL, 0, janet_thread_body, init, 0, NULL);
    if (NULL == thread_handle) {
        janet_free(init);
        janet_panic("failed to create thread");
    }
    CloseHandle(thread_handle); /* detach from thread */
#else
    init->write_pipe = janet_vm.selfpipe[1];
    pthread_t waiter_thread;
    int err = pthread_create(&waiter_thread, &janet_vm.new_thread_attr, janet_thread_body, init);
    if (err) {
        janet_free(init);
        janet_panicf("%s", strerror(err));
    }
#endif

    /* Increment ev refcount so we don't quit while waiting for a subprocess */
    janet_ev_inc_refcount();
}
```

[`janet_thread_body` in ev.c](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/ev.c#L1954-L1996):

```c
#ifdef JANET_WINDOWS
static DWORD WINAPI janet_thread_body(LPVOID ptr) {
    JanetEVThreadInit *init = (JanetEVThreadInit *)ptr;
    JanetEVGenericMessage msg = init->msg;
    JanetThreadedSubroutine subr = init->subr;
    JanetThreadedCallback cb = init->cb;
    JanetHandle iocp = init->write_pipe;
    /* Reuse memory from thread init for returning data */
    init->msg = subr(msg);
    init->cb = cb;
    janet_assert(PostQueuedCompletionStatus(iocp,
                                            sizeof(JanetSelfPipeEvent),
                                            0,
                                            (LPOVERLAPPED) init),
                 "failed to post completion event");
    return 0;
}
#else
static void *janet_thread_body(void *ptr) {
    JanetEVThreadInit *init = (JanetEVThreadInit *)ptr;
    JanetEVGenericMessage msg = init->msg;
    JanetThreadedSubroutine subr = init->subr;
    JanetThreadedCallback cb = init->cb;
    int fd = init->write_pipe;
    janet_free(init);
    JanetSelfPipeEvent response;
    memset(&response, 0, sizeof(response));
    response.msg = subr(msg);
    response.cb = cb;
    /* handle a bit of back pressure before giving up. */
    int tries = 4;
    while (tries > 0) {
        int status;
        do {
            status = write(fd, &response, sizeof(response));
        } while (status == -1 && errno == EINTR);
        if (status > 0) break;
        sleep(1);
        tries--;
    }
    return NULL;
}
#endif
```

[`janet_proc_wait_subr` and `janet_proc_wait_cb` in os.c](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/os.c#L482-L544):

```c
#ifdef JANET_EV

#ifdef JANET_WINDOWS

static JanetEVGenericMessage janet_proc_wait_subr(JanetEVGenericMessage args) {
    JanetProc *proc = (JanetProc *) args.argp;
    WaitForSingleObject(proc->pHandle, INFINITE);
    DWORD exitcode = 0;
    GetExitCodeProcess(proc->pHandle, &exitcode);
    args.tag = (int32_t) exitcode;
    return args;
}

#else /* windows check */

static int proc_get_status(JanetProc *proc) {
    /* Use POSIX shell semantics for interpreting signals */
    int status = 0;
    pid_t result;
    do {
        result = waitpid(proc->pid, &status, 0);
    } while (result == -1 && errno == EINTR);
    if (WIFEXITED(status)) {
        status = WEXITSTATUS(status);
    } else if (WIFSTOPPED(status)) {
        status = WSTOPSIG(status) + 128;
    } else {
        status = WTERMSIG(status) + 128;
    }
    return status;
}

/* Function that is called in separate thread to wait on a pid */
static JanetEVGenericMessage janet_proc_wait_subr(JanetEVGenericMessage args) {
    JanetProc *proc = (JanetProc *) args.argp;
    args.tag = proc_get_status(proc);
    return args;
}

#endif /* End windows check */

/* Callback that is called in main thread when subroutine completes. */
static void janet_proc_wait_cb(JanetEVGenericMessage args) {
    JanetProc *proc = (JanetProc *) args.argp;
    if (NULL != proc) {
        int status = args.tag;
        proc->return_code = (int32_t) status;
        proc->flags |= JANET_PROC_WAITED;
        proc->flags &= ~JANET_PROC_WAITING;
        janet_gcunroot(janet_wrap_abstract(proc));
        janet_gcunroot(janet_wrap_fiber(args.fiber));
        if ((status != 0) && (proc->flags & JANET_PROC_ERROR_NONZERO)) {
            JanetString s = janet_formatc("command failed with non-zero exit code %d", status);
            janet_cancel(args.fiber, janet_wrap_string(s));
        } else {
            if (janet_fiber_can_resume(args.fiber)) {
                janet_schedule(args.fiber, janet_wrap_integer(status));
            }
        }
    }
}

#endif /* End ev check */
```

[`janet_loop1_impl` in ev.c](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/ev.c#L1575) (though actually there are four implementations (Windows, EPOLL, KQUEUE, and POLL)):

EPOLL, KQUEUE, POLL:

```c
void janet_loop1_impl(int has_timeout, JanetTimestamp timeout) {
  // ... elided ...

            janet_ev_handle_selfpipe();

  // ... elided ...
```

Windows:

```c
void janet_loop1_impl(int has_timeout, JanetTimestamp timeout) {
  // ... elided ...

            /* Custom event */
            JanetSelfPipeEvent *response = (JanetSelfPipeEvent *)(overlapped);
            if (NULL != response->cb) {
                response->cb(response->msg);
            }
            janet_ev_dec_refcount();

  // ... elided ...
```

[`janet_ev_handle_selfpipe` in ev.c](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/ev.c#L1414-L1429):

EPOLL, KQUEUE, POLL:

```c
/* Handle events from the self pipe inside the event loop */
static void janet_ev_handle_selfpipe(void) {
    JanetSelfPipeEvent response;
    int status;
recur:
    do {
        status = read(janet_vm.selfpipe[0], &response, sizeof(response));
    } while (status == -1 && errno == EINTR);
    if (status > 0) {
        if (NULL != response.cb) {
            response.cb(response.msg);
            janet_ev_dec_refcount();
        }
        goto recur;
    }
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

[`janet_try` in `janet.h`](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/include/janet.h#L1791-L1795):

```c
#if defined(JANET_BSD) || defined(JANET_APPLE)
#define janet_try(state) (janet_try_init(state), (JanetSignal) _setjmp((state)->buf))
#else
#define janet_try(state) (janet_try_init(state), (JanetSignal) setjmp((state)->buf))
#endif
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