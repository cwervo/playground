# folk-convivial Crash Diagnosis Report

## Summary
The `folk` process on `folk-convivial` crashed with a `SIGSEGV` (Segmentation Fault) due to an unhandled edge-case in multithreaded signal handling. 

Specifically, a `SIGUSR1` (Signal 10) was delivered to a pure C background thread (`sysmon`), which then invoked the JimTcl interpreter's global signal handler. Because the background thread is not a JimTcl thread, the signal handler attempted to dereference an uninitialized/thread-local variable (`sigloc`), leading to a segmentation fault.

## Detailed Analysis

1. **The Crash Location**:
   The crash occurred in Thread 207228 (the `sysmon` thread). At the time of the crash, the thread was reading `/proc/<tid>/stat` using `fscanf` inside `__vfscanf_internal`. 

2. **The Trigger**:
   While the `sysmon` thread was inside `fscanf`, the process received a `SIGUSR1` (Signal 10). In POSIX systems, if a signal is sent to the process and isn't targeted at a specific thread, the kernel will deliver it to *any* thread that does not have that signal masked. The kernel chose the `sysmon` thread.

3. **The Signal Handler Fault**:
   The installed signal handler for `SIGUSR1` is `signal_handler` from `jim-signal.c`. 
   Looking at the GDB backtrace for the crashing thread:
   ```c
   #0  0x00005e0024c993f7 in signal_handler (sig=10) at jim-signal.c:44
   #1  <signal handler called>
   #2  0x000079c3ab71ba9a in __GI___libc_read (nbytes=1024, buf=0x79c3785c3910, fd=258)
   ```
   At line 44 of `jim-signal.c`, the code does:
   ```c
   *sigloc |= sig_to_bit(sig);
   ```
   Because `sysmon` is a background C thread and not an initialized JimTcl worker thread, the `sigloc` pointer is likely uninitialized (or thread-local and NULL). Dereferencing it to record the signal bitmask triggered a `SIGSEGV` (Signal 11), bringing down the entire process.

4. **Secondary Observation in `sysmon.c`**:
   While reviewing `sysmon.c`, we also noticed an unsafe format string is used during parsing:
   `fscanf(fp, "%d %s %c ", &_pid, _name, &state)`
   The `%s` specifier without a length limit writes into `char _name[100]`. Because the second field of `/proc/[pid]/stat` is the process name enclosed in parentheses, and can occasionally contain spaces, this parsing is brittle. If a name has spaces, it breaks the scan offset, and if it exceeds 99 characters, it would cause a stack buffer overflow. While this was not the cause of *this* crash, it should be fixed.

## Recommended Fix

1. **Mask Signals in Background C Threads**:
   To prevent JimTcl signal handlers from running in non-Tcl threads, background C threads (like `sysmon`) should explicitly block all signals upon startup.
   ```c
   sigset_t set;
   sigfillset(&set);
   pthread_sigmask(SIG_BLOCK, &set, NULL);
   ```
   This ensures signals are correctly routed only to the main thread or worker threads that have initialized JimTcl environments and can safely process them.

2. **Fix `fscanf` parsing in `sysmon`**:
   Update `fscanf(fp, "%d %s %c ", ...)` to safely parse the name, which can contain spaces and parentheses (e.g., using a regex or reading character by character until the closing parenthesis).

## Extracted Artifacts
- The core dump has been successfully saved to: `~/code/playground/folk/diagnoses/core.folk`
- The full interactive GDB backtrace report has been saved to: `~/code/playground/folk/diagnoses/gdb_report.txt`
