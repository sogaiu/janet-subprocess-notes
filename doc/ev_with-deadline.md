# ev/with-deadline

## Information

`(ev/with-deadline deadline & body)`

Run a body of code with a deadline, such that if the code does not
complete before the deadline is up, it will be canceled.

`deadline` is a number of seconds that can have a fractional part.

## Sample Code

```janet
(ev/with-deadline 0.1
                  (def p (os/spawn ["find" "/"] :p))
                  (os/proc-wait p))
```

## Janet Implementation

```janet
(defmacro ev/with-deadline
  [deadline & body]
  (with-syms [f]
    ~(let [,f (coro ,;body)]
       (,ev/deadline ,deadline nil ,f)
       (,resume ,f))))
```
