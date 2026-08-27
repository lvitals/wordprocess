/* Test-only helper: drives one child process attached to a real
 * pseudo-terminal, following a line-oriented command script read from
 * stdin, and reports one result line per command on stdout.
 *
 * This exists purely so the Lua tests under tests/frontend can exercise
 * the ncurses frontend (resize, key input, clean exit) the same way a
 * real terminal
 * would -- something no amount of mocking wg.getscreensize() can reach,
 * since that boundary sits entirely below the Lua/wg layer. The actual
 * pass/fail assertions belong in the Lua test, in the same idiom as the
 * rest of tests/; this tool only performs the raw OS-level mechanics
 * (openpty, fork/exec, ioctl, poll) that Lua has no access to.
 *
 * Commands (one per line, space-separated, results as "<NAME> <...>\n"):
 *   SETENV <key> <value>              -- applies before the next SPAWN
 *   SPAWN <binary> <home> <rows> <cols> <term>
 *   SEND_HEX <hex>                    -- write raw bytes to the pty
 *   RESIZE <rows> <cols>               -- ioctl(TIOCSWINSZ) + SIGWINCH
 *   DRAIN <ms>                         -- collect output for up to <ms>
 *   ALIVE                              -- 1 if the child is still running
 *   WAIT_EXIT <ms>                     -- 1 if the child exits within <ms>
 *   KILL                               -- SIGKILL the child if still alive
 *
 * Not installed; not linked into wp/xwp. Built only for `meson test`.
 */

#define _GNU_SOURCE

#include <pty.h>
#include <utmp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <poll.h>
#include <unistd.h>

static pid_t child_pid = -1;
static int master_fd = -1;

static void hex_encode(const unsigned char* data, size_t len, FILE* out)
{
    static const char digits[] = "0123456789abcdef";
    for (size_t i = 0; i < len; i++)
    {
        putc(digits[data[i] >> 4], out);
        putc(digits[data[i] & 0xf], out);
    }
}

static int hex_nibble(char c)
{
    if ((c >= '0') && (c <= '9'))
        return c - '0';
    if ((c >= 'a') && (c <= 'f'))
        return c - 'a' + 10;
    if ((c >= 'A') && (c <= 'F'))
        return c - 'A' + 10;
    return -1;
}

/* Decodes in place; returns the decoded length. */
static size_t hex_decode(char* s)
{
    size_t out = 0;
    for (size_t i = 0; s[i] && s[i + 1]; i += 2)
    {
        int hi = hex_nibble(s[i]);
        int lo = hex_nibble(s[i + 1]);
        if ((hi < 0) || (lo < 0))
            break;
        ((unsigned char*)s)[out++] = (unsigned char)((hi << 4) | lo);
    }
    return out;
}

static int child_alive(void)
{
    if (child_pid <= 0)
        return 0;
    int status;
    pid_t r = waitpid(child_pid, &status, WNOHANG);
    if (r == 0)
        return 1;
    /* r == child_pid (exited/signalled) or r == -1 (already reaped/gone) */
    child_pid = -1;
    return 0;
}

static void cmd_spawn(char* binary, char* home, int rows, int cols, char* term)
{
    setenv("HOME", home, 1);
    setenv("TERM", term, 1);

    struct winsize ws = {0};
    ws.ws_row = (unsigned short)rows;
    ws.ws_col = (unsigned short)cols;

    int master, slave;
    if (openpty(&master, &slave, NULL, NULL, &ws) != 0)
    {
        printf("SPAWN 0\n");
        return;
    }

    pid_t pid = fork();
    if (pid == 0)
    {
        close(master);
        if (login_tty(slave) != 0)
            _exit(126);
        execl(binary, binary, (char*)NULL);
        _exit(127);
    }

    close(slave);
    if (pid < 0)
    {
        close(master);
        printf("SPAWN 0\n");
        return;
    }

    master_fd = master;
    child_pid = pid;
    printf("SPAWN 1\n");
}

static void cmd_send_hex(char* hex)
{
    size_t len = hex_decode(hex);
    if (master_fd >= 0 && len > 0)
    {
        ssize_t written = write(master_fd, hex, len);
        (void)written; /* best-effort; DRAIN/ALIVE afterwards report the outcome */
    }
    printf("SEND_HEX 1\n");
}

static void cmd_resize(int rows, int cols)
{
    if (master_fd >= 0)
    {
        struct winsize ws = {0};
        ws.ws_row = (unsigned short)rows;
        ws.ws_col = (unsigned short)cols;
        ioctl(master_fd, TIOCSWINSZ, &ws);
    }
    if (child_pid > 0)
        kill(child_pid, SIGWINCH);
    printf("RESIZE 1\n");
}

static void cmd_drain(int ms)
{
    unsigned char buf[65536];
    unsigned char* accum = NULL;
    size_t accum_len = 0;

    struct timespec deadline;
    clock_gettime(CLOCK_MONOTONIC, &deadline);
    deadline.tv_sec += ms / 1000;
    deadline.tv_nsec += (long)(ms % 1000) * 1000000L;
    if (deadline.tv_nsec >= 1000000000L)
    {
        deadline.tv_sec += 1;
        deadline.tv_nsec -= 1000000000L;
    }

    for (;;)
    {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        long remaining_ms = (long)(deadline.tv_sec - now.tv_sec) * 1000 +
            (deadline.tv_nsec - now.tv_nsec) / 1000000;
        if (remaining_ms <= 0 || master_fd < 0)
            break;

        struct pollfd pfd = {.fd = master_fd, .events = POLLIN};
        int r = poll(&pfd, 1, (int)remaining_ms);
        if (r <= 0)
            break;
        if (!(pfd.revents & POLLIN))
            break;

        ssize_t n = read(master_fd, buf, sizeof(buf));
        if (n <= 0)
            break;

        unsigned char* grown = realloc(accum, accum_len + (size_t)n);
        if (!grown)
            break;
        accum = grown;
        memcpy(accum + accum_len, buf, (size_t)n);
        accum_len += (size_t)n;
    }

    printf("DATA ");
    hex_encode(accum, accum_len, stdout);
    printf("\n");
    free(accum);
}

static void cmd_alive(void)
{
    printf("ALIVE %d\n", child_alive());
}

static void cmd_wait_exit(int ms)
{
    struct timespec deadline;
    clock_gettime(CLOCK_MONOTONIC, &deadline);
    deadline.tv_sec += ms / 1000;
    deadline.tv_nsec += (long)(ms % 1000) * 1000000L;
    if (deadline.tv_nsec >= 1000000000L)
    {
        deadline.tv_sec += 1;
        deadline.tv_nsec -= 1000000000L;
    }

    for (;;)
    {
        if (!child_alive())
        {
            printf("WAIT_EXIT 1\n");
            return;
        }
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        long remaining_ms = (long)(deadline.tv_sec - now.tv_sec) * 1000 +
            (deadline.tv_nsec - now.tv_nsec) / 1000000;
        if (remaining_ms <= 0)
        {
            printf("WAIT_EXIT 0\n");
            return;
        }
        struct timespec sleepfor = {0, 20000000L}; /* 20ms */
        nanosleep(&sleepfor, NULL);
    }
}

static void cmd_kill(void)
{
    if (child_alive())
    {
        kill(child_pid, SIGKILL);
        waitpid(child_pid, NULL, 0);
        child_pid = -1;
    }
    printf("KILL 1\n");
}

int main(void)
{
    char* line = NULL;
    size_t linecap = 0;

    while (getline(&line, &linecap, stdin) > 0)
    {
        char* verb = strtok(line, " \t\r\n");
        if (!verb)
            continue;

        if (strcmp(verb, "SETENV") == 0)
        {
            char* key = strtok(NULL, " \t\r\n");
            char* value = strtok(NULL, "\r\n");
            if (key && value)
                setenv(key, value, 1);
            printf("SETENV 1\n");
        }
        else if (strcmp(verb, "SPAWN") == 0)
        {
            char* binary = strtok(NULL, " \t\r\n");
            char* home = strtok(NULL, " \t\r\n");
            char* rows_s = strtok(NULL, " \t\r\n");
            char* cols_s = strtok(NULL, " \t\r\n");
            char* term = strtok(NULL, " \t\r\n");
            if (binary && home && rows_s && cols_s && term)
                cmd_spawn(binary, home, atoi(rows_s), atoi(cols_s), term);
            else
                printf("SPAWN 0\n");
        }
        else if (strcmp(verb, "SEND_HEX") == 0)
        {
            char* hex = strtok(NULL, " \t\r\n");
            cmd_send_hex(hex ? hex : "");
        }
        else if (strcmp(verb, "RESIZE") == 0)
        {
            char* rows_s = strtok(NULL, " \t\r\n");
            char* cols_s = strtok(NULL, " \t\r\n");
            cmd_resize(rows_s ? atoi(rows_s) : 24, cols_s ? atoi(cols_s) : 80);
        }
        else if (strcmp(verb, "DRAIN") == 0)
        {
            char* ms_s = strtok(NULL, " \t\r\n");
            cmd_drain(ms_s ? atoi(ms_s) : 500);
        }
        else if (strcmp(verb, "ALIVE") == 0)
        {
            cmd_alive();
        }
        else if (strcmp(verb, "WAIT_EXIT") == 0)
        {
            char* ms_s = strtok(NULL, " \t\r\n");
            cmd_wait_exit(ms_s ? atoi(ms_s) : 5000);
        }
        else if (strcmp(verb, "KILL") == 0)
        {
            cmd_kill();
        }
        else
        {
            printf("ERROR unknown command\n");
        }
        fflush(stdout);
    }

    free(line);

    if (child_alive())
    {
        kill(child_pid, SIGKILL);
        waitpid(child_pid, NULL, 0);
    }
    if (master_fd >= 0)
        close(master_fd);

    return 0;
}
