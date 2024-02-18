# cancel

## Information

`(cancel fiber err)`

Resume a fiber but have it immediately raise an error.

This lets a programmer unwind a pending fiber.

Returns the same result as `resume`.

## Sample Code

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

Sample output:

```
nifty
```

Note in the above that the fiber being subject to `cancel` had a
chance to handle the error.

## C Implementation

[`JOP_CANCEL` in `run_vm` in `vm.c`](https://github.com/janet-lang/janet/blob/master/src/core/vm.c#L1137-L1154):

```c
    VM_OP(JOP_CANCEL) {
        Janet retreg;
        vm_assert_type(stack[B], JANET_FIBER);
        JanetFiber *child = janet_unwrap_fiber(stack[B]);
        if (janet_check_can_resume(child, &retreg, 1)) {
            vm_commit();
            janet_panicv(retreg);
        }
        fiber->child = child;
        JanetSignal sig = janet_continue_signal(child, stack[C], &retreg, JANET_SIGNAL_ERROR);
        if (sig != JANET_SIGNAL_OK && !(child->flags & (1 << sig))) {
            vm_return(sig, retreg);
        }
        fiber->child = NULL;
        stack = fiber->data + fiber->frame;
        stack[A] = retreg;
        vm_checkgc_pcnext();
    }
```

[`janet_continue_signal` in `vm.c`](https://github.com/janet-lang/janet/blob/master/src/core/vm.c#L1535-L1547):

```c
/* Enter the main vm loop but immediately raise a signal */
JanetSignal janet_continue_signal(JanetFiber *fiber, Janet in, Janet *out, JanetSignal sig) {
    JanetSignal tmp_signal = janet_check_can_resume(fiber, out, sig != JANET_SIGNAL_OK);
    if (tmp_signal) return tmp_signal;
    if (sig != JANET_SIGNAL_OK) {
        JanetFiber *child = fiber;
        while (child->child) child = child->child;
        child->gc.flags &= ~JANET_FIBER_STATUS_MASK;
        child->gc.flags |= sig << JANET_FIBER_STATUS_OFFSET;
        child->flags |= JANET_FIBER_RESUME_SIGNAL;
    }
    return janet_continue_no_check(fiber, in, out);
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
