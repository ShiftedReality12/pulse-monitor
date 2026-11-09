#ifndef PULSE_DISK_H
#define PULSE_DISK_H
#include <stdint.h>
typedef struct PulseBulk PulseBulk;
typedef struct { char name[1024]; uint64_t inode, allocated; uint32_t type, links; int error; } PulseDiskEntry;
typedef struct { uint64_t allocated; int entries, status; PulseDiskEntry boundary; } PulseDiskBatch;
void *pulse_cancel_create(void);
void pulse_cancel_destroy(void *flag);
void pulse_cancel_set(void *flag);
int pulse_cancelled(const void *flag);
void pulse_bulk_batch(PulseBulk *reader, int limit, PulseDiskBatch *batch, const void *cancellation, double cpu_deadline);
PulseBulk *pulse_bulk_open(int fd, int64_t offset, int skipped);
int pulse_bulk_next(PulseBulk *reader, PulseDiskEntry *entry);
int64_t pulse_bulk_offset(PulseBulk *reader);
int pulse_bulk_skipped(PulseBulk *reader);
void pulse_bulk_close(PulseBulk *reader);
int pulse_spawn_group(const char *path, char *const argv[], int *read_fd);
int pulse_process_succeeded(int status);
#endif
