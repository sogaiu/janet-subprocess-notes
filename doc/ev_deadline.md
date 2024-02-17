# ev/deadline

## Information

`(ev/deadline sec &opt tocancel tocheck)`

> may be the argument fibers have to be of the type that are on the
> event loop?  seems the answer is yes.  there is no error indication
> when passing normal fibers though.

Set a deadline for a fiber `tocheck`.

If `tocheck` is not finished after `sec` seconds, `tocancel` will be
canceled as with `ev/cancel`.

If `tocancel` and `tocheck` are not given, they default to
`(fiber/root)` and `(fiber/current)` respectively.

Returns `tocancel`.

## Sample Code

```janet
(def check-wait 1.1)
(def cancel-wait (* 2 check-wait))
(def deadline (* 0.5 check-wait))

(ev/deadline
  deadline
  (ev/go
    (fiber/new (fn []
                 (print "tocancel: started")
                 (printf "tocancel: waiting: %n sec" cancel-wait)
                 (ev/sleep cancel-wait)
                 (print "tocancel: ended"))))
  (ev/go
    (fiber/new (fn []
                 (print "tocheck: started")
                 (printf "tocheck: waiting: %n sec" check-wait)
                 (ev/sleep check-wait)
                 (print "tocheck: ended")))))
```

Sample output:

```
tocancel: started
tocancel: waiting: 2.2 sec
tocheck: started
tocheck: waiting: 1.1 sec
error: deadline expired
  in ev/sleep [src/core/ev.c] on line 2938
  in _spawn [ev-deadline.janet] on line 9, column 16
tocheck: ended
```

## C Implementation

[`ev/deadline` in ev.c](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/ev.c#L2953-L2963):

```c
    double sec = janet_getnumber(argv, 0);
    JanetFiber *tocancel = janet_optfiber(argv, argc, 1, janet_vm.root_fiber);
    JanetFiber *tocheck = janet_optfiber(argv, argc, 2, janet_vm.fiber);
    JanetTimeout to;
    to.when = ts_delta(ts_now(), sec);
    to.fiber = tocancel;
    to.curr_fiber = tocheck;
    to.is_error = 0;
    to.sched_id = to.fiber->sched_id;
    add_timeout(to);
    return janet_wrap_fiber(tocancel);
```

[`JanetTimeout` in state.h](https://github.com/janet-lang/janet/blob/master/src/core/state.h#L56-L62):

```c
typedef struct {
    JanetTimestamp when;
    JanetFiber *fiber;
    JanetFiber *curr_fiber;
    uint32_t sched_id;
    int is_error;
} JanetTimeout;
```

[`add_timeout` in ev.c](https://github.com/janet-lang/janet/blob/9142f38cbceb72e7d2d8a12846d2c22c2322fc34/src/core/ev.c#L226-L254):

```c
/* Add a timeout to the timeout min heap */
static void add_timeout(JanetTimeout to) {
    size_t oldcount = janet_vm.tq_count;
    size_t newcount = oldcount + 1;
    if (newcount > janet_vm.tq_capacity) {
        size_t newcap = 2 * newcount;
        JanetTimeout *tq = janet_realloc(janet_vm.tq, newcap * sizeof(JanetTimeout));
        if (NULL == tq) {
            JANET_OUT_OF_MEMORY;
        }
        janet_vm.tq = tq;
        janet_vm.tq_capacity = newcap;
    }
    /* Append */
    janet_vm.tq_count = (int32_t) newcount;
    janet_vm.tq[oldcount] = to;
    /* Heapify */
    size_t index = oldcount;
    while (index > 0) {
        size_t parent = (index - 1) >> 1;
        if (janet_vm.tq[parent].when <= janet_vm.tq[index].when) break;
        /* Swap */
        JanetTimeout tmp = janet_vm.tq[index];
        janet_vm.tq[index] = janet_vm.tq[parent];
        janet_vm.tq[parent] = tmp;
        /* Next */
        index = parent;
    }
}
```

[`janet_vm.tq` and friends in state.h](https://github.com/janet-lang/janet/blob/9142f38cbceb72e7d2d8a12846d2c22c2322fc34/src/core/state.h#L152-L162):

```c
    /* Event loop and scheduler globals */
#ifdef JANET_EV
    size_t tq_count;
    size_t tq_capacity;
    JanetQueue spawn;
    JanetTimeout *tq;
    JanetRNG ev_rng;
    volatile JanetAtomicInt listener_count; /* used in signal handler, must be volatile */
    JanetTable threaded_abstracts; /* All abstract types that can be shared between threads (used in this thread) */
    JanetTable active_tasks; /* All possibly live task fibers - used just for tracking */
    JanetTable signal_handlers;
```

[`janet_loop1` scheduling expired timers bit in ev.c](https://github.com/janet-lang/janet/blob/9142f38cbceb72e7d2d8a12846d2c22c2322fc34/src/core/ev.c#L1294-L1310):

```c
JanetFiber *janet_loop1(void) {
    /* Schedule expired timers */
    JanetTimeout to;
    JanetTimestamp now = ts_now();
    while (peek_timeout(&to) && to.when <= now) {
        pop_timeout(0);
        if (to.curr_fiber != NULL) {
            if (janet_fiber_can_resume(to.curr_fiber)) {
                janet_cancel(to.fiber, janet_cstringv("deadline expired"));
            }
        } else {
          // ... elided ...
        }
    }
```

[`peek_timeout` in ev.c](https://github.com/janet-lang/janet/blob/9142f38cbceb72e7d2d8a12846d2c22c2322fc34/src/core/ev.c#L197-L202):

```c
/* Look at the next timeout value without removing it. */
static int peek_timeout(JanetTimeout *out) {
    if (janet_vm.tq_count == 0) return 0;
    *out = janet_vm.tq[0];
    return 1;
}
```

[`pop_timeout` in ev.c](https://github.com/janet-lang/janet/blob/9142f38cbceb72e7d2d8a12846d2c22c2322fc34/src/core/ev.c#L204-L224):

```c
/* Remove the next timeout from the priority queue */
static void pop_timeout(size_t index) {
    if (janet_vm.tq_count <= index) return;
    janet_vm.tq[index] = janet_vm.tq[--janet_vm.tq_count];
    for (;;) {
        size_t left = (index << 1) + 1;
        size_t right = left + 1;
        size_t smallest = index;
        if (left < janet_vm.tq_count &&
                (janet_vm.tq[left].when < janet_vm.tq[smallest].when))
            smallest = left;
        if (right < janet_vm.tq_count &&
                (janet_vm.tq[right].when < janet_vm.tq[smallest].when))
            smallest = right;
        if (smallest == index) return;
        JanetTimeout temp = janet_vm.tq[index];
        janet_vm.tq[index] = janet_vm.tq[smallest];
        janet_vm.tq[smallest] = temp;
        index = smallest;
    }
}
```

[`janet_cancel`, `janet_schedule`, and related in ev.c](https://github.com/janet-lang/janet/blob/9142f38cbceb72e7d2d8a12846d2c22c2322fc34/src/core/ev.c#L477-L508):

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

void janet_schedule_soon(JanetFiber *fiber, Janet value, JanetSignal sig) {
    janet_schedule_general(fiber, value, sig, 1);
}

void janet_cancel(JanetFiber *fiber, Janet value) {
    janet_schedule_signal(fiber, value, JANET_SIGNAL_ERROR);
}

void janet_schedule(JanetFiber *fiber, Janet value) {
    janet_schedule_signal(fiber, value, JANET_SIGNAL_OK);
}
```

[`janet_q_push` and `janet_q_push_head` in ev.c](https://github.com/janet-lang/janet/blob/9142f38cbceb72e7d2d8a12846d2c22c2322fc34/src/core/ev.c#L160-L176):

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

[`janet_q_pop` in ev.c](https://github.com/janet-lang/janet/blob/9142f38cbceb72e7d2d8a12846d2c22c2322fc34/src/core/ev.c#L178-L183):

```c
static int janet_q_pop(JanetQueue *q, void *out, size_t itemsize) {
    if (q->head == q->tail) return 1;
    memcpy(out, (char *) q->data + itemsize * q->head, itemsize);
    q->head = q->head + 1 < q->capacity ? q->head + 1 : 0;
    return 0;
}
```

[`janet_loop1` running scheduled fibers bit in ev.c](https://github.com/janet-lang/janet/blob/9142f38cbceb72e7d2d8a12846d2c22c2322fc34/src/core/ev.c#L1312-L1322):

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
