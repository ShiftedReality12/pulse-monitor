#include "include/PulseDisk.h"
#include <sys/attr.h>
#include <sys/vnode.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <time.h>

struct PulseBulk {
    const void *cancellation;
    double cpu_deadline;
    int fd, remaining, used;
    int64_t skip;
    int64_t offset;
    size_t position;
    char buffer[32768];
};
PulseBulk *pulse_bulk_open(int fd, int64_t offset, int skipped) {
    /* APFS cookies are stream-local. Reopen at zero and discard the absolute entry index. */
    PulseBulk *reader = calloc(1, sizeof(*reader));
    if (reader) { reader->fd = fd; reader->offset = 0; reader->skip = offset + skipped; }
    return reader;
}
int64_t pulse_bulk_offset(PulseBulk *reader) { return reader->skip > 0 ? reader->offset + reader->used + reader->skip : reader->offset; }
int pulse_bulk_skipped(PulseBulk *reader) { return reader->skip > 0 ? 0 : reader->used; }
void pulse_bulk_close(PulseBulk *reader) { free(reader); }
#define READ(value) do { if (field + sizeof(value) > end) return -1; memcpy(&(value), field, sizeof(value)); field += sizeof(value); } while (0)
int pulse_bulk_next(PulseBulk *reader, PulseDiskEntry *entry) {
    for (;;) {
        if (pulse_cancelled(reader->cancellation) || (reader->cpu_deadline > 0 && (reader->used & 31) == 0 &&
            (double)clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) / 1e9 >= reader->cpu_deadline)) return -2;
        if (!reader->remaining) {
            struct attrlist attrs = {0};
            attrs.bitmapcount = ATTR_BIT_MAP_COUNT;
            attrs.commonattr = ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_ERROR | ATTR_CMN_NAME | ATTR_CMN_OBJTYPE | ATTR_CMN_FILEID;
            attrs.fileattr = ATTR_FILE_LINKCOUNT | ATTR_FILE_ALLOCSIZE;
            reader->offset += reader->used;
            reader->used = 0; reader->position = 0;
            int count = getattrlistbulk(reader->fd, &attrs, reader->buffer, sizeof(reader->buffer), FSOPT_PACK_INVAL_ATTRS);
            if (count <= 0) return count;
            reader->remaining = count;
        }
        char *start = reader->buffer + reader->position, *field = start;
        char *end = reader->buffer + sizeof(reader->buffer);
        uint32_t length; READ(length);
        if (length < 4 || length > (size_t)(end - start)) return -1;
        end = start + length;
        reader->position += length; reader->remaining--; reader->used++;
        if (reader->skip > 0) { reader->skip--; continue; }
        attribute_set_t returned; uint32_t error, type, links = 0;
        attrreference_t name; uint64_t inode; off_t allocated = 0;
        READ(returned); READ(error);
        char *reference = field; READ(name); READ(type); READ(inode);
        if (returned.fileattr & ATTR_FILE_LINKCOUNT) { READ(links); }
        if (returned.fileattr & ATTR_FILE_ALLOCSIZE) { READ(allocated); }
        if (name.attr_dataoffset < 0 || name.attr_length == 0 ||
            reference + name.attr_dataoffset >= end ||
            name.attr_length > (size_t)(end - (reference + name.attr_dataoffset))) return -1;

        size_t count = name.attr_length < sizeof(entry->name) ? name.attr_length : sizeof(entry->name);
        memcpy(entry->name, reference + name.attr_dataoffset, count);
        entry->name[count < sizeof(entry->name) ? count : sizeof(entry->name) - 1] = 0;
        entry->type = type; entry->inode = inode; entry->links = links;
        entry->allocated = allocated > 0 ? (uint64_t)allocated : 0;
        entry->error = (int)error;
        if (!(returned.commonattr & ATTR_CMN_OBJTYPE) || !(returned.commonattr & ATTR_CMN_FILEID) ||
            (type == VREG && !(returned.fileattr & ATTR_FILE_ALLOCSIZE))) entry->error = EIO;
        return 1;
    }
}

/* Regular leaves stay in C: Swift receives only aggregates or a directory/hardlink boundary. */
void pulse_bulk_batch(PulseBulk *reader, int limit, PulseDiskBatch *batch, const void *cancellation, double cpu_deadline) {
    reader->cancellation = cancellation; reader->cpu_deadline = cpu_deadline;
    batch->allocated = 0; batch->entries = 0; batch->status = 1;
    while (batch->entries < limit) {
        int status = pulse_bulk_next(reader, &batch->boundary);
        if (status <= 0) { batch->status = status; reader->cancellation = NULL; reader->cpu_deadline = 0; return; }
        batch->entries++;
        if (!batch->boundary.error && batch->boundary.type == VREG && batch->boundary.links <= 1) {
            batch->allocated += batch->boundary.allocated;
        } else { batch->status = 2; reader->cancellation = NULL; reader->cpu_deadline = 0; return; }
    }
    reader->cancellation = NULL; reader->cpu_deadline = 0;
}
