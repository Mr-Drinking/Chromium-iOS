// vaclamp: gives an app in the iOS simulator the address space of an app on an
// iPhone without the extended virtual addressing entitlement (one sideloaded
// with a free Apple ID), to test how it copes there.
//
// Without the entitlement, xnu lets a process on a device with more than 3 GB
// of memory use addresses below 17.375 GiB (ARM64_MAX_OFFSET_DEVICE_LARGE), and
// 6-12 GiB is the shared region. A simulator app is a macOS process with far
// more room. Injected ahead of the app's own initializers, this library reserves
// (no access) every free range in 6-12 GiB and above the limit, and gives back
// the part of 12 GiB up to the limit that the simulator's dyld reserves.
//
// Build, then launch the installed app with it (see docs/build-guide.md):
//   xcrun -sdk iphonesimulator clang -target arm64-apple-ios26.0-simulator \
//       -dynamiclib -O2 -o out/vaclamp.dylib tools/vaclamp.c
//   SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=$PWD/out/vaclamp.dylib \
//   SIMCTL_CHILD_JSC_useJIT=false \
//       xcrun simctl launch --console-pty <device> <bundle id>
// JSC_useJIT=false because apps can't JIT on a device, so JavaScriptCore (if
// something starts it) doesn't reserve its 512 MB JIT region there.
//
// Settings (environment, SIMCTL_CHILD_-prefixed for simctl):
//   VACLAMP_LIMIT_GIB        end of the address space, default 17.375
//   VACLAMP_LOG              write to this file instead of stderr, unbuffered
//                            (somewhere under /tmp: on an external volume the
//                            app's open() waits for a privacy prompt)
//   VACLAMP_DUMP_AFTER       seconds until the full layout is logged again (20)
//   VACLAMP_USAGE_EVERY      then log resident memory per Chromium VM tag
//                            (240-255) every N seconds
//   VACLAMP_LAYOUT_EVERY_MS  log a one-line layout every N ms
// Every failed mmap of 16 MB or more is logged with the layout at that moment,
// and with a backtrace if it asked for 64 MB to 1 GB.

#include <errno.h>
#include <execinfo.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define GiB (1ULL << 30)

// Output: VACLAMP_LOG if set, else stderr.
static int g_fd = 2;

static void say(const char* format, ...) {
  char buffer[4096];
  va_list args;
  va_start(args, format);
  int n = vsnprintf(buffer, sizeof buffer, format, args);
  va_end(args);
  if (n > (int)sizeof buffer - 1) n = sizeof buffer - 1;
  if (n > 0) write(g_fd, buffer, (size_t)n);
}

// The simulator app is a macOS process: its user address space ends here, not
// at the iOS SDK's MACH_VM_MAX_ADDRESS.
#define TOP 0x00007FFFFE000000ULL

static void dump(const char* title) {
  say("vaclamp: --- %s (GiB; free gaps >= 64 MiB marked)\n", title);
  vm_address_t addr = 0, prev_end = 0;
  int depth = 0;
  for (;;) {
    vm_size_t size = 0;
    natural_t d = depth;
    vm_region_submap_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
    if (vm_region_recurse_64(mach_task_self(), &addr, &size, &d,
                               (vm_region_recurse_info_t)&info,
                               &count) != KERN_SUCCESS) {
      break;
    }
    if (addr - prev_end >= 64ULL << 20 && prev_end) {
      say("vaclamp:   %9.3f-%9.3f  FREE %.3f\n",
              (double)prev_end / GiB, (double)addr / GiB,
              (double)(addr - prev_end) / GiB);
    }
    // Only print big regions or Chromium's own tags (240-255).
    if (size >= 256ULL << 20 || info.user_tag >= 240) {
      say("vaclamp:   %9.3f-%9.3f  tag %3u prot %d size %.3f\n",
              (double)addr / GiB, (double)(addr + size) / GiB,
              info.user_tag, info.protection, (double)size / GiB);
    }
    prev_end = addr + size;
    addr += size;
  }
}

static void compact(void) {
  vm_address_t addr = 0, prev_end = 0;
  char line[4096];
  int n = 0;
  n += snprintf(line + n, sizeof line - n, "vaclamp: now:");
  for (;;) {
    vm_size_t size = 0;
    natural_t depth = 0;
    vm_region_submap_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
    if (vm_region_recurse_64(mach_task_self(), &addr, &size, &depth,
                             (vm_region_recurse_info_t)&info,
                             &count) != KERN_SUCCESS || addr >= 18 * GiB) {
      break;
    }
    if (prev_end && addr - prev_end >= (16ULL << 20) && n < 3900)
      n += snprintf(line + n, sizeof line - n, " free %.3f+%.0fM", (double)prev_end / GiB,
                    (double)(addr - prev_end) / 1048576);
    if (size >= (64ULL << 20) && addr >= 4 * GiB && n < 3900)
      n += snprintf(line + n, sizeof line - n, " [%.3f+%.0fM t%u]", (double)addr / GiB,
                    (double)size / 1048576, info.user_tag);
    prev_end = addr + size;
    addr += size;
  }
  if (n < (int)sizeof line - 1) line[n++] = '\n';
  write(g_fd, line, (size_t)n);
}

static void* compact_loop(void* arg) {
  long ms = (long)arg;
  for (;;) {
    usleep((useconds_t)(ms * 1000));
    compact();
  }
  return NULL;
}

// Log every failed mmap of 16 MiB or more, with the layout at that moment.
static void* vaclamp_mmap(void* addr, size_t len, int prot, int flags, int fd,
                          off_t offset) {
  void* result = mmap(addr, len, prot, flags, fd, offset);
  if (result == MAP_FAILED && len >= (16u << 20)) {
    int saved = errno;
    char msg[256];
    int n = snprintf(msg, sizeof msg,
                     "vaclamp: mmap(hint %.3f GiB, %zu MiB, prot %d, flags 0x%x) failed: %s\n",
                     (double)(uintptr_t)addr / GiB, len >> 20, prot, flags, strerror(saved));
    write(g_fd, msg, (size_t)n);
    compact();
    if (len >= (64u << 20) && len <= GiB) {
      void* frames[14];
      int count = backtrace(frames, 14);
      backtrace_symbols_fd(frames + 1, count - 1, g_fd);
    }
    errno = saved;
  }
  return result;
}
__attribute__((used)) static struct {
  const void* replacement;
  const void* replacee;
} interpose_mmap __attribute__((section("__DATA,__interpose"))) = {
    (const void*)&vaclamp_mmap, (const void*)&mmap};

static void reserve_free(vm_address_t start, vm_address_t end) {
  vm_address_t addr = start;
  int n = 0;
  unsigned long long total = 0;
  while (addr < end) {
    vm_address_t region = addr;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    kern_return_t kr =
        vm_region_64(mach_task_self(), &region, &size, VM_REGION_BASIC_INFO_64,
                       (vm_region_info_t)&info, &count, &object);
    vm_address_t gap_end = kr == KERN_SUCCESS ? region : end;
    if (gap_end > end) gap_end = end;
    if (gap_end > addr) {
      vm_address_t a = addr;
      kern_return_t r = vm_map(mach_task_self(), &a, gap_end - addr, 0,
                                    VM_FLAGS_FIXED, MACH_PORT_NULL, 0, FALSE,
                                    VM_PROT_NONE, VM_PROT_NONE, VM_INHERIT_NONE);
      if (r == KERN_SUCCESS) {
        n++;
        total += gap_end - addr;
      } else {
        say("vaclamp: reserving %.3f-%.3f failed: %d\n",
                (double)addr / GiB, (double)gap_end / GiB, r);
      }
    }
    if (kr != KERN_SUCCESS) break;
    addr = region + size;
  }
  say("vaclamp: reserved %d gaps in %.3f-%.3f GiB (%.1f GiB)\n", n,
          (double)start / GiB, (double)end / GiB, (double)total / GiB);
}

// The simulator's dyld reserves (tag 60, no access) everything from the end
// of the simulator's shared cache up to 63 GiB. On a device, 12 GiB up to the
// limit is free, so give that part back.
static void release_dyld_reservation(vm_address_t start, vm_address_t end) {
  vm_address_t addr = start;
  unsigned long long total = 0;
  while (addr < end) {
    vm_size_t size = 0;
    natural_t depth = 0;
    vm_region_submap_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
    vm_address_t region = addr;
    if (vm_region_recurse_64(mach_task_self(), &region, &size, &depth,
                             (vm_region_recurse_info_t)&info,
                             &count) != KERN_SUCCESS || region >= end) {
      break;
    }
    vm_address_t a = region > addr ? region : addr;
    vm_address_t b = region + size < end ? region + size : end;
    if (info.user_tag == 60 && info.protection == VM_PROT_NONE && b > a) {
      if (vm_deallocate(mach_task_self(), a, b - a) == KERN_SUCCESS) {
        total += b - a;
      }
    }
    addr = region + size;
  }
  say("vaclamp: released %.3f GiB of dyld's reservation in %.3f-%.3f GiB\n",
          (double)total / GiB, (double)start / GiB, (double)end / GiB);
}

// Resident memory in regions tagged by Chromium (240-255), per tag and per
// GiB of address, to see how full PartitionAlloc's pools (tag 253) get.
static void usage(void) {
  unsigned long long by_tag[16] = {0}, by_q[256] = {0};  // 256 MiB buckets
  vm_address_t addr = 0;
  for (;;) {
    vm_size_t size = 0;
    natural_t depth = 0;
    vm_region_submap_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
    if (vm_region_recurse_64(mach_task_self(), &addr, &size, &depth,
                             (vm_region_recurse_info_t)&info,
                             &count) != KERN_SUCCESS) {
      break;
    }
    if (info.user_tag >= 240) {
      unsigned long long resident =
          (unsigned long long)info.pages_resident * vm_page_size;
      by_tag[info.user_tag - 240] += resident;
      if (info.user_tag == 253 && addr / (GiB / 4) < 256) by_q[addr / (GiB / 4)] += resident;
    }
    addr += size;
  }
  say("vaclamp: resident MiB by tag:");
  for (int i = 0; i < 16; i++)
    if (by_tag[i]) say(" %d=%.0f", 240 + i, by_tag[i] / 1048576.0);
  say("; tag 253 by 256 MiB from (GiB):");
  for (int i = 0; i < 256; i++)
    if (by_q[i]) say(" [%.2f]=%.0f", i / 4.0, by_q[i] / 1048576.0);
  say("\n");
}

static void* dump_later(void* arg) {
  long seconds = (long)arg;
  sleep((unsigned)seconds);
  dump("layout later");
  const char* every = getenv("VACLAMP_USAGE_EVERY");
  long interval = every ? atol(every) : 0;
  usage();
  while (interval > 0) {
    sleep((unsigned)interval);
    usage();
  }
  return NULL;
}

__attribute__((constructor(101))) static void vaclamp(void) {
  const char* log = getenv("VACLAMP_LOG");
  if (log) {
    int fd = open(log, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) g_fd = fd;
  }
  const char* limit_env = getenv("VACLAMP_LIMIT_GIB");
  double limit_gib = limit_env ? atof(limit_env) : 17.375;
  vm_address_t limit = (vm_address_t)(limit_gib * GiB);
  dump("layout before clamping");
  reserve_free(6 * GiB, 12 * GiB);
  reserve_free(limit, TOP);
  release_dyld_reservation(12 * GiB, limit);
  dump("layout after clamping");
  say("vaclamp: address space clamped below %.3f GiB\n", limit_gib);
  const char* every_ms = getenv("VACLAMP_LAYOUT_EVERY_MS");
  if (every_ms && atol(every_ms) > 0) {
    pthread_t t;
    pthread_create(&t, NULL, compact_loop, (void*)atol(every_ms));
    pthread_detach(t);
  }
  const char* after = getenv("VACLAMP_DUMP_AFTER");
  long seconds = after ? atol(after) : 20;
  if (seconds > 0) {
    pthread_t t;
    pthread_create(&t, NULL, dump_later, (void*)seconds);
    pthread_detach(t);
  }
}
