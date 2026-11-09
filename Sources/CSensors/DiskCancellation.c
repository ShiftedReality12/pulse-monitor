#include <stdatomic.h>
#include <stdlib.h>
void *pulse_cancel_create(void) { return calloc(1, sizeof(_Atomic int)); }
void pulse_cancel_destroy(void *flag) { free(flag); }
void pulse_cancel_set(void *flag) { atomic_store((_Atomic int *)flag, 1); }
int pulse_cancelled(const void *flag) { return flag && atomic_load((const _Atomic int *)flag); }
