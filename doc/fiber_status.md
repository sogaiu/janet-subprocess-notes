# fiber/status

## Information

`(fiber/status fib)`

Get the status of a fiber. The status will be one of:

> the prose term "suspended" is used below, but this doesn't seem to
> correspond exactly to a status of :suspended.

> :dead, :error, :debug, :pending, :user(0-9), :alive, and :new were
> added to the docstring in 2018-11-16.  the associated text for each
> state has not changed since then.

> the name :suspended was given to what used to be called :user9
> and was added to the docstring in 2023-04

> thus the prose term "suspended" had been used for somewhat over four
> years to describe that the "fiber is suspended" for :debug and
> :user(0-9) before :suspended came about.

* :dead - the fiber has finished
* :error - the fiber has errored out
* :debug - the fiber is suspended in debug mode
* :pending - the fiber has been yielded
* :user(0-7) - the fiber is suspended by a user signal
* :interrupted - the fiber was interrupted
* :suspended - the fiber is waiting to be resumed by the scheduler
* :alive - the fiber is currently running and cannot be resumed
* :new - the fiber has just been created and not yet run

## Sample Code

```janet
(fiber/status (fiber/new (fn [] nil)))
# =>
:new
```

```janet
(def fib (coro :a))

(resume fib)
# =>
:a

(fiber/status fib)
# =>
:dead
```

```janet
(def fib (coro (yield 1)))

(resume fib)
# =>
1

(fiber/status fib)
# =>
:pending
```

```janet
(def fib (coro (error :hey)))

(protect (resume fib))
# =>
[false :hey]

(fiber/status fib)
# =>
:error
```

```janet
(def fib
  (fiber/new |(signal 0 :hi)
             :0))

(resume fib)
# =>
:hi

(fiber/status fib)
# =>
:user0
```

```janet
(def fib (ev/spawn (forever (ev/sleep 1))))

(fiber/status fib)
# =>
:new

(ev/sleep 0)
# =>
nil

(fiber/status fib)
:suspended
```

## C Implementation

[`cfun_fiber_status` in `fiber.c`](https://github.com/janet-lang/janet/blob/23b0fe9f8e9bcc391fe94b18db379c73f1e2c8a2/src/core/fiber.c#L598-L600):

```c
    JanetFiber *fiber = janet_getfiber(argv, 0);
    uint32_t s = janet_fiber_status(fiber);
    return janet_ckeywordv(janet_status_names[s]);
```

[`janet_getfiber` and `DEFINE_GETTER` in `capi.c`](https://github.com/janet-lang/janet/blob/23b0fe9f8e9bcc391fe94b18db379c73f1e2c8a2/src/core/capi.c#L117-L124):

```c
#define DEFINE_GETTER(name, NAME, type) \
type janet_get##name(const Janet *argv, int32_t n) { \
    Janet x = argv[n]; \
    if (!janet_checktype(x, JANET_##NAME)) { \
        janet_panic_type(x, n, JANET_TFLAG_##NAME); \
    } \
    return janet_unwrap_##name(x); \
}

// ... elided ... //

DEFINE_GETTER(fiber, FIBER, JanetFiber *)
```

[`JanetFiber` in `janet.h`](https://github.com/janet-lang/janet/blob/23b0fe9f8e9bcc391fe94b18db379c73f1e2c8a2/src/include/janet.h#L919-L944):

```c
/* A lightweight green thread in janet. Does not correspond to
 * operating system threads. */
struct JanetFiber {
    JanetGCObject gc; /* GC Object stuff */
    int32_t flags; /* More flags */
    int32_t frame; /* Index of the stack frame */
    int32_t stackstart; /* Beginning of next args */
    int32_t stacktop; /* Top of stack. Where values are pushed and popped from. */
    int32_t capacity; /* How big is the stack memory */
    int32_t maxstack; /* Arbitrary defined limit for stack overflow */
    JanetTable *env; /* Dynamic bindings table (usually current environment). */
    Janet *data; /* Dynamically resized stack memory */
    JanetFiber *child; /* Keep linked list of fibers for restarting pending fibers */
    Janet last_value; /* Last returned value from a fiber */
#ifdef JANET_EV
    /* These fields are only relevant for fibers that are used as "root fibers" -
     * that is, fibers that are scheduled on the event loop and behave much like threads
     * in a multi-tasking system. It would be possible to move these fields to a new
     * type, say "JanetTask", that as separate from fibers to save a bit of space. */
    uint32_t sched_id; /* Increment everytime fiber is scheduled by event loop */
    JanetEVCallback ev_callback; /* Call this before starting scheduled fibers */
    JanetStream *ev_stream; /* which stream we are waiting on */
    void *ev_state; /* Extra data for ev callback state. On windows, first element must be OVERLAPPED. */
    void *supervisor_channel; /* Channel to push self to when complete */
#endif
};
```

[`janet_fiber_status` in `fiber.c`](https://github.com/janet-lang/janet/blob/23b0fe9f8e9bcc391fe94b18db379c73f1e2c8a2/src/core/fiber.c#L442-L444):

```c
JanetFiberStatus janet_fiber_status(JanetFiber *f) {
    return ((f)->flags & JANET_FIBER_STATUS_MASK) >> JANET_FIBER_STATUS_OFFSET;
}
```

[`JanetFiberStatus` in `janet.h`](https://github.com/janet-lang/janet/blob/23b0fe9f8e9bcc391fe94b18db379c73f1e2c8a2/src/include/janet.h#L419-L437):

```c
/* Fiber statuses - mostly corresponds to signals. */
typedef enum {
    JANET_STATUS_DEAD,
    JANET_STATUS_ERROR,
    JANET_STATUS_DEBUG,
    JANET_STATUS_PENDING,
    JANET_STATUS_USER0,
    JANET_STATUS_USER1,
    JANET_STATUS_USER2,
    JANET_STATUS_USER3,
    JANET_STATUS_USER4,
    JANET_STATUS_USER5,
    JANET_STATUS_USER6,
    JANET_STATUS_USER7,
    JANET_STATUS_USER8,
    JANET_STATUS_USER9,
    JANET_STATUS_NEW,
    JANET_STATUS_ALIVE
} JanetFiberStatus;
```

[`janet_status_names` in `util.c`](https://github.com/janet-lang/janet/blob/23b0fe9f8e9bcc391fe94b18db379c73f1e2c8a2/src/core/util.c#L99-L116):

```c
const char *const janet_status_names[16] = {
    "dead",
    "error",
    "debug",
    "pending",
    "user0",
    "user1",
    "user2",
    "user3",
    "user4",
    "user5",
    "user6",
    "user7",
    "interrupted",
    "suspended",
    "new",
    "alive"
};
```