/* Native lock-screen primitives used by the omcli shell orchestrator. */

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

enum {
    EXIT_OK = 0,
    EXIT_FALSE = 1,
    EXIT_USAGE = 2,
    EXIT_UNAVAILABLE = 3,
};

enum lock_state {
    LOCK_STATE_UNKNOWN = -1,
    LOCK_STATE_UNLOCKED = 0,
    LOCK_STATE_LOCKED = 1,
};

static const char *const login_framework_paths[] = {
    "/System/Library/PrivateFrameworks/login.framework/Versions/A/login",
    "/System/Library/PrivateFrameworks/login.framework/login",
    "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login",
};

static void usage(FILE *stream)
{
    fprintf(stream, "Usage: omcli-lockscreen <command>\n"
                    "\n"
                    "Commands:\n"
                    "  status        Print locked or unlocked\n"
                    "  direct        Request a lock through the private login framework\n"
                    "  hotkey        Post the Control-Command-Q lock shortcut\n"
                    "  capabilities  Print native mechanism availability\n"
                    "  help          Show this help\n");
}

static enum lock_state read_lock_state(void)
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

static void *open_login_framework(void)
{
    for (size_t index = 0;
         index < sizeof login_framework_paths / sizeof login_framework_paths[0];
         index++) {
        void *handle = dlopen(login_framework_paths[index], RTLD_LAZY | RTLD_LOCAL);
        if (handle != NULL) {
            return handle;
        }
    }
    return NULL;
}

static int direct_available(void)
{
    void *handle = open_login_framework();
    if (handle == NULL) {
        return 0;
    }
    int available = dlsym(handle, "SACLockScreenImmediate") != NULL;
    dlclose(handle);
    return available;
}

static int status_command(void)
{
    switch (read_lock_state()) {
    case LOCK_STATE_LOCKED:
        puts("locked");
        return EXIT_OK;
    case LOCK_STATE_UNLOCKED:
        puts("unlocked");
        return EXIT_FALSE;
    default:
        fprintf(stderr, "omcli lockscreen: cannot read the console lock state\n");
        return EXIT_UNAVAILABLE;
    }
}

static int direct_command(void)
{
    void *handle = open_login_framework();
    if (handle == NULL) {
        fprintf(stderr, "omcli lockscreen: the private login framework is unavailable\n");
        return EXIT_UNAVAILABLE;
    }

    void (*lock_screen)(void) =
        (void (*)(void))dlsym(handle, "SACLockScreenImmediate");
    if (lock_screen == NULL) {
        fprintf(stderr, "omcli lockscreen: SACLockScreenImmediate is unavailable\n");
        dlclose(handle);
        return EXIT_UNAVAILABLE;
    }

    lock_screen();
    dlclose(handle);
    return EXIT_OK;
}

static int hotkey_command(void)
{
    if (!AXIsProcessTrusted()) {
        fprintf(stderr, "omcli lockscreen: hotkey requires Accessibility permission "
                        "for omcli-lockscreen\n");
        return EXIT_UNAVAILABLE;
    }

    /* ANSI Q is virtual key code 12 on macOS. */
    CGEventRef key_down = CGEventCreateKeyboardEvent(NULL, 12, true);
    CGEventRef key_up = CGEventCreateKeyboardEvent(NULL, 12, false);
    if (key_down == NULL || key_up == NULL) {
        if (key_down != NULL) {
            CFRelease(key_down);
        }
        if (key_up != NULL) {
            CFRelease(key_up);
        }
        fprintf(stderr, "omcli lockscreen: cannot create the lock-screen hotkey events\n");
        return EXIT_UNAVAILABLE;
    }

    CGEventFlags flags = kCGEventFlagMaskControl | kCGEventFlagMaskCommand;
    CGEventSetFlags(key_down, flags);
    CGEventSetFlags(key_up, flags);
    CGEventPost(kCGHIDEventTap, key_down);
    usleep(20000);
    CGEventPost(kCGHIDEventTap, key_up);

    CFRelease(key_down);
    CFRelease(key_up);
    return EXIT_OK;
}

static int capabilities_command(void)
{
    printf("direct.symbol=%s\n", direct_available() ? "available" : "unavailable");
    printf("hotkey.accessibility=%s\n",
           AXIsProcessTrusted() ? "authorized" : "unauthorized");
    return EXIT_OK;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        usage(stderr);
        return EXIT_USAGE;
    }

    if (strcmp(argv[1], "status") == 0) {
        return status_command();
    }
    if (strcmp(argv[1], "direct") == 0) {
        return direct_command();
    }
    if (strcmp(argv[1], "hotkey") == 0) {
        return hotkey_command();
    }
    if (strcmp(argv[1], "capabilities") == 0) {
        return capabilities_command();
    }
    if (strcmp(argv[1], "help") == 0 || strcmp(argv[1], "-h") == 0 ||
        strcmp(argv[1], "--help") == 0) {
        usage(stdout);
        return EXIT_OK;
    }

    fprintf(stderr, "omcli lockscreen: unknown helper command: %s\n", argv[1]);
    usage(stderr);
    return EXIT_USAGE;
}
