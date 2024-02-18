# ev/cancel

## Information

`(ev/cancel fiber err)`

Cancel a suspended fiber in the event loop.

Differs from cancel in that it returns the canceled fiber immediately.

## Sample Code

```janet
(def f
  (ev/spawn
    (try
      (do
        (print "starting long io...")
        (ev/sleep 10000)
        (print "finished long io!"))
      ([e]
        (eprint "aha!")))))

# wait 2 seconds before canceling the long IO.
(ev/sleep 2)
(ev/cancel f "canceled")
```

Sample output:

```
starting long io...
aha!
```

Note in the above that the fiber being subject to `ev/cancel` had a
chance to handle the error.

## C Implementation

[`cfun_ev_cancel` in `ev.c`](https://github.com/janet-lang/janet/blob/e66dc14b3ad6210e1bfa398e5c8fbe266cbfdd36/src/core/ev.c#L2970-L2973):

```c
    JanetFiber *fiber = janet_getfiber(argv, 0);
    Janet err = argv[1];
    janet_cancel(fiber, err);
    return argv[0];
```

[`janet_cancel` and friends in `ev.c`](https://github.com/janet-lang/janet/blob/e66dc14b3ad6210e1bfa398e5c8fbe266cbfdd36/src/core/ev.c#L477-L504):

```c
/* Register a fiber to resume with value */
static void janet_schedule_general(JanetFiber *fiber, Janet value, JanetSignal sig, int soon) {
    if (fiber->gc.flags & JANET_FIBER_EV_FLAG_CANCELED) return;
    if (!(fiber->gc.flags & JANET_FIBER_FLAG_ROOT)) {
        Janet task_element = janet_wrap_fiber(fiber);
        janet_table_put(&janet_vm.active_tasks, task_element, janet_wrap_true());
    }
    JanetTask t = { fiber, value, sig, ++fiber->sched_id };
    fiber->gc.flags |= JANET_FIBER_FLAG_ROOT;
    if (sig == JANET_SIGNAL_ERROR) fiber->gc.flags |= JANET_FIBER_EV_FLAG_CANCELED;
    if (soon) {
        janet_q_push_head(&janet_vm.spawn, &t, sizeof(t));
    } else {
        janet_q_push(&janet_vm.spawn, &t, sizeof(t));
    }
}

void janet_schedule_signal(JanetFiber *fiber, Janet value, JanetSignal sig) {
    janet_schedule_general(fiber, value, sig, 0);
}

// ... elided ... //

void janet_cancel(JanetFiber *fiber, Janet value) {
    janet_schedule_signal(fiber, value, JANET_SIGNAL_ERROR);
}
```

[`janet_q_push` and `janet_q_push_head` in `ev.c`](https://github.com/janet-lang/janet/blob/9142f38cbceb72e7d2d8a12846d2c22c2322fc34/src/core/ev.c#L160-L176):

```c
static int janet_q_push(JanetQueue *q, void *item, size_t itemsize) {
    if (janet_q_maybe_resize(q, itemsize)) return 1;
    memcpy((char *) q->data + itemsize * q->tail, item, itemsize);
    q->tail = q->tail + 1 < q->capacity ? q->tail + 1 : 0;
    return 0;
}

static int janet_q_push_head(JanetQueue *q, void *item, size_t itemsize) {
    if (janet_q_maybe_resize(q, itemsize)) return 1;
    int32_t newhead = q->head - 1;
    if (newhead < 0) {
        newhead += q->capacity;
    }
    memcpy((char *) q->data + itemsize * newhead, item, itemsize);
    q->head = newhead;
    return 0;
}
```

[`janet_q_pop` in `ev.c`](https://github.com/janet-lang/janet/blob/9142f38cbceb72e7d2d8a12846d2c22c2322fc34/src/core/ev.c#L178-L183):

```c
static int janet_q_pop(JanetQueue *q, void *out, size_t itemsize) {
    if (q->head == q->tail) return 1;
    memcpy(out, (char *) q->data + itemsize * q->head, itemsize);
    q->head = q->head + 1 < q->capacity ? q->head + 1 : 0;
    return 0;
}
```

[`janet_loop1` running scheduled fibers bit in `ev.c`](https://github.com/janet-lang/janet/blob/9142f38cbceb72e7d2d8a12846d2c22c2322fc34/src/core/ev.c#L1312-L1322):

```c
    /* Run scheduled fibers unless interrupts need to be handled. */
    while (janet_vm.spawn.head != janet_vm.spawn.tail) {
        /* Don't run until all interrupts have been marked as handled by calling janet_interpreter_interrupt_handled */
        if (janet_vm.auto_suspend) break;
        JanetTask task = {NULL, janet_wrap_nil(), JANET_SIGNAL_OK, 0};
        janet_q_pop(&janet_vm.spawn, &task, sizeof(task));
        if (task.fiber->gc.flags & JANET_FIBER_EV_FLAG_SUSPENDED) janet_ev_dec_refcount();
        task.fiber->gc.flags &= ~(JANET_FIBER_EV_FLAG_CANCELED | JANET_FIBER_EV_FLAG_SUSPENDED);
        if (task.expected_sched_id != task.fiber->sched_id) continue;
        Janet res;
        JanetSignal sig = janet_continue_signal(task.fiber, task.value, &res, task.sig);
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