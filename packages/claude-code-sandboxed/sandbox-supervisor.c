/*
 * sandbox-supervisor: a minimal process supervisor for sandbox-exec wrappers.
 *
 * The shell-based alternative (background + wait + traps) has unavoidable
 * races: a child that exits at the same instant as a forwarded signal can
 * corrupt the reported status, and a signal received between launching the
 * child and recording its PID is silently dropped. This supervisor does the
 * work with explicit signal masking + waitpid(2)/EINTR handling:
 *
 *   - HUP/INT/TERM are BLOCKED before installing handlers and fork(), so a
 *     termination signal arriving during startup is held as pending and
 *     delivered after the parent records the child PID (never dropped).
 *   - The parent forwards HUP/INT/TERM to the supervised child.
 *   - The child restores the caller's signal mask and default dispositions
 *     before execvp(), so the sandboxed agent sees normal signal semantics.
 *   - The parent waits with waitpid(2), handling EINTR, and returns the
 *     child's real exit status (re-raising the terminating signal on signal
 *     death).
 *   - After the child is reaped, child_pid is cleared while signals are
 *     blocked, so a late signal cannot kill a recycled PID.
 *   - A cleanup directory (the wrapper's per-invocation temp dir) is removed
 *     only after the child has exited, so a signal sent to the wrapper never
 *     removes the temp dir while the agent is still running.
 *
 * The child is the `sandbox-exec` binary, which replaces itself (exec) with
 * the agent process; the supervisor therefore supervises the agent directly.
 *
 * Usage: sandbox-supervisor [--cleanup DIR] -- COMMAND [ARGS...]
 */
#include <errno.h>
#include <ftw.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static volatile sig_atomic_t child_pid = -1;

static void forward_signal(int sig) {
  /* Async-signal-safe: forwards termination signals to the supervised child.
   * Signals arriving before fork() (or after reap) see child_pid <= 0 and are
   * no-ops; during startup they are held blocked and delivered only after the
   * PID is recorded. */
  if (child_pid > 0) {
    kill((pid_t)child_pid, sig);
  }
}

/* Block SIGHUP/SIGINT/SIGTERM, capturing the previous mask for later restore. */
static int block_term_signals(sigset_t *oldset) {
  sigset_t set;
  sigemptyset(&set);
  sigaddset(&set, SIGHUP);
  sigaddset(&set, SIGINT);
  sigaddset(&set, SIGTERM);
  return sigprocmask(SIG_SETMASK, &set, oldset);
}

static int restore_signal_mask(const sigset_t *set) {
  return sigprocmask(SIG_SETMASK, set, NULL);
}

static int install_forwarders(void) {
  struct sigaction act;
  memset(&act, 0, sizeof(act));
  act.sa_handler = forward_signal;
  if (sigaction(SIGHUP, &act, NULL) != 0 ||
      sigaction(SIGINT, &act, NULL) != 0 ||
      sigaction(SIGTERM, &act, NULL) != 0) {
    return -1;
  }
  return 0;
}

static void restore_default_dispositions(void) {
  struct sigaction def;
  memset(&def, 0, sizeof(def));
  def.sa_handler = SIG_DFL;
  (void)sigaction(SIGHUP, &def, NULL);
  (void)sigaction(SIGINT, &def, NULL);
  (void)sigaction(SIGTERM, &def, NULL);
}

static int remove_entry(const char *path, const struct stat *st, int type,
                        struct FTW *ftw) {
  (void)st;
  (void)ftw;
  if (type == FTW_DP) {
    return rmdir(path);
  }
  return unlink(path);
}

static int remove_tree(const char *path) {
  return nftw(path, remove_entry, 16, FTW_DEPTH | FTW_PHYS);
}

/* The wrapper always passes its own private mktemp dir; still refuse anything
 * that is not an absolute path or that could reach the filesystem root. */
static int validate_cleanup_path(const char *path) {
  return path != NULL && path[0] == '/' && strcmp(path, "/") != 0 &&
         strcmp(path, "/private") != 0 && strcmp(path, "/private/tmp") != 0;
}

int main(int argc, char **argv) {
  const char *cleanup_dir = NULL;
  int i = 1;

  if (argc >= 3 && strcmp(argv[1], "--cleanup") == 0) {
    cleanup_dir = argv[2];
    i = 3;
  }
  if (i >= argc || strcmp(argv[i], "--") != 0) {
    fprintf(stderr, "usage: sandbox-supervisor [--cleanup DIR] -- COMMAND [ARGS...]\n");
    return 2;
  }
  char **cmd = &argv[i + 1];
  if (cmd == NULL || cmd[0] == NULL) {
    fprintf(stderr, "sandbox-supervisor: no command\n");
    return 2;
  }
  if (cleanup_dir != NULL && !validate_cleanup_path(cleanup_dir)) {
    fprintf(stderr, "sandbox-supervisor: refusing unsafe cleanup path: %s\n",
            cleanup_dir);
    return 2;
  }

  sigset_t orig_mask;
  if (block_term_signals(&orig_mask) != 0) {
    perror("sigprocmask");
    return 1;
  }
  if (install_forwarders() != 0) {
    perror("sigaction");
    (void)restore_signal_mask(&orig_mask);
    return 1;
  }

  child_pid = fork();
  if (child_pid < 0) {
    perror("fork");
    (void)restore_signal_mask(&orig_mask);
    if (cleanup_dir != NULL &&
        remove_tree(cleanup_dir) != 0) {
      fprintf(stderr, "sandbox-supervisor: warning: failed to remove %s\n",
              cleanup_dir);
    }
    return 1;
  }
  if (child_pid == 0) {
    /* Child: hand the process back to the caller's signal environment, then
     * exec the command (sandbox-exec), which execs the agent binary. */
    child_pid = -1;
    restore_default_dispositions();
    (void)restore_signal_mask(&orig_mask);
    execvp(cmd[0], cmd);
    perror("execvp");
    _exit(127);
  }

  /* Parent: resume normal signal delivery; pending startup signals (which
   * arrived while blocked) are now delivered and forwarded to the child. */
  if (restore_signal_mask(&orig_mask) != 0) {
    perror("sigprocmask");
    /* Fail closed but keep waiting so the child is not orphaned. */
  }

  int status = 0;
  int wait_error = 0;
  for (;;) {
    pid_t r = waitpid((pid_t)child_pid, &status, 0);
    if (r < 0 && errno == EINTR) {
      continue;
    }
    if (r < 0) {
      perror("waitpid");
      wait_error = 1;
    }
    break;
  }

  /* Reap done. Clear the child PID while termination signals are blocked so a
   * late signal cannot kill a recycled PID, then remove the temp dir. */
  sigset_t reap_mask;
  (void)block_term_signals(&reap_mask);
  child_pid = -1;

  if (cleanup_dir != NULL && remove_tree(cleanup_dir) != 0) {
    fprintf(stderr, "sandbox-supervisor: warning: failed to remove %s\n",
            cleanup_dir);
  }

  if (wait_error) {
    return 1;
  }
  if (WIFEXITED(status)) {
    return WEXITSTATUS(status);
  }
  if (WIFSIGNALED(status)) {
    int sig = WTERMSIG(status);
    /* Re-raise with the default disposition so the caller observes normal
     * signal death; unblock first so the raise can be delivered. */
    (void)restore_default_dispositions();
    (void)restore_signal_mask(&reap_mask);
    raise(sig);
    return 128 + sig;
  }
  return 1;
}