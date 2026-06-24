// engine_18_device.c - Block devices, partitions & hardware scanner
#include "common.h"
static int write_file_with_name(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
static int dump_cmd(const char *res, const char *name, const char *cmd, char *buf, size_t bufsz) {
    if (run_cmd(cmd, buf, bufsz) < 0 || strlen(buf) < 5) return 0;
    write_file_with_name(res, name, buf); return 1;
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH], buf[65536], sp[MAX_PATH];
    snprintf(res, sizeof(res), "%s/device", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_18.json", outdir); json_start(jsonname);
    int count = 0;
    // Block devices
    DIR *d = opendir("/dev/block"); if (d) {
        struct dirent *e; char dst[MAX_PATH];
        while ((e = readdir(d)) != NULL) {
            if (e->d_name[0] == '.') continue;
            snprintf(sp, sizeof(sp), "/dev/block/%s", e->d_name);
            struct stat st; if (stat(sp, &st) != 0) continue;
            snprintf(dst, sizeof(dst), "%s/block_%s_size_%lld.txt", res, e->d_name, (long long)st.st_size);
            char info[256];
            snprintf(info, sizeof(info), "Device: %s\nSize: %lld\nMajor: %d\nMinor: %d", sp, (long long)st.st_size, major(st.st_rdev), minor(st.st_rdev));
            write_file(dst, info); count++;
        } closedir(d);
    }
    // /proc/partitions
    count += dump_cmd(res, "partitions.txt", "cat /proc/partitions 2>/dev/null || true", buf, sizeof(buf));
    // /proc/diskstats
    count += dump_cmd(res, "diskstats.txt", "cat /proc/diskstats 2>/dev/null || true", buf, sizeof(buf));
    // /proc/mounts
    count += dump_cmd(res, "mounts.txt", "cat /proc/mounts 2>/dev/null || mount 2>/dev/null || true", buf, sizeof(buf));
    // df
    count += dump_cmd(res, "df.txt", "df -h 2>/dev/null || true", buf, sizeof(buf));
    // Hardware info via /sys
    const char *sys_paths[] = {
        "/sys/class/kgsl/kgsl-3d0/gpu_model",
        "/sys/class/kgsl/kgsl-3d0/gpu_speed",
        "/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq",
        "/sys/devices/system/cpu/possible",
        "/sys/class/kgsl/kgsl-3d0/gpubusy",
        NULL
    };
    for (int i = 0; sys_paths[i]; i++) {
        int fd = open(sys_paths[i], O_RDONLY); if (fd < 0) continue;
        int r = read(fd, buf, sizeof(buf) - 1); close(fd);
        if (r > 0) { buf[r] = 0;
            char fn[MAX_PATH]; snprintf(fn, sizeof(fn), "sys_%s.txt", sys_paths[i]);
            char *clean = fn; while (*clean) { if (*clean == '/') *clean = '_'; clean++; }
            write_file_with_name(res, fn, buf); count++; }
    }
    // dumpsys
    count += dump_cmd(res, "dumpsys_display.txt", "dumpsys display 2>/dev/null | head -300 || true", buf, sizeof(buf));
    count += dump_cmd(res, "dumpsys_battery.txt", "dumpsys battery 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "dumpsys_hardware.txt", "dumpsys hardware 2>/dev/null | head -300 || true", buf, sizeof(buf));
    // All /proc/ info
    const char *proc_files[] = {
        "cpuinfo", "meminfo", "version", "uptime",
        "loadavg", "vmstat", "zoneinfo", "slabinfo",
        "iomem", "ioports", "interrupts",
        NULL
    };
    for (int i = 0; proc_files[i]; i++) {
        snprintf(sp, sizeof(sp), "/proc/%s", proc_files[i]);
        char *c = read_file(sp); if (c) {
            snprintf(buf, sizeof(buf), "proc_%s.txt", proc_files[i]);
            write_file_with_name(res, buf, c); count++; free(c); }
    }
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"device\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
