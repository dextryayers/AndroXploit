// engine_10_system.c - Complete system configuration dump
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
    char res[MAX_PATH], jsonname[MAX_PATH], buf[65536];
    snprintf(res, sizeof(res), "%s/system", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_10.json", outdir); json_start(jsonname);
    int count = 0;
    // Build properties
    count += dump_cmd(res, "build_prop.txt", "getprop 2>/dev/null | sort || true", buf, sizeof(buf));
    count += dump_cmd(res, "build_prop_raw.txt", "cat /system/build.prop 2>/dev/null || cat /vendor/build.prop 2>/dev/null || cat /product/build.prop 2>/dev/null || true", buf, sizeof(buf));
    // System files
    const char *sys_files[] = {
        "/system/build.prop", "/vendor/build.prop", "/product/build.prop",
        "/system/etc/hosts", "/system/etc/hosts.times",
        "/proc/version", "/proc/cpuinfo", "/proc/meminfo",
        "/proc/uptime", "/proc/loadavg", "/proc/partitions",
        "/proc/diskstats", "/proc/mounts", "/proc/filesystems",
        "/proc/devices", "/proc/cmdline",
        "/data/system/packages.xml",
        "/data/system/packages.list",
        "/data/system/device_policies.xml",
        "/data/system/appops.xml",
        "/data/system/netstats/",
        "/data/system/users.xml",
        "/data/system/uiderrors.txt",
        "/system/build.spec",
        NULL
    };
    for (int i = 0; sys_files[i]; i++) {
        char dst[MAX_PATH], *l = strrchr(sys_files[i], '/'); l = l ? l + 1 : (char*)sys_files[i];
        snprintf(dst, sizeof(dst), "%s/sys_%s", res, l);
        save_with_root_fallback(sys_files[i], dst);
        if (file_exists(dst) && file_size(dst) > 0) count++;
    }
    // dumpsys
    const char *dumpsys_svcs[] = {
        "android.security.keystore", "batterystats", "diskstats",
        "dropbox", "jobscheduler", "netstats",
        "package", "permission", "power",
        "runtime", "search", "usagestats",
        "wallpaper", "device_policy", "backup",
        NULL
    };
    for (int i = 0; dumpsys_svcs[i]; i++) {
        char cmd[256]; snprintf(cmd, sizeof(cmd), "dumpsys %s 2>/dev/null | head -1000 || true", dumpsys_svcs[i]);
        if (run_cmd(cmd, buf, sizeof(buf)) >= 0 && strlen(buf) > 50) {
            char fn[MAX_PATH]; snprintf(fn, sizeof(fn), "dumpsys_%s.txt", dumpsys_svcs[i]);
            write_file_with_name(res, fn, buf); count++; }
    }
    // /system directory listing
    run_cmd("ls -laR /system/ 2>/dev/null | head -5000 || true", buf, sizeof(buf));
    if (strlen(buf) > 100) { write_file_with_name(res, "system_dir_listing.txt", buf); count++; }
    // SELinux
    run_cmd("cat /proc/self/attr/current 2>/dev/null || echo 'unknown'", buf, sizeof(buf));
    if (strlen(buf) > 2) { write_file_with_name(res, "selinux_context.txt", buf); count++; }
    // Full settings dump
    count += dump_cmd(res, "settings_global.txt", "settings list global 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "settings_secure.txt", "settings list secure 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "settings_system.txt", "settings list system 2>/dev/null || true", buf, sizeof(buf));
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"system\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
