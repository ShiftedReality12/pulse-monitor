// Interpose OS reads while compiling the real collector, without production test hooks.
#define proc_listallpids fixture_listallpids
#define proc_name fixture_name
#define proc_pidpath fixture_path
#define proc_pidinfo fixture_info
#define proc_pid_rusage fixture_rusage
#include "../../Sources/CSensors/CSensors.c"
#undef proc_listallpids
#undef proc_name
#undef proc_pidpath
#undef proc_pidinfo
#undef proc_pid_rusage

static uint64_t starts[2];
static int identity_reads;
static int unbracketed_reads;
int fixture_listallpids(void *buffer, int size) {
    (void)size;
    if (buffer) *(int *)buffer = 52;
    return 1;
}
int fixture_name(int pid, void *buffer, uint32_t size) {
    unbracketed_reads += identity_reads != 1;
    (void)pid; return snprintf(buffer, size, "codex");
}
int fixture_path(int pid, void *buffer, uint32_t size) {
    unbracketed_reads += identity_reads != 1;
    (void)pid; return snprintf(buffer, size, "/bin/codex");
}
int fixture_info(int pid, int flavor, uint64_t arg, void *buffer, int size) {
    (void)pid; (void)arg; (void)size;
    if (flavor != PROC_PIDTBSDINFO) unbracketed_reads += identity_reads != 1;
    if (flavor == PROC_PIDTBSDINFO) {
        struct proc_bsdinfo *bsd = buffer;
        bsd->pbi_start_tvusec = starts[identity_reads++ > 0 ? 1 : 0];
        bsd->pbi_ppid = 1;
        return sizeof(*bsd);
    }
    if (flavor == PROC_PIDTASKINFO) {
        struct proc_taskinfo *task = buffer;
        task->pti_resident_size = 60000000;
        task->pti_total_user = 123;
        return sizeof(*task);
    }
    return 0;
}
int fixture_rusage(int pid, int flavor, rusage_info_t *buffer) {
    unbracketed_reads += identity_reads != 1;
    (void)pid; (void)flavor; (void)buffer; return -1;
}
int main(void) {
    const uint64_t cases[][3] = {{100, 200, 0}, {100, 100, 1}, {0, 0, 1}, {100, 0, 0}, {0, 100, 0}};
    int failures = 0;
    for (unsigned i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        starts[0] = cases[i][0]; starts[1] = cases[i][1]; identity_reads = 0; unbracketed_reads = 0;
        PulseProcess output = {0}; int pid = 0;
        int count = pulse_processes(&output, 1, &pid, 1);
        int pass = count == (int)cases[i][2] && identity_reads == 2 && !unbracketed_reads;
        if (count) pass = pass && output.started == starts[0] && output.resident == 60000000;
        printf("%s before=%llu after=%llu records=%d identity_reads=%d unbracketed_reads=%d\n", pass ? "PASS" : "FAIL",
               (unsigned long long)starts[0], (unsigned long long)starts[1], count, identity_reads, unbracketed_reads);
        failures += !pass;
    }
    return failures ? 1 : 0;
}
