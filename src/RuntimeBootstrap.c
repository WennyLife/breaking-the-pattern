#include <unistd.h>
#include <signal.h>
#include <stdlib.h>
#include <stdio.h>
#include <sys/wait.h>
#include <errno.h>
// Isolate the Wine/Rosetta process from the GUI launcher's session and signals.
int main(int argc, char **argv) {
    if (argc < 3) return 64;
    pid_t pid = fork();
    if (pid < 0) { perror("fork runtime"); return 71; }
    if (pid > 0) {
        FILE *f = fopen(argv[1], "w"); if (f) { fprintf(f, "%d\n", pid); fclose(f); }
        int status; while (waitpid(pid, &status, 0) < 0) { if (errno != EINTR) return 71; }
        return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    }
    sigset_t empty; sigemptyset(&empty); sigprocmask(SIG_SETMASK, &empty, NULL);
    for (int n=1; n<NSIG; n++) if (n != SIGKILL && n != SIGSTOP) signal(n, SIG_DFL);
    setsid(); unsetenv("__CFBundleIdentifier");
    execv(argv[2], argv + 2); perror("exec runtime"); return 71;
}
