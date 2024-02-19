# resume

## Information

`(resume fiber &opt x)`

Resume a new or suspended fiber and optionally pass in a value to the
fiber that will be returned to the last yield in the case of a pending
fiber, or the argument to the dispatch function in the case of a new
fiber.

Returns either the return result of the fiber's dispatch function, or
the value from the next yield call in fiber.

## Sample Code

```janet
(pp (resume (coro (yield :a))))
```

Sample output:

```
:a
```

```janet
(pp (resume (fiber/new |(yield $))
            -1))
```

Sample output:

```
7
```


## C Implementation

[`JOP_RESUME` in `run_vm` in `vm.c`](https://github.com/janet-lang/janet/blob/23b0fe9f8e9bcc391fe94b18db379c73f1e2c8a2/src/core/vm.c#L1096-L1114):

```c
    VM_OP(JOP_RESUME) {
        Janet retreg;
        vm_maybe_auto_suspend(1);
        vm_assert_type(stack[B], JANET_FIBER);
        JanetFiber *child = janet_unwrap_fiber(stack[B]);
        if (janet_check_can_resume(child, &retreg, 0)) {
            vm_commit();
            janet_panicv(retreg);
        }
        fiber->child = child;
        JanetSignal sig = janet_continue_no_check(child, stack[C], &retreg);
        if (sig != JANET_SIGNAL_OK && !(child->flags & (1 << sig))) {
            vm_return(sig, retreg);
        }
        fiber->child = NULL;
        stack = fiber->data + fiber->frame;
        stack[A] = retreg;
        vm_checkgc_pcnext();
    }
```

[`janet_check_can_resume` in `vm.c`](https://github.com/janet-lang/janet/blob/23b0fe9f8e9bcc391fe94b18db379c73f1e2c8a2/src/core/vm.c#L1393-L1425):

```c
static JanetSignal janet_check_can_resume(JanetFiber *fiber, Janet *out, int is_cancel) {
    /* Check conditions */
    JanetFiberStatus old_status = janet_fiber_status(fiber);
    if (janet_vm.stackn >= JANET_RECURSION_GUARD) {
        janet_fiber_set_status(fiber, JANET_STATUS_ERROR);
        *out = janet_cstringv("C stack recursed too deeply");
        return JANET_SIGNAL_ERROR;
    }
    /* If a "task" fiber is trying to be used as a normal fiber, detect that. See bug #920.
     * Fibers must be marked as root fibers manually, or by the ev scheduler. */
    if (janet_vm.fiber != NULL && (fiber->gc.flags & JANET_FIBER_FLAG_ROOT)) {
#ifdef JANET_EV
        *out = janet_cstringv(is_cancel
                              ? "cannot cancel root fiber, use ev/cancel"
                              : "cannot resume root fiber, use ev/go");
#else
        *out = janet_cstringv(is_cancel
                              ? "cannot cancel root fiber"
                              : "cannot resume root fiber");
#endif
        return JANET_SIGNAL_ERROR;
    }
    if (old_status == JANET_STATUS_ALIVE ||
            old_status == JANET_STATUS_DEAD ||
            (old_status >= JANET_STATUS_USER0 && old_status <= JANET_STATUS_USER4) ||
            old_status == JANET_STATUS_ERROR) {
        const uint8_t *str = janet_formatc("cannot resume fiber with status :%s",
                                           janet_status_names[old_status]);
        *out = janet_wrap_string(str);
        return JANET_SIGNAL_ERROR;
    }
    return JANET_SIGNAL_OK;
}
```

[`janet_continue_no_check` in `vm.c`](https://github.com/janet-lang/janet/blob/master/src/core/vm.c#L1445-L1525):

```c
static JanetSignal janet_continue_no_check(JanetFiber *fiber, Janet in, Janet *out) {

    JanetFiberStatus old_status = janet_fiber_status(fiber);

#ifdef JANET_EV
    janet_fiber_did_resume(fiber);
#endif

    /* Clear last value */
    fiber->last_value = janet_wrap_nil();

    /* Continue child fiber if it exists */
    if (fiber->child) {
        if (janet_vm.root_fiber == NULL) janet_vm.root_fiber = fiber;
        JanetFiber *child = fiber->child;
        uint32_t instr = (janet_stack_frame(fiber->data + fiber->frame)->pc)[0];
        janet_vm.stackn++;
        JanetSignal sig = janet_continue(child, in, &in);
        janet_vm.stackn--;
        if (janet_vm.root_fiber == fiber) janet_vm.root_fiber = NULL;
        if (sig != JANET_SIGNAL_OK && !(child->flags & (1 << sig))) {
            *out = in;
            janet_fiber_set_status(fiber, sig);
            fiber->last_value = child->last_value;
            return sig;
        }
        /* Check if we need any special handling for certain opcodes */
        switch (instr & 0x7F) {
            default:
                break;
            case JOP_NEXT: {
                if (sig == JANET_SIGNAL_OK ||
                        sig == JANET_SIGNAL_ERROR ||
                        sig == JANET_SIGNAL_USER0 ||
                        sig == JANET_SIGNAL_USER1 ||
                        sig == JANET_SIGNAL_USER2 ||
                        sig == JANET_SIGNAL_USER3 ||
                        sig == JANET_SIGNAL_USER4) {
                    in = janet_wrap_nil();
                } else {
                    in = janet_wrap_integer(0);
                }
                break;
            }
        }
        fiber->child = NULL;
    }

    /* Handle new fibers being resumed with a non-nil value */
    if (old_status == JANET_STATUS_NEW && !janet_checktype(in, JANET_NIL)) {
        Janet *stack = fiber->data + fiber->frame;
        JanetFunction *func = janet_stack_frame(stack)->func;
        if (func) {
            if (func->def->arity > 0) {
                stack[0] = in;
            } else if (func->def->flags & JANET_FUNCDEF_FLAG_VARARG) {
                stack[0] = janet_wrap_tuple(janet_tuple_n(&in, 1));
            }
        }
    }

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
}
```
