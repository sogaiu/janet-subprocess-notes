# os/execute

## Information

`(os/execute args &opt flags env)`

Execute a program on the system.

`args` is a tuple or array of strings for an invocation of a program
along with arguments.

`flags` is a keyword that modifies how the program will execute.

* :e - enables passing an environment to the program. Without :e, the
  current environment is inherited.

* :p - allows searching the current PATH for the binary to execute.
  Without this flag, binaries must use absolute paths.

* :x - raise error if exit code is non-zero.

* :d - Don't try and terminate the process on garbage collection
  (allow spawning zombies).

`env` is a table or struct mapping environment variables to values.
It can also contain the keys :in, :out, and :err, which allow
redirecting stdio in the subprocess. The values associated with these
keys should be core/file values. For better results, close these
values explicitly, but after the subprocess has completed.

Returns the exit code of the program.

## Sample Code

```janet
(def fpath "/tmp/fun.log")
(def of (file/open fpath :w))
(os/execute ["ls" "-al"] :p {:out of})
# XXX: can work without closing (sometimes?), but better to close
(file/close of)
(print (slurp fpath))
```

Example of something that may work in some cases, but not recommended
in general:

```janet
(def [rs ws] (os/pipe))
(os/execute ["ls"] :p {:out ws})
# close ws before reading from rs
(ev/close ws)
(print (ev/read rs :all))
(ev/close rs)
```
