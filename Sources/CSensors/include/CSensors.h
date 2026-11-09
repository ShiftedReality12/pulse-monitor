#ifndef PULSE_SENSORS_H
#define PULSE_SENSORS_H
#include <stdint.h>
#include <stddef.h>
#include "PulseDisk.h"
typedef struct { uint64_t user, system, idle, nice; } PulseCPU;
typedef struct {
    uint64_t total, used, compressed, swap;
    int vm_ok, swap_ok, pressure_level;
    double free_percent;
} PulseMemory;
typedef struct {
    int pid; uint64_t resident, cpu_ns, started;
    int readable; char name[1024]; char path[4096];
    int parent; uint64_t disk_written; int io_ok; char cwd[1024];
    uint64_t footprint; int uid; int responsible;
} PulseProcess;
typedef struct { double celsius; double cpu_die; double fans[4]; int fan_count; char status[256]; } PulseSensors;
typedef struct { int warning_level, speed_limit, scheduler_limit, available_cpus; } PulseThermal;
int pulse_cpu(PulseCPU *out, int capacity);
/// Reads only the whitelisted configuration/pane variables of the caller's own processes.
/// Returns 1 when found, 0 when the variable is absent, -1 when the environment could not be read (exited, restricted, other user).
int pulse_process_env(int pid, const char *key, char *out, int capacity);
/// Mirrors `pmset -g therm`; every field is -1 when macOS has recorded nothing.
PulseThermal pulse_thermal(void);
PulseMemory pulse_memory(void);
int pulse_processes(PulseProcess *out, int capacity, int *pids, int pid_capacity);
int pulse_disk_writes(uint64_t *bytes);
PulseSensors pulse_sensors(void);
int pulse_perf_count(int level);
uint64_t pulse_boot_time(void);
#endif
