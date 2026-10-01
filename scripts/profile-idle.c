// Development-only passive process sampler. Never linked into PrayBar.
// Build: xcrun clang -O2 -Wall -Wextra scripts/profile-idle.c -o build/profile-idle
// Run:   build/profile-idle PID 300 > build/profiling/MODE.csv
#include <errno.h>
#include <inttypes.h>
#include <libproc.h>
#include <mach/mach_time.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

static double seconds(uint64_t ticks, mach_timebase_info_data_t scale) {
    return (double)ticks * scale.numer / scale.denom / 1e9;
}

int main(int argc, char **argv) {
    char *end;
    if (argc != 3) {
        fprintf(stderr, "Usage: %s PID DURATION_SECONDS\n", argv[0]);
        return 2;
    }
    long pid = strtol(argv[1], &end, 10);
    if (*end || pid <= 0 || pid > INT32_MAX) return 2;
    double duration = strtod(argv[2], &end);
    if (*end || !isfinite(duration) || duration <= 0) return 2;
    mach_timebase_info_data_t scale;
    if (mach_timebase_info(&scale) != KERN_SUCCESS) return 1;
    uint64_t start = mach_absolute_time(), continuousStart = mach_continuous_time();
    uint64_t previousTime = 0, previousCPU = 0, processStart = 0;
    puts("utc,active_seconds,continuous_seconds,cpu_seconds,cpu_percent,footprint_bytes,resident_bytes,interrupt_wakeups,package_idle_wakeups,disk_read_bytes,disk_written_bytes");
    for (;;) {
        struct rusage_info_v2 usage = {0};
        if (proc_pid_rusage((pid_t)pid, RUSAGE_INFO_V2, (rusage_info_t *)&usage) != 0) {
            perror("proc_pid_rusage");
            return 1;
        }
        if (processStart && processStart != usage.ri_proc_start_abstime) {
            fprintf(stderr, "PID was reused; refusing to combine processes\n");
            return 1;
        }
        processStart = usage.ri_proc_start_abstime;
        uint64_t now = mach_absolute_time(), continuous = mach_continuous_time();
        // XNU fills these from task_power_info: Mach ticks, not nanoseconds.
        uint64_t cpu = usage.ri_user_time + usage.ri_system_time;
        double elapsed = seconds(now - start, scale);
        double percent = previousTime ? 100.0 * (double)(cpu - previousCPU) / (now - previousTime) : 0;
        struct timespec wall;
        clock_gettime(CLOCK_REALTIME, &wall);
        struct tm utc;
        gmtime_r(&wall.tv_sec, &utc);
        char stamp[32];
        strftime(stamp, sizeof(stamp), "%Y-%m-%dT%H:%M:%S", &utc);
        printf("%s.%03ldZ,%.6f,%.6f,%.9f,", stamp, wall.tv_nsec / 1000000,
               elapsed, seconds(continuous - continuousStart, scale), seconds(cpu, scale));
        if (previousTime) printf("%.9f", percent); // First row is only a baseline.
        printf(",%" PRIu64 ",%" PRIu64 ",%" PRIu64 ",%" PRIu64 ",%" PRIu64 ",%" PRIu64 "\n",
               usage.ri_phys_footprint, usage.ri_resident_size, usage.ri_interrupt_wkups,
               usage.ri_pkg_idle_wkups, usage.ri_diskio_bytesread, usage.ri_diskio_byteswritten);
        fflush(stdout);
        previousTime = now; previousCPU = cpu;
        if (elapsed >= duration) break;
        double delay = fmin(5.0, duration - elapsed);
        struct timespec wait = { .tv_sec = (time_t)delay,
                                 .tv_nsec = (long)((delay - floor(delay)) * 1e9) };
        while (nanosleep(&wait, &wait) == -1 && errno == EINTR) {}
    }
    return 0;
}
