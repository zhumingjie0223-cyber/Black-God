// Exercise the production kernel/uname.c with controlled host uname responses.
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/utsname.h>
#include "kernel/calls.h"
#include "platform/platform.h"

extern const char *uname_hostname_override;
static char host_name[sizeof(((struct utsname *)0)->nodename)];
static int host_uname_error;
static int host_uname_calls;

// Replace only the host OS call; do_uname and its guest layout remain real.
int uname(struct utsname *value) {
    host_uname_calls++;
    if (host_uname_error) {
        // Failed system calls may leave unusable or partially written data.
        memset(value, 0xa5, sizeof(*value));
        return -1;
    }
    memset(value, 0, sizeof(*value));
    memcpy(value->nodename, host_name, sizeof(host_name));
    return 0;
}

// Unused syscall dependencies, so this test needs no guest image or process.
int user_read(addr_t addr, void *buf, size_t count) {
    (void)addr; (void)buf; (void)count;
    return _EFAULT;
}
int user_write(addr_t addr, const void *buf, size_t count) {
    (void)addr; (void)buf; (void)count;
    return _EFAULT;
}
struct uptime_info get_uptime(void) { return (struct uptime_info){0}; }
_Atomic long anon_page_count;

static void check(const char *label, const char *expected, size_t expected_length) {
    struct {
        unsigned char before[32];
        struct uname value;
        unsigned char after[32];
    } guarded;
    memset(&guarded, 0xa5, sizeof(guarded));
    int calls_before = host_uname_calls;
    do_uname(&guarded.value);
    assert(host_uname_calls == calls_before + 1);
    assert(expected_length < sizeof(guarded.value.hostname));
    assert(memcmp(guarded.value.hostname, expected, expected_length) == 0);
    assert(guarded.value.hostname[expected_length] == '\0');
    assert(strnlen(guarded.value.hostname, sizeof(guarded.value.hostname)) == expected_length);
    assert(strcmp(guarded.value.system, "Linux") == 0);
    assert(strcmp(guarded.value.release, "4.20.69-ish") == 0);
    assert(strncmp(guarded.value.version, "SUPER AWESOME ", 14) == 0);
    assert(memchr(guarded.value.version, '\0', sizeof(guarded.value.version)) != NULL);
    assert(strcmp(guarded.value.arch, "aarch64") == 0);
    assert(strcmp(guarded.value.domain, "(none)") == 0);
    for (size_t i = 0; i < sizeof(guarded.before); i++) {
        assert(guarded.before[i] == 0xa5);
        assert(guarded.after[i] == 0xa5);
    }
    printf("PASS: %s\n", label);
}

int main(void) {
    strcpy(host_name, "blackgod-test");
    check("ordinary host name", "blackgod-test", 13);

    memset(host_name, 'h', 64);
    host_name[64] = '\0';
    check("64-byte host name", host_name, 64);

    memset(host_name, 'h', 65);
    host_name[65] = '\0';
    check("65-byte host name", host_name, 64);

    memset(host_name, 'h', sizeof(host_name) - 1);
    host_name[sizeof(host_name) - 1] = '\0';
    check("maximum Darwin host name", host_name, 64);

    char long_override[4097];
    memset(long_override, 'o', sizeof(long_override) - 1);
    long_override[sizeof(long_override) - 1] = '\0';
    uname_hostname_override = long_override;
    check("4096-byte override", long_override, 64);

    char bounded_override[64];
    memset(bounded_override, 'b', sizeof(bounded_override));
    uname_hostname_override = bounded_override;
    check("read stays inside the 64-byte prefix", bounded_override, 64);

    host_uname_error = 1;
    uname_hostname_override = NULL;
    check("failed host uname uses fallback", "localhost", 9);
    uname_hostname_override = "guest";
    check("override survives failed host uname", "guest", 5);
    uname_hostname_override = NULL;
    return 0;
}
