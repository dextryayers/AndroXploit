// engine_01_imei.c - IMEI/MEID/Radio extraction
#include "common.h"
static int write_in(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
static void scan_proc_radio(const char *base, const char *outdir) {
    DIR *d = opendir(base); if (!d) return;
    struct dirent *e; char sp[MAX_PATH], dp[MAX_PATH];
    snprintf(dp, sizeof(dp), "%s/imei", outdir); mkdir_p(dp);
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.') { continue; }
        snprintf(sp, sizeof(sp), "%s/%s", base, e->d_name);
        char buf[256]; int fd = open(sp, O_RDONLY);
        if (fd < 0) { continue; }
        int r = read(fd, buf, 255); close(fd);
        if (r > 0) { buf[r] = 0; char op[512]; snprintf(op, sizeof(op), "%s/%s.txt", dp, e->d_name); write_file(op, buf); }
    } closedir(d);
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH], buf[65536];
    snprintf(res, sizeof(res), "%s/imei", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_01.json", outdir); json_start(jsonname);
    int count = 0;
    struct { const char *cmd; const char *fn; } props[] = {
        {"getprop ro.ril.oem.imei1 2>/dev/null || true", "imei_oem1.txt"},
        {"getprop ro.ril.oem.imei2 2>/dev/null || true", "imei_oem2.txt"},
        {"getprop ro.phone.imei 2>/dev/null || true", "phone_imei.txt"},
        {"getprop gsm.baseband.imei 2>/dev/null || true", "baseband_imei.txt"},
        {"getprop ril.imei 2>/dev/null || true", "ril_imei.txt"},
        {"getprop persist.radio.imei 2>/dev/null || true", "persist_imei.txt"},
        {"getprop ro.serialno 2>/dev/null || true", "serialno.txt"},
        {"dumpsys iphonesubinfo 2>/dev/null | head -100 || true", "iphonesubinfo.txt"},
        {"settings get secure android_id 2>/dev/null || true", "android_id.txt"},
        {NULL, NULL}
    };
    for (int i = 0; props[i].cmd; i++) {
        if (run_cmd(props[i].cmd, buf, sizeof(buf)) >= 0 && strlen(buf) > 2) {
            write_in(res, props[i].fn, buf); count++;
        }
    }
    scan_proc_radio("/proc/radio", res);
    count += count_dir(res);
    for (int i = 1; i <= 5; i++) {
        char cmd[128]; snprintf(cmd, sizeof(cmd), "service call radio %d 2>/dev/null || true", i);
        if (run_cmd(cmd, buf, sizeof(buf)) >= 0 && strlen(buf) > 5) {
            char fn[64]; snprintf(fn, sizeof(fn), "service_radio_%d.txt", i);
            write_in(res, fn, buf); count++;
        }
    }
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"imei\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
