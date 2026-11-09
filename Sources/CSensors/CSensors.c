#include "CSensors.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <sys/sysctl.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <libproc.h>
#include <dlfcn.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

static int read_value(const char *key, void *value, size_t size) {
    return sysctlbyname(key, value, &size, NULL, 0) == 0;
}
typedef int (*pulse_responsible_fn)(int pid);
static pulse_responsible_fn responsible_for_pid(void) {
    static pulse_responsible_fn function;
    static int looked_up;
    if (!looked_up) {
        looked_up = 1;
        function = (pulse_responsible_fn)dlsym(RTLD_DEFAULT, "responsibility_get_pid_responsible_for_pid");
    }
    return function;
}
/// Root and DriverKit deny proc_pidinfo. sysctl still returns the owner uid.
static int uid_from_sysctl(int pid) {
    struct kinfo_proc info = {0};
    size_t size = sizeof(info);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) return -1;
    return (int)info.kp_eproc.e_ucred.cr_uid;
}
static uint64_t process_identity(int pid, int *parent, int *uid) {
    struct proc_bsdinfo bsd = {0};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) != sizeof(bsd)) {
        if (uid) *uid = uid_from_sysctl(pid);
        return 0;
    }
    if (parent) *parent = bsd.pbi_ppid;
    if (uid) *uid = (int)bsd.pbi_uid;
    return bsd.pbi_start_tvsec * 1000000ULL + bsd.pbi_start_tvusec;
}
int pulse_cpu(PulseCPU *out, int capacity) {
    natural_t n = 0; processor_info_array_t info = NULL; mach_msg_type_number_t count = 0;
    if (host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &info, &count) != KERN_SUCCESS) return 0;
    int length = n < (unsigned)capacity ? (int)n : capacity;
    for (int i = 0; i < length; i++) {
        unsigned int *p = (unsigned int *)info + i * CPU_STATE_MAX;
        out[i] = (PulseCPU){p[CPU_STATE_USER], p[CPU_STATE_SYSTEM], p[CPU_STATE_IDLE], p[CPU_STATE_NICE]};
    }
    vm_deallocate(mach_task_self(), (vm_address_t)info, count * sizeof(integer_t));
    return length;
}
PulseMemory pulse_memory(void) {
    PulseMemory result = {0}; result.free_percent = -1; result.pressure_level = -1;
    read_value("hw.memsize", &result.total, sizeof(result.total));
    vm_statistics64_data_t vm = {0}; mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    vm_size_t page = 0; host_page_size(mach_host_self(), &page);
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vm, &count) == KERN_SUCCESS && result.total) {
        // Activity Monitor style physical usage: active + wired + compressor minus purgeable/external pages.
        uint64_t occupied = (uint64_t)vm.active_count + vm.inactive_count + vm.wire_count + vm.compressor_page_count;
        uint64_t reclaimable = (uint64_t)vm.purgeable_count + vm.external_page_count;
        result.used = (occupied > reclaimable ? occupied - reclaimable : 0) * page;
        result.compressed = (uint64_t)vm.compressor_page_count * page;
        result.vm_ok = 1;
    }
    struct xsw_usage swap = {0};
    if (read_value("vm.swapusage", &swap, sizeof(swap))) { result.swap = swap.xsu_used; result.swap_ok = 1; }
    int pressure = 0;
    if (read_value("kern.memorystatus_vm_pressure_level", &pressure, sizeof(pressure))) result.pressure_level = pressure;
    int percent = 0;
    int (*get_level)(unsigned int *) = dlsym(RTLD_DEFAULT, "memorystatus_get_level");
    if (get_level && get_level((unsigned int *)&percent) == 0 && percent >= 0 && percent <= 100) result.free_percent = percent;
    return result;
}
int pulse_processes(PulseProcess *out, int capacity, int *pids, int pid_capacity) {
    int count = proc_listallpids(NULL, 0);
    if (count <= 0) return 0;
    if (!out || capacity == 0) return count + 64;
    if (!pids || pid_capacity <= 0) return 0;
    count = proc_listallpids(pids, pid_capacity * sizeof(int));
    int used = 0;
    for (int i = 0; i < count && used < capacity; i++) {
        if (pids[i] <= 0) continue;
        PulseProcess p = {0}; p.pid = pids[i]; p.uid = -1;
        p.started = process_identity(p.pid, &p.parent, &p.uid);
        proc_name(p.pid, p.name, sizeof(p.name)); proc_pidpath(p.pid, p.path, sizeof(p.path));
        struct proc_taskinfo task = {0};
        if (proc_pidinfo(p.pid, PROC_PIDTASKINFO, 0, &task, sizeof(task)) == sizeof(task)) {
            p.resident = task.pti_resident_size; p.cpu_ns = task.pti_total_user + task.pti_total_system; p.readable = 1;
        }
        // V4 replaces the old V2 disk call. Every process is sampled: a top-N cut by RSS drops the virtual machine, whose footprint is far above its RSS.
        struct rusage_info_v4 usage = {0};
        if (proc_pid_rusage(p.pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) == 0) {
            p.io_ok = 1; p.disk_written = usage.ri_diskio_byteswritten; p.footprint = usage.ri_phys_footprint;
        }
        // Private one-argument function. dlsym keeps a missing symbol from blocking launch.
        if (!strstr(p.path, ".app/") && (p.parent == 1 || strstr(p.name, "Virtualization") || strstr(p.path, ".xpc/"))) {
            pulse_responsible_fn lookup = responsible_for_pid();
            int responsible = lookup ? lookup(p.pid) : 0;
            if (responsible > 1 && responsible != p.pid) p.responsible = responsible;
        }
        if (strstr(p.name, "codex") || strstr(p.name, "claude") || strstr(p.name, "node") || strstr(p.name, "python") || strstr(p.name, "Python") || strstr(p.path, "/claude/versions/")) {
            struct proc_vnodepathinfo paths = {0};
            if (proc_pidinfo(p.pid, PROC_PIDVNODEPATHINFO, 0, &paths, sizeof(paths)) == sizeof(paths)) snprintf(p.cwd, sizeof(p.cwd), "%s", paths.pvi_cdir.vip_path);
        }
        if (!p.name[0] && p.path[0]) {
            const char *last = strrchr(p.path, '/');
            snprintf(p.name, sizeof(p.name), "%s", last ? last + 1 : p.path);
        }
        if (!p.name[0]) snprintf(p.name, sizeof(p.name), "Unknown helper (pid %d)", p.pid);
        if (process_identity(p.pid, NULL, NULL) != p.started) continue;
        out[used++] = p;
    }
    return used;
}
int pulse_disk_writes(uint64_t *bytes) {
    io_iterator_t iterator = 0; *bytes = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) != KERN_SUCCESS) return 0;
    int found = 0; io_object_t object;
    while ((object = IOIteratorNext(iterator))) {
        CFTypeRef stats = IORegistryEntryCreateCFProperty(object, CFSTR("Statistics"), kCFAllocatorDefault, 0);
        if (stats && CFGetTypeID(stats) == CFDictionaryGetTypeID()) {
            CFNumberRef value = CFDictionaryGetValue(stats, CFSTR("Bytes (Write)"));
            int64_t number = 0;
            if (value && CFGetTypeID(value) == CFNumberGetTypeID() && CFNumberGetValue(value, kCFNumberSInt64Type, &number) && number >= 0) { *bytes += (uint64_t)number; found = 1; }
        }
        if (stats) CFRelease(stats); IOObjectRelease(object);
    }
    IOObjectRelease(iterator); return found;
}
int pulse_perf_count(int level) {
    char key[64]; int value = 0; snprintf(key, sizeof(key), "hw.perflevel%d.logicalcpu", level);
    return read_value(key, &value, sizeof(value)) ? value : 0;
}
uint64_t pulse_boot_time(void) {
    struct timeval boot = {0}; return read_value("kern.boottime", &boot, sizeof(boot)) ? (uint64_t)boot.tv_sec : 0;
}

int pulse_process_env(int pid, const char *key, char *out, int capacity) {
    if (!out || capacity <= 0 || !key || !*key) return 0;
    out[0] = 0;
    int mib[3] = {CTL_KERN, KERN_PROCARGS2, pid};
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) != 0 || size < sizeof(int) || size > 4u * 1024 * 1024) return -1;
    char *buffer = malloc(size);
    if (!buffer) return -1;
    if (sysctl(mib, 3, buffer, &size, NULL, 0) != 0 || size < sizeof(int)) { free(buffer); return -1; }
    int argc = 0; memcpy(&argc, buffer, sizeof(int));
    char *cursor = buffer + sizeof(int), *end = buffer + size;
    while (cursor < end && *cursor) cursor++;            // executable path
    while (cursor < end && !*cursor) cursor++;           // padding
    for (int i = 0; i < argc && cursor < end; i++) {      // skip argv
        while (cursor < end && *cursor) cursor++;
        cursor++;
    }
    size_t length = strlen(key); int found = 0;
    while (cursor < end && *cursor) {                     // environment, NAME=value
        size_t remaining = (size_t)(end - cursor);
        size_t item = strnlen(cursor, remaining);
        if (item > length && cursor[length] == '=' && strncmp(cursor, key, length) == 0) {
            snprintf(out, (size_t)capacity, "%.*s", (int)(item - length - 1), cursor + length + 1);
            found = out[0] != 0; break;
        }
        cursor += item + 1;
    }
    free(buffer);
    return found;
}
PulseThermal pulse_thermal(void) {
    PulseThermal result = {-1, -1, -1, -1};
    uint32_t level = 0;
    if (IOPMGetThermalWarningLevel(&level) == kIOReturnSuccess) result.warning_level = (int)level;
    CFDictionaryRef status = NULL;
    if (IOPMCopyCPUPowerStatus(&status) == kIOReturnSuccess && status) {
        struct { CFStringRef key; int *slot; } fields[] = {
            {CFSTR("CPU_Speed_Limit"), &result.speed_limit}, {CFSTR("CPU_Scheduler_Limit"), &result.scheduler_limit},
            {CFSTR("CPU_Available_CPUs"), &result.available_cpus}};
        for (int i = 0; i < 3; i++) {
            CFNumberRef value = CFDictionaryGetValue(status, fields[i].key);
            int number = 0;
            if (value && CFGetTypeID(value) == CFNumberGetTypeID() && CFNumberGetValue(value, kCFNumberIntType, &number)) *fields[i].slot = number;
        }
        CFRelease(status);
    }
    return result;
}
