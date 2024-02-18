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

