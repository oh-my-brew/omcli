/*
 * omcli-lockscreen: lock the macOS screen and report whether that worked.
 *
 * The lock primitive lives in Apple's private login framework, so it is
 * resolved at runtime with dlopen/dlsym instead of being linked directly. A
 * renamed or removed symbol degrades into a reported failure with a fallback
 * rather than a crash or a silent no-op.
 *
 * The result is read back from the IORegistry (IOConsoleLocked), which is the
 * flag macOS sets for any lock, including manual and idle locks. It stays
 * readable from a non-GUI session, so a lock request that does nothing - the
 * usual outcome over SSH - is reported as a failure instead of a success.
 */

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <errno.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

#define OMCLI_CONFIRM_TIMEOUT_MS 3000
#define OMCLI_POLL_INTERVAL_US 50000

enum {
    EXIT_LOCKED = 0,
    EXIT_NOT_LOCKED = 1,
    EXIT_USAGE = 2,
    EXIT_UNAVAILABLE = 3,
};

enum lock_state {
    LOCK_STATE_UNKNOWN = -1,
    LOCK_STATE_UNLOCKED = 0,
    LOCK_STATE_LOCKED = 1,
};

static const char *const omcli_lock_frameworks[] = {
    "/System/Library/PrivateFrameworks/login.framework/Versions/A/login",
    "/System/Library/PrivateFrameworks/login.framework/login",
    "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login",
};

static void omcli_usage(FILE *stream)
{
    fprintf(stream, "Usage: omcli-lockscreen [command]\n"
                    "\n"
                    "Commands:\n"
                    "  lock      Lock the screen and confirm the lock took effect (default)\n"
                    "  status    Report whether the screen is currently locked\n"
                    "  help      Show this help\n"
                    "\n"
                    "Exit status:\n"
                    "  0  the screen is locked\n"
                    "  1  the screen is not locked\n"
                    "  2  usage error\n"
                    "  3  the lock state or the lock mechanism is unavailable\n");
}

static enum lock_state omcli_read_lock_state(void)
{
    io_registry_entry_t root = IORegistryGetRootEntry(kIOMainPortDefault);
    if (root == MACH_PORT_NULL) {
        return LOCK_STATE_UNKNOWN;
    }

    CFTypeRef value = IORegistryEntryCreateCFProperty(
        root, CFSTR("IOConsoleLocked"), kCFAllocatorDefault, 0);
    IOObjectRelease(root);

    if (value == NULL) {
        return LOCK_STATE_UNKNOWN;
    }

    enum lock_state state = LOCK_STATE_UNKNOWN;
    if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
        state = CFBooleanGetValue((CFBooleanRef)value) ? LOCK_STATE_LOCKED
                                                       : LOCK_STATE_UNLOCKED;
    } else if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        int flag = 0;
        if (CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &flag)) {
            state = flag ? LOCK_STATE_LOCKED : LOCK_STATE_UNLOCKED;
        }
    }

    CFRelease(value);
    return state;
}

/* Returns 1 when the private lock symbol was called, 0 when it is unavailable. */
static int omcli_lock_via_login_framework(void)
{
    for (size_t i = 0; i < sizeof omcli_lock_frameworks / sizeof omcli_lock_frameworks[0]; i++) {
        void *handle = dlopen(omcli_lock_frameworks[i], RTLD_LAZY | RTLD_LOCAL);
        if (handle == NULL) {
            continue;
        }

        void (*lock_screen)(void) = (void (*)(void))dlsym(handle, "SACLockScreenImmediate");
        if (lock_screen == NULL) {
            dlclose(handle);
            continue;
        }

        lock_screen();
        return 1;
    }

    return 0;
}

/* Public fallback: sleeping the display locks the session when the user
 * requires a password immediately after sleep or screen saver. */
static int omcli_lock_via_display_sleep(void)
{
    pid_t pid = 0;
    char *const argv[] = { (char *)"pmset", (char *)"displaysleepnow", NULL };

    if (posix_spawn(&pid, "/usr/bin/pmset", NULL, NULL, argv, environ) != 0) {
        return -1;
    }

    int status = 0;
    pid_t waited = 0;
    do {
        waited = waitpid(pid, &status, 0);
    } while (waited == -1 && errno == EINTR);

    if (waited == -1) {
        return -1;
    }

    return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : -1;
}

/* Returns 1 when the screen locked, 0 when it stayed unlocked, and -1 when the
 * lock state could not be read at all. */
static int omcli_wait_for_lock(void)
{
    int elapsed = 0;
    enum lock_state state = LOCK_STATE_UNKNOWN;

    while (elapsed <= OMCLI_CONFIRM_TIMEOUT_MS) {
        state = omcli_read_lock_state();
        if (state == LOCK_STATE_LOCKED) {
            return 1;
        }
        usleep(OMCLI_POLL_INTERVAL_US);
        elapsed += OMCLI_POLL_INTERVAL_US / 1000;
    }

    return state == LOCK_STATE_UNKNOWN ? -1 : 0;
}

static int omcli_status(void)
{
    switch (omcli_read_lock_state()) {
    case LOCK_STATE_LOCKED:
        printf("locked\n");
        return EXIT_LOCKED;
    case LOCK_STATE_UNLOCKED:
        printf("unlocked\n");
        return EXIT_NOT_LOCKED;
    default:
        fprintf(stderr, "omcli lockscreen: cannot read the console lock state\n");
        return EXIT_UNAVAILABLE;
    }
}

static int omcli_lock(void)
{
    if (omcli_read_lock_state() == LOCK_STATE_LOCKED) {
        printf("screen is already locked\n");
        return EXIT_LOCKED;
    }

    const char *mechanism = NULL;
    const char *failure_hint = NULL;

    if (omcli_lock_via_login_framework()) {
        mechanism = "the login framework lock request";
        failure_hint = "run it from a terminal in the logged-in GUI session; "
                       "a lock started outside that session cannot reach the console";
    } else if (omcli_lock_via_display_sleep() == 0) {
        mechanism = "display sleep";
        failure_hint = "enable \"Require password immediately after sleep or screen saver begins\" "
                       "in Lock Screen settings";
    } else {
        fprintf(stderr, "omcli lockscreen: no usable lock mechanism: the private login "
                        "framework exposes no SACLockScreenImmediate and /usr/bin/pmset "
                        "could not sleep the display\n");
        return EXIT_UNAVAILABLE;
    }

    int confirmed = omcli_wait_for_lock();
    if (confirmed == 1) {
        printf("screen locked\n");
        return EXIT_LOCKED;
    }

    if (confirmed < 0) {
        fprintf(stderr, "omcli lockscreen: %s was sent, but this session cannot read the "
                        "console lock state, so the lock could not be confirmed\n",
                mechanism);
        return EXIT_UNAVAILABLE;
    }

    fprintf(stderr, "omcli lockscreen: %s returned but the screen did not lock within %dms; "
                    "to fix, %s\n",
            mechanism, OMCLI_CONFIRM_TIMEOUT_MS, failure_hint);
    return EXIT_NOT_LOCKED;
}

int main(int argc, char **argv)
{
    const char *command = argc > 1 ? argv[1] : "lock";

    if (argc > 2) {
        fprintf(stderr, "omcli lockscreen: %s does not accept arguments\n", command);
        omcli_usage(stderr);
        return EXIT_USAGE;
    }

    if (strcmp(command, "lock") == 0) {
        return omcli_lock();
    }
    if (strcmp(command, "status") == 0) {
        return omcli_status();
    }
    if (strcmp(command, "help") == 0 || strcmp(command, "-h") == 0 ||
        strcmp(command, "--help") == 0) {
        omcli_usage(stdout);
        return EXIT_LOCKED;
    }

    fprintf(stderr, "omcli lockscreen: unknown command: %s\n", command);
    omcli_usage(stderr);
    return EXIT_USAGE;
}
