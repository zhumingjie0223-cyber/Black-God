// Black God minimal iSH host. Links GPLv3 iSH; see THIRD_PARTY.md.
#import "ISHKernel.h"
#include "ish/kernel/init.h"
#include "ish/kernel/task.h"
#include "ish/kernel/signal.h"
#include "ish/kernel/calls.h"
#include "ish/kernel/fs.h"
#define ISH_INTERNAL
#include "ish/fs/fake.h"
#include "ish/fs/devices.h"
#include "ish/fs/path.h"
#include "ish/fs/fd.h"
#include "ish/asbestos/frame.h"
#include <signal.h>
#include <sys/ucontext.h>
#include <pthread.h>
#include <stddef.h>
#include <mach/mach.h>

NSNotificationName const ISHProcessExitedNotification = @"BlackGodISHProcessExited";
extern void (*exit_hook)(struct task *, int);
extern const char *sock_tmp_prefix;
extern __thread volatile sig_atomic_t in_jit;
extern __thread volatile uint64_t jit_saved_pc;
extern void jit_crash_trampoline(void);
static struct sigaction previousSegv, previousBus;

// Derived from the pinned kernel's main.c. Compute offsets from the current
// types: Minis' older hardcoded offsets do not match this kernel revision.
static void recoverGuestFault(int sig, siginfo_t *info, void *context) {
#if defined(__aarch64__)
    if (in_jit) {
        ucontext_t *uc = context;
        struct cpu_state *cpu = (void *)uc->uc_mcontext->__ss.__x[1];
        cpu->segfault_addr = (uc->uc_mcontext->__ss.__x[7] - uc->uc_mcontext->__ss.__x[10]) & 0xffffffffffffULL;
        cpu->segfault_was_write = (uc->uc_mcontext->__es.__esr & 0x40) != 0;
        cpu->pc = jit_saved_pc;
        // cpu_state is the first member of fiber_frame.
        uc->uc_mcontext->__ss.__sp = ((struct fiber_frame *)cpu)->jit_exit_sp;
        uc->uc_mcontext->__ss.__pc = (uint64_t)jit_crash_trampoline;
        return;
    }
#endif
    // Do not swallow host faults or detach Swift threads.
    struct sigaction *previous = sig == SIGBUS ? &previousBus : &previousSegv;
    sigaction(sig, previous, NULL);
    raise(sig);
}
static void processExited(struct task *task, int status) {
    if (task->parent && task->parent->parent) return;
    int pid = task->pid;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:ISHProcessExitedNotification object:nil
            userInfo:@{@"pid": @(pid), @"code": @(status)}];
    });
}
static int memoryGuard(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return -1;
    return info.phys_footprint < 256 * 1024 * 1024 ? 0 : -1;
}
@implementation ISHKernel {
    BOOL _isBooted;
    BOOL _attempted;
}
+ (ISHKernel *)shared { static ISHKernel *value; static dispatch_once_t once; dispatch_once(&once, ^{ value = [ISHKernel new]; }); return value; }
- (BOOL)isBooted { return _isBooted; }
- (int)confineCurrentTask {
    if (!self.nextRoot) return 0;
    struct fd *root = generic_open(self.nextRoot.fileSystemRepresentation, O_RDONLY_, 0);
    if (IS_ERR(root)) return PTR_ERR(root);
    fd_close(current->fs->root);
    fd_close(current->fs->pwd);
    current->fs->root = root;
    current->fs->pwd = fd_retain(root);
    current->group->fs_context = 1;
    current->uid = current->euid = current->suid = 1000;
    current->gid = current->egid = current->sgid = 1000;
    current->ngroups = 0;
    return 0;
}
- (void)terminateGuestProcesses {
    if (!_isBooted) return;
    lock(&pids_lock);
    struct siginfo_ info = SIGINFO_NIL;
    for (int pid = 2; pid < MAX_PID; pid++) {
        struct task *task = pid_get_task(pid);
        if (task) send_signal(task, SIGKILL_, info);
    }
    unlock(&pids_lock);
}
- (int)reapAndCountGuestProcesses {
    if (!_isBooted) return 0;
    // Only the host owns PID 1. Nonblocking wait reaps its exited children.
    extern int do_wait(int, pid_t_, struct siginfo_ *, struct rusage_ *, int);
    struct task *saved = current;
    current = pid_get_task(1);
    for (int i = 0; i < MAX_PID; i++) {
        struct siginfo_ info = SIGINFO_NIL;
        int err = do_wait(0, 0, &info, NULL, (1 << 0) | (1 << 2));
        if (err < 0 || info.child.pid == 0) break;
    }
    current = saved;
    int count = 0;
    lock(&pids_lock);
    for (int pid = 2; pid < MAX_PID; pid++) if (pid_get_task(pid)) count++;
    unlock(&pids_lock);
    return count;
}
- (int)bootWithRootPath:(NSString *)path {
    NSAssert([NSThread isMainThread], @"Kernel setup requires main thread");
    if (_isBooted) return 0;
    if (_attempted) return -1; // partial mount is not safe to repeat in-process
    _attempted = YES;
    NSString *data = [path stringByAppendingPathComponent:@"data"];
    int err = mount_root(&fakefs, data.fileSystemRepresentation);
    if (err < 0) return err;
    char resolved[4096];
    if (realpath(data.fileSystemRepresentation, resolved)) fakefs_set_rootfs_data_path(resolved);
    err = become_first_process();
    if (err < 0) return err;
    current->thread = pthread_self();
    generic_mkdirat(AT_PWD, "/dev", 0755);
    generic_mkdirat(AT_PWD, "/dev/pts", 0755);
    generic_mkdirat(AT_PWD, "/proc", 0755);
    generic_mkdirat(AT_PWD, "/workspace", 0700);
    generic_mknodat(AT_PWD, "/dev/null", S_IFCHR|0666, dev_make(MEM_MAJOR, DEV_NULL_MINOR));
    generic_mknodat(AT_PWD, "/dev/zero", S_IFCHR|0666, dev_make(MEM_MAJOR, DEV_ZERO_MINOR));
    generic_mknodat(AT_PWD, "/dev/random", S_IFCHR|0666, dev_make(MEM_MAJOR, DEV_RANDOM_MINOR));
    generic_mknodat(AT_PWD, "/dev/urandom", S_IFCHR|0666, dev_make(MEM_MAJOR, DEV_URANDOM_MINOR));
    do_mount(&procfs, "proc", "/proc", "", 0);
    do_mount(&devptsfs, "devpts", "/dev/pts", "", 0);
    NSString *socketDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"blackgod-guest-sockets"];
    [[NSFileManager defaultManager] createDirectoryAtPath:socketDir withIntermediateDirectories:YES attributes:nil error:nil];
    sock_tmp_prefix = strdup([[socketDir stringByAppendingString:@"/"] UTF8String]);
    exit_hook = processExited;
    ish_set_fork_guard(memoryGuard);
    struct sigaction action = {0};
    action.sa_sigaction = recoverGuestFault;
    action.sa_flags = SA_SIGINFO;
    sigemptyset(&action.sa_mask);
    sigaction(SIGSEGV, &action, &previousSegv);
    sigaction(SIGBUS, &action, &previousBus);
    _isBooted = YES;
    return 0;
}
@end
