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
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

// Read-only SMC ABI: selector 2, key metadata command 9, key read command 5.
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } SMCPLimit;
typedef struct { uint32_t size, type; uint8_t attributes; } SMCKeyInfo;
typedef struct {
    uint32_t key; SMCVersion version; SMCPLimit limit; SMCKeyInfo info;
    uint8_t result, status, command; uint32_t data32; uint8_t bytes[32];
} SMCData;
static uint32_t fourcc(const char *s) { return (uint32_t)(uint8_t)s[0]<<24 | (uint32_t)(uint8_t)s[1]<<16 | (uint32_t)(uint8_t)s[2]<<8 | (uint8_t)s[3]; }
static double smc_read(io_connect_t connection, const char *key) {
    SMCData in = {0}, out = {0}; size_t size = sizeof(out);
    in.key = fourcc(key); in.command = 9;
    if (IOConnectCallStructMethod(connection, 2, &in, sizeof(in), &out, &size) != KERN_SUCCESS || out.result || out.info.size > 32) return NAN;
    in.info = out.info; in.command = 5; size = sizeof(out);
    if (IOConnectCallStructMethod(connection, 2, &in, sizeof(in), &out, &size) != KERN_SUCCESS || out.result) return NAN;
    if (in.info.type == fourcc("flt ") && in.info.size == 4) { float f; memcpy(&f, out.bytes, 4); return f; }
    if (in.info.type == fourcc("fpe2") && in.info.size == 2) return (out.bytes[0] * 256 + out.bytes[1]) / 4.0;
    if (in.info.type == fourcc("sp78") && in.info.size == 2) return (int16_t)(out.bytes[0] * 256 + out.bytes[1]) / 256.0;
    if (in.info.type == fourcc("ui8 ") && in.info.size == 1) return out.bytes[0];
    return NAN;
}
PulseSensors pulse_sensors(void) {
    PulseSensors result = {0}; result.celsius = NAN; result.cpu_die = NAN;
    int hid_count = -1; kern_return_t smc_status = kIOReturnNotFound;
    // dlopen keeps unavailable private symbols from preventing application launch.
    void *library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    if (library) {
        CFTypeRef (*create)(CFAllocatorRef) = dlsym(library, "IOHIDEventSystemClientCreate");
        CFArrayRef (*services)(CFTypeRef) = dlsym(library, "IOHIDEventSystemClientCopyServices");
        int (*matching)(CFTypeRef, CFDictionaryRef) = dlsym(library, "IOHIDEventSystemClientSetMatching");
        CFTypeRef (*event)(CFTypeRef, int64_t, int32_t, int64_t) = dlsym(library, "IOHIDServiceClientCopyEvent");
        double (*value)(CFTypeRef, int64_t) = dlsym(library, "IOHIDEventGetFloatValue");
        CFTypeRef (*property)(CFTypeRef, CFStringRef) = dlsym(library, "IOHIDServiceClientCopyProperty");
        if (create && services && matching && event && value) {
            CFTypeRef client = create(kCFAllocatorDefault);
            if (client) {
                int page = 0xff00, usage = 5;
                CFNumberRef p = CFNumberCreate(NULL, kCFNumberIntType, &page), u = CFNumberCreate(NULL, kCFNumberIntType, &usage);
                const void *keys[] = {CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage")}; const void *values[] = {p, u};
                CFDictionaryRef match = CFDictionaryCreate(NULL, keys, values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
                matching(client, match); CFRelease(match); CFRelease(p); CFRelease(u);
                CFArrayRef list = services(client);
                double maximum = NAN;
                if (list) {
                    hid_count = (int)CFArrayGetCount(list);
                    for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
                        CFTypeRef e = event(CFArrayGetValueAtIndex(list, i), 15, 0, 0);
                        if (e) {
                            double t = value(e, 15 << 16);
                            if (t > 0 && t < 150) {
                                if (!isfinite(maximum) || t > maximum) maximum = t;
                                CFTypeRef product = property ? property(CFArrayGetValueAtIndex(list, i), CFSTR("Product")) : NULL;
                                char name[256] = {0};
                                if (product && CFGetTypeID(product) == CFStringGetTypeID()) CFStringGetCString(product, name, sizeof(name), kCFStringEncodingUTF8);
                                if ((strstr(name, "pACC MTR Temp Sensor") || strstr(name, "eACC MTR Temp Sensor") || strstr(name, "CPU Die")) && (!isfinite(result.cpu_die) || t > result.cpu_die)) result.cpu_die = t;
                                if (product) CFRelease(product);
                            }
                            CFRelease(e);
                        }
                    }
                    CFRelease(list);
                }
                result.celsius = maximum; CFRelease(client);
            }
        }
        dlclose(library);
    }
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    io_connect_t connection = 0;
    if (service) smc_status = IOServiceOpen(service, mach_task_self(), 0, &connection);
    if (service && smc_status == KERN_SUCCESS) {
        // A known CPU proximity key is an honest fallback, never a guessed default.
        if (!isfinite(result.celsius)) { double t = smc_read(connection, "TC0P"); if (t > 0 && t < 150) result.celsius = t; }
        double fans = smc_read(connection, "FNum");
        if (isfinite(fans) && fans >= 0 && fans <= 4) {
            for (int i = 0; i < (int)fans; i++) {
                char key[5]; snprintf(key, sizeof(key), "F%dAc", i);
                double rpm = smc_read(connection, key);
                if (isfinite(rpm) && rpm >= 0 && rpm < 20000) result.fans[result.fan_count++] = rpm;
            }
        }
        IOServiceClose(connection);
    }
    if (service) IOObjectRelease(service);
    snprintf(result.status, sizeof(result.status), "%s. HID services: %d; SMC open: 0x%x%s", isfinite(result.cpu_die) ? "CPU-die maximum (named CPU HID sensors)" : isfinite(result.celsius) ? "Available HID maximum / SMC CPU proximity; CPU-die mapping unavailable" : "Sensor unavailable", hid_count, smc_status, !isfinite(result.celsius) && smc_status == KERN_SUCCESS ? "; TC0P returned no valid temperature" : "");
    return result;
}
