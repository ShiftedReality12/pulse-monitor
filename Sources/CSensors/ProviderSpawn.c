#include "include/PulseDisk.h"
#include <spawn.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <crt_externs.h>
#include <errno.h>

int pulse_spawn_group(const char *path, char *const argv[], int *read_fd) {
    int pipefd[2];
    if (pipe(pipefd) != 0) return -errno;
    fcntl(pipefd[0], F_SETFD, FD_CLOEXEC); fcntl(pipefd[1], F_SETFD, FD_CLOEXEC);
    posix_spawn_file_actions_t actions; posix_spawnattr_t attributes;
    posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);
    posix_spawn_file_actions_addclose(&actions, pipefd[1]);
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup(&attributes, 0);
    pid_t pid;
    int error = posix_spawn(&pid, path, &actions, &attributes, argv, *_NSGetEnviron());
    posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes);
    close(pipefd[1]);
    if (error) { close(pipefd[0]); return -error; }
    *read_fd = pipefd[0]; return pid;
}
int pulse_process_succeeded(int status) { return WIFEXITED(status) && WEXITSTATUS(status) == 0; }
