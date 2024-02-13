# os/spawn

## Information

`(os/spawn args &opt flags env)`

Execute a program on the system and return a handle to the process.

Otherwise, takes the same arguments as `os/execute`.

Does not wait for the process.

For each of the :in, :out, and :err keys of the `env` argument, one
can also pass in the keyword :pipe to get streams for standard IO of
the subprocess that can be read from and written to.

The returned value proc has the fields :in, :out, :err, and the
additional field :pid on unix-like platforms.  Use `(os/proc-wait
proc)` to rejoin the subprocess. After waiting completes, proc gains a
new field, :return-code.

> below seems true (even for Windows), initially thought it would be
> better to put the info at the website, but now am not so sure

If :x flag is used, a non-zero exit code will cause calls to certain
functions such as `os/proc-wait`, `os/proc-close`, and `os/proc-kill`
(things that lead to a call of `os_proc_wait_impl` [1] basically can
trigger [this
code](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/os.c#L533-L535))
to raise an error.

[1] [`os/execute` (but not `os/spawn`) can also call
`os_proc_wait_impl`.](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/os.c#L1360-L1361)

```janet
(def p (os/spawn ["ls" "1"] :px))

(try
  (os/proc-wait p)
  ([e]
   (eprint "error from os/proc-wait")
   (eprint e)))
```

```janet
(def p (os/spawn ["ls" "1"] :px))

(try
  (os/proc-close p)
  ([e]
   (eprint "error from os/proc-close")
   (eprint e)))
```

> below seems true, but possibly better for website docs (e.g. the
> functionality of `os/proc-close` is duplicating info from
> `os/proc-close`'s docstring)

If pipe streams created with :pipe keyword are not closed soon enough,
a janet process can run out of file descriptors. They can be closed
individually, or `os/proc-close` can close all pipe streams on proc.

> though important, stuff below here appears to be generic programming
> info (for certain operating systems?) and as such doesn't feel right
> in a docstring.  in the website docs might be ok though.

> is it always true that "pipe buffers become full", or is it that
> it's a likely risk?  see for example
> [this](https://unix.stackexchange.com/questions/11946/how-big-is-the-pipe-buffer)

> current sense is that it's not always the case, more like "pipe
> buffers can become full" and that can lead to issues.

> it seems that enough needs to be read from the pipe buffer so that a
> process can finish writing what it needs to

If pipe streams aren't read (add "enough" or "sufficiently" here?)
before `os/proc-wait` finishes, then pipe buffers can become full, and
the process cannot finish because the process cannot print more on
pipe buffers which are already full. If the process cannot finish,
`os/proc-wait` cannot finish either.

## C Implementation

[`os_execute_impl` in os.c](https://github.com/janet-lang/janet/blob/431ecd3d1a4caabc66b62f63c2f83ece2f74e9f9/src/core/os.c#L1098-L1366):

```c
static Janet os_execute_impl(int32_t argc, Janet *argv, JanetExecuteMode mode) {
    janet_sandbox_assert(JANET_SANDBOX_SUBPROCESS);
    janet_arity(argc, 1, 3);

    /* Get flags */
    int is_spawn = mode == JANET_EXECUTE_SPAWN;
    uint64_t flags = 0;
    if (argc > 1) {
        flags = janet_getflags(argv, 1, "epxd");
    }

    /* Get environment */
    int use_environ = !janet_flag_at(flags, 0);
    EnvBlock envp = os_execute_env(argc, argv);

    /* Get arguments */
    JanetView exargs = janet_getindexed(argv, 0);
    if (exargs.len < 1) {
        janet_panic("expected at least 1 command line argument");
    }

    /* Optional stdio redirections */
    JanetAbstract orig_in = NULL, orig_out = NULL, orig_err = NULL;
    JanetHandle new_in = JANET_HANDLE_NONE, new_out = JANET_HANDLE_NONE, new_err = JANET_HANDLE_NONE;
    JanetHandle pipe_in = JANET_HANDLE_NONE, pipe_out = JANET_HANDLE_NONE, pipe_err = JANET_HANDLE_NONE;
    int pipe_errflag = 0; /* Track errors setting up pipes */
    int pipe_owner_flags = (is_spawn && (flags & 0x8)) ? JANET_PROC_ALLOW_ZOMBIE : 0;

    /* Get optional redirections */
    if (argc > 2 && (mode != JANET_EXECUTE_EXEC)) {
        JanetDictView tab = janet_getdictionary(argv, 2);
        Janet maybe_stdin = janet_dictionary_get(tab.kvs, tab.cap, janet_ckeywordv("in"));
        Janet maybe_stdout = janet_dictionary_get(tab.kvs, tab.cap, janet_ckeywordv("out"));
        Janet maybe_stderr = janet_dictionary_get(tab.kvs, tab.cap, janet_ckeywordv("err"));
        if (is_spawn && janet_keyeq(maybe_stdin, "pipe")) {
            new_in = make_pipes(&pipe_in, 1, &pipe_errflag);
            pipe_owner_flags |= JANET_PROC_OWNS_STDIN;
        } else if (!janet_checktype(maybe_stdin, JANET_NIL)) {
            new_in = janet_getjstream(&maybe_stdin, 0, &orig_in);
        }
        if (is_spawn && janet_keyeq(maybe_stdout, "pipe")) {
            new_out = make_pipes(&pipe_out, 0, &pipe_errflag);
            pipe_owner_flags |= JANET_PROC_OWNS_STDOUT;
        } else if (!janet_checktype(maybe_stdout, JANET_NIL)) {
            new_out = janet_getjstream(&maybe_stdout, 0, &orig_out);
        }
        if (is_spawn && janet_keyeq(maybe_stderr, "pipe")) {
            new_err = make_pipes(&pipe_err, 0, &pipe_errflag);
            pipe_owner_flags |= JANET_PROC_OWNS_STDERR;
        } else if (!janet_checktype(maybe_stderr, JANET_NIL)) {
            new_err = janet_getjstream(&maybe_stderr, 0, &orig_err);
        }
    }

    /* Clean up if any of the pipes have any issues */
    if (pipe_errflag) {
        if (pipe_in != JANET_HANDLE_NONE) close_handle(pipe_in);
        if (pipe_out != JANET_HANDLE_NONE) close_handle(pipe_out);
        if (pipe_err != JANET_HANDLE_NONE) close_handle(pipe_err);
        janet_panic("failed to create pipes");
    }

#ifdef JANET_WINDOWS

    HANDLE pHandle, tHandle;
    SECURITY_ATTRIBUTES saAttr;
    PROCESS_INFORMATION processInfo;
    STARTUPINFO startupInfo;
    memset(&saAttr, 0, sizeof(saAttr));
    memset(&processInfo, 0, sizeof(processInfo));
    memset(&startupInfo, 0, sizeof(startupInfo));
    startupInfo.cb = sizeof(startupInfo);
    startupInfo.dwFlags |= STARTF_USESTDHANDLES;
    saAttr.nLength = sizeof(saAttr);

    JanetBuffer *buf = os_exec_escape(exargs);
    if (buf->count > 8191) {
        if (pipe_in != JANET_HANDLE_NONE) CloseHandle(pipe_in);
        if (pipe_out != JANET_HANDLE_NONE) CloseHandle(pipe_out);
        if (pipe_err != JANET_HANDLE_NONE) CloseHandle(pipe_err);
        janet_panic("command line string too long (max 8191 characters)");
    }
    const char *path = (const char *) janet_unwrap_string(exargs.items[0]);

    /* Do IO redirection */

    if (pipe_in != JANET_HANDLE_NONE) {
        startupInfo.hStdInput = pipe_in;
    } else if (new_in != JANET_HANDLE_NONE) {
        startupInfo.hStdInput = new_in;
    } else {
        startupInfo.hStdInput = (HANDLE) _get_osfhandle(0);
    }

    if (pipe_out != JANET_HANDLE_NONE) {
        startupInfo.hStdOutput = pipe_out;
    } else if (new_out != JANET_HANDLE_NONE) {
        startupInfo.hStdOutput = new_out;
    } else {
        startupInfo.hStdOutput = (HANDLE) _get_osfhandle(1);
    }

    if (pipe_err != JANET_HANDLE_NONE) {
        startupInfo.hStdError = pipe_err;
    } else if (new_err != NULL) {
        startupInfo.hStdError = new_err;
    } else {
        startupInfo.hStdError = (HANDLE) _get_osfhandle(2);
    }

    int cp_failed = 0;
    if (!CreateProcess(janet_flag_at(flags, 1) ? NULL : path,
                       (char *) buf->data, /* Single CLI argument */
                       &saAttr, /* no proc inheritance */
                       &saAttr, /* no thread inheritance */
                       TRUE, /* handle inheritance */
                       0, /* flags */
                       use_environ ? NULL : envp, /* pass in environment */
                       NULL, /* use parents starting directory */
                       &startupInfo,
                       &processInfo)) {
        cp_failed = 1;
    }

    if (pipe_in != JANET_HANDLE_NONE) CloseHandle(pipe_in);
    if (pipe_out != JANET_HANDLE_NONE) CloseHandle(pipe_out);
    if (pipe_err != JANET_HANDLE_NONE) CloseHandle(pipe_err);

    os_execute_cleanup(envp, NULL);

    if (cp_failed)  {
        janet_panic("failed to create process");
    }

    pHandle = processInfo.hProcess;
    tHandle = processInfo.hThread;

#else

    /* Result */
    int status = 0;

    const char **child_argv = janet_smalloc(sizeof(char *) * ((size_t) exargs.len + 1));
    for (int32_t i = 0; i < exargs.len; i++)
        child_argv[i] = janet_getcstring(exargs.items, i);
    child_argv[exargs.len] = NULL;
    /* Coerce to form that works for spawn. I'm fairly confident no implementation
     * of posix_spawn would modify the argv array passed in. */
    char *const *cargv = (char *const *)child_argv;

    if (use_environ) {
        janet_lock_environ();
    }

    /* exec mode */
    if (mode == JANET_EXECUTE_EXEC) {
#ifdef JANET_WINDOWS
        janet_panic("not supported on windows");
#else
        int status;
        if (!use_environ) {
            environ = envp;
        }
        do {
            if (janet_flag_at(flags, 1)) {
                status = execvp(cargv[0], cargv);
            } else {
                status = execv(cargv[0], cargv);
            }
        } while (status == -1 && errno == EINTR);
        janet_panicf("%p: %s", cargv[0], strerror(errno ? errno : ENOENT));
#endif
    }

    /* Use posix_spawn to spawn new process */

    /* Posix spawn setup */
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    if (pipe_in != JANET_HANDLE_NONE) {
        posix_spawn_file_actions_adddup2(&actions, pipe_in, 0);
        posix_spawn_file_actions_addclose(&actions, pipe_in);
    } else if (new_in != JANET_HANDLE_NONE && new_in != 0) {
        posix_spawn_file_actions_adddup2(&actions, new_in, 0);
        if (new_in != new_out && new_in != new_err)
            posix_spawn_file_actions_addclose(&actions, new_in);
    }
    if (pipe_out != JANET_HANDLE_NONE) {
        posix_spawn_file_actions_adddup2(&actions, pipe_out, 1);
        posix_spawn_file_actions_addclose(&actions, pipe_out);
    } else if (new_out != JANET_HANDLE_NONE && new_out != 1) {
        posix_spawn_file_actions_adddup2(&actions, new_out, 1);
        if (new_out != new_err)
            posix_spawn_file_actions_addclose(&actions, new_out);
    }
    if (pipe_err != JANET_HANDLE_NONE) {
        posix_spawn_file_actions_adddup2(&actions, pipe_err, 2);
        posix_spawn_file_actions_addclose(&actions, pipe_err);
    } else if (new_err != JANET_HANDLE_NONE && new_err != 2) {
        posix_spawn_file_actions_adddup2(&actions, new_err, 2);
        posix_spawn_file_actions_addclose(&actions, new_err);
    }

    pid_t pid;
    if (janet_flag_at(flags, 1)) {
        status = posix_spawnp(&pid,
                              child_argv[0], &actions, NULL, cargv,
                              use_environ ? environ : envp);
    } else {
        status = posix_spawn(&pid,
                             child_argv[0], &actions, NULL, cargv,
                             use_environ ? environ : envp);
    }

    posix_spawn_file_actions_destroy(&actions);

    if (pipe_in != JANET_HANDLE_NONE) close(pipe_in);
    if (pipe_out != JANET_HANDLE_NONE) close(pipe_out);
    if (pipe_err != JANET_HANDLE_NONE) close(pipe_err);

    if (use_environ) {
        janet_unlock_environ();
    }

    os_execute_cleanup(envp, child_argv);
    if (status) {
        /* correct for macos bug where errno is not set */
        janet_panicf("%p: %s", argv[0], strerror(errno ? errno : ENOENT));
    }

#endif
    JanetProc *proc = janet_abstract(&ProcAT, sizeof(JanetProc));
    proc->return_code = -1;
#ifdef JANET_WINDOWS
    proc->pHandle = pHandle;
    proc->tHandle = tHandle;
#else
    proc->pid = pid;
#endif
    proc->in = NULL;
    proc->out = NULL;
    proc->err = NULL;
    proc->flags = pipe_owner_flags;
    if (janet_flag_at(flags, 2)) {
        proc->flags |= JANET_PROC_ERROR_NONZERO;
    }
    if (is_spawn) {
        /* Only set up pointers to stdin, stdout, and stderr if os/spawn. */
        if (new_in != JANET_HANDLE_NONE) {
            proc->in = get_stdio_for_handle(new_in, orig_in, 1);
            if (NULL == proc->in) janet_panic("failed to construct proc");
        }
        if (new_out != JANET_HANDLE_NONE) {
            proc->out = get_stdio_for_handle(new_out, orig_out, 0);
            if (NULL == proc->out) janet_panic("failed to construct proc");
        }
        if (new_err != JANET_HANDLE_NONE) {
            proc->err = get_stdio_for_handle(new_err, orig_err, 0);
            if (NULL == proc->err) janet_panic("failed to construct proc");
        }
        return janet_wrap_abstract(proc);
    } else {
#ifdef JANET_EV
        os_proc_wait_impl(proc);
#else
        return os_proc_wait_impl(proc);
#endif
    }
}
```