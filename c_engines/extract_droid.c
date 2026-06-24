/*
 * extract_droid.c — Single binary universal Android extraction engine
 * 
 * One binary, 15+ extraction modules. Compile once, push to device, run all.
 * 
 * Compile (NDK):  aarch64-linux-android21-clang -Os -fPIE -static -o extract_droid extract_droid.c -lz
 * Compile (host): gcc -Os -o extract_droid extract_droid.c -lz -DTARGET_HOST
 * Run:            extract_droid <outdir> [--all|--imei|--contacts|--sms|--wifi|--whatsapp|
 *                                       --files|--sqlite|--system|--proc|--packages|--media|
 *                                       --backup|--accounts|--network|--browser]
 *
 * Output: JSON to stdout + files in <outdir>
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <time.h>
#include <errno.h>
#include <ctype.h>
#include <pwd.h>
#include <grp.h>
#include <libgen.h>

/* ================================================================
 *  UTILITY FUNCTIONS
 * ================================================================ */

#define MAX_PATH 4096
#define MAX_ENTRIES 200000
#define OUT_BUF 65536

static int _mkdir_p(const char *path) {
    char tmp[MAX_PATH];
    char *p;
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            mkdir(tmp, 0755);
            *p = '/';
        }
    }
    mkdir(tmp, 0755);
    return 0;
}

static char *_read_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    if (len > 10485760) { fclose(f); return NULL; } /* skip >10MB */
    fseek(f, 0, SEEK_SET);
    char *buf = malloc(len + 1);
    if (!buf) { fclose(f); return NULL; }
    size_t r = fread(buf, 1, len, f);
    buf[r] = 0;
    fclose(f);
    return buf;
}

static int _write_file(const char *path, const char *content) {
    FILE *f = fopen(path, "w");
    if (!f) return -1;
    if (content) fputs(content, f);
    fclose(f);
    return 0;
}

static int _write_file_bin(const char *path, const char *data, size_t len) {
    FILE *f = fopen(path, "wb");
    if (!f) return -1;
    fwrite(data, 1, len, f);
    fclose(f);
    return 0;
}

static int _copy_file(const char *src, const char *dst) {
    char *data = _read_file(src);
    if (!data) return -1;
    int r = _write_file(dst, data);
    free(data);
    return r;
}

static int _file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0;
}

static long long _file_size(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    return (long long)st.st_size;
}

static void _sanitize_path(char *p) {
    for (; *p; p++) if (*p == '/' || *p == '\\') *p = '_';
}

/* Find string in multi-line text */
static int _contains(const char *haystack, const char *needle) {
    return haystack && strstr(haystack, needle) != NULL;
}

/* Simple JSON output helpers */
static FILE *_json_fp = NULL;
static int _json_first = 0;

static void _json_open(const char *path) {
    _json_fp = fopen(path, "w");
    if (!_json_fp) return;
    fprintf(_json_fp, "{\n");
    _json_first = 1;
}

static void _json_kv(const char *key, const char *val) {
    if (!_json_fp) return;
    if (!_json_first) fprintf(_json_fp, ",\n"); else _json_first = 0;
    fprintf(_json_fp, "  \"%s\": \"%s\"", key, val ? val : "");
    fflush(_json_fp);
}

static void _json_ki(const char *key, long long val) {
    if (!_json_fp) return;
    if (!_json_first) fprintf(_json_fp, ",\n"); else _json_first = 0;
    fprintf(_json_fp, "  \"%s\": %lld", key, val);
    fflush(_json_fp);
}

static void _json_close(void) {
    if (!_json_fp) return;
    fprintf(_json_fp, "\n}\n");
    fclose(_json_fp);
    _json_fp = NULL;
}

/* ================================================================
 *  MODULE: IMEI / DEVICE INFO
 * ================================================================ */

static int module_imei(const char *outdir) {
    char subdir[MAX_PATH];
    snprintf(subdir, sizeof(subdir), "%s/imei", outdir);
    _mkdir_p(subdir);

    /* Read IMEI-related properties */
    const char *props[] = {
        "ro.imei", "ro.ril.miui.network.imei", "gsm.baseband.imei",
        "ril.imei", "ro.ril.oem.imei", "persist.radio.imei",
        "ro.build.version.release", "ro.build.version.sdk",
        "ro.product.model", "ro.product.manufacturer",
        "ro.serialno", "ro.build.fingerprint",
        "ro.hardware", "ro.bootloader",
        "persist.sys.timezone",
        NULL
    };
    int count = 0;
    for (int i = 0; props[i]; i++) {
        char cmd[MAX_PATH * 2];
        char outpath[MAX_PATH];
        snprintf(cmd, sizeof(cmd), "getprop %s 2>/dev/null", props[i]);
        FILE *fp = popen(cmd, "r");
        if (!fp) continue;
        char buf[4096] = {0};
        if (fgets(buf, sizeof(buf), fp)) {
            char *nl = strchr(buf, '\n');
            if (nl) *nl = 0;
            if (strlen(buf) > 0) {
                snprintf(outpath, sizeof(outpath), "%s/prop_%s.txt", subdir, props[i]);
                _write_file(outpath, buf);
                count++;
            }
        }
        pclose(fp);
    }

    /* CPU/Memory info */
    const char *info_files[] = {
        "/proc/cpuinfo", "/proc/meminfo", "/proc/version",
        "/proc/cmdline", "/proc/uptime",
        NULL
    };
    for (int i = 0; info_files[i]; i++) {
        char *data = _read_file(info_files[i]);
        if (data) {
            char outpath[MAX_PATH];
            const char *name = strrchr(info_files[i], '/');
            name = name ? name + 1 : info_files[i];
            snprintf(outpath, sizeof(outpath), "%s/%s", subdir, name);
            _write_file(outpath, data);
            count++;
            free(data);
        }
    }

    /* /dev/block listing */
    DIR *d = opendir("/dev/block");
    if (d) {
        char outpath[MAX_PATH];
        snprintf(outpath, sizeof(outpath), "%s/block_devices.txt", subdir);
        FILE *out = fopen(outpath, "w");
        if (out) {
            struct dirent *e;
            while ((e = readdir(d)) != NULL) {
                if (e->d_name[0] == '.') continue;
                char full[MAX_PATH];
                snprintf(full, sizeof(full), "/dev/block/%s", e->d_name);
                struct stat st;
                if (lstat(full, &st) == 0)
                    fprintf(out, "%s  size=%lld  mode=%o\n",
                            e->d_name, (long long)st.st_size, st.st_mode & 07777);
            }
            fclose(out);
            count++;
        }
        closedir(d);
    }

    return count;
}

/* ================================================================
 *  MODULE: COMMUNICATIONS (SMS/Contacts/Call Log)
 * ================================================================ */

static int module_communications(const char *outdir) {
    char subdir[MAX_PATH];
    snprintf(subdir, sizeof(subdir), "%s/communications", outdir);
    _mkdir_p(subdir);

    /* Use content providers directly (works without root) */
    const char *queries[] = {
        "content query --uri content://sms/inbox --projection address:date:body",
        "content query --uri content://sms/sent --projection address:date:body",
        "content query --uri content://sms/draft --projection address:date:body",
        "content query --uri content://mms --projection _id:date:sub",
        "content query --uri content://contacts/phones/ --projection display_name:data1",
        "content query --uri content://call_log/calls --projection number:date:duration:type",
        NULL
    };
    const char *names[] = {
        "sms_inbox.txt", "sms_sent.txt", "sms_drafts.txt",
        "mms.txt", "contacts.txt", "call_log.txt"
    };

    int count = 0;
    for (int i = 0; queries[i]; i++) {
        char cmd[MAX_PATH * 2];
        snprintf(cmd, sizeof(cmd), "%s 2>/dev/null || true", queries[i]);
        FILE *fp = popen(cmd, "r");
        if (!fp) continue;
        char buf[65536];
        size_t total = 0;
        char *out = malloc(OUT_BUF);
        if (!out) { pclose(fp); continue; }
        out[0] = 0;
        while (fgets(buf, sizeof(buf), fp) && total < OUT_BUF - 4096) {
            size_t blen = strlen(buf);
            if (total + blen < OUT_BUF - 1) {
                memcpy(out + total, buf, blen);
                total += blen;
                out[total] = 0;
            }
        }
        pclose(fp);
        if (total > 10) {
            char outpath[MAX_PATH];
            snprintf(outpath, sizeof(outpath), "%s/%s", subdir, names[i]);
            _write_file(outpath, out);
            count++;
        }
        free(out);
    }

    /* Also try dumpsys telecom for call info */
    FILE *fp = popen("dumpsys telecom 2>/dev/null | head -200 || true", "r");
    if (fp) {
        char buf[65536];
        size_t r = fread(buf, 1, sizeof(buf) - 1, fp);
        buf[r] = 0;
        pclose(fp);
        if (r > 50) {
            char outpath[MAX_PATH];
            snprintf(outpath, sizeof(outpath), "%s/telecom.txt", subdir);
            _write_file(outpath, buf);
            count++;
        }
    }

    return count;
}

/* ================================================================
 *  MODULE: SYSTEM INFO
 * ================================================================ */

static int module_system(const char *outdir) {
    char subdir[MAX_PATH];
    snprintf(subdir, sizeof(subdir), "%s/system", outdir);
    _mkdir_p(subdir);
    int count = 0;

    /* getprop */
    FILE *fp = popen("getprop 2>/dev/null || true", "r");
    if (fp) {
        char buf[OUT_BUF];
        size_t r = fread(buf, 1, sizeof(buf) - 1, fp);
        buf[r] = 0;
        pclose(fp);
        if (r > 10) {
            char op[MAX_PATH];
            snprintf(op, sizeof(op), "%s/all_props.txt", subdir);
            _write_file(op, buf);
            count++;
        }
    }

    /* settings */
    const char *namespaces[] = {"system", "secure", "global", NULL};
    for (int i = 0; namespaces[i]; i++) {
        char cmd[MAX_PATH];
        snprintf(cmd, sizeof(cmd), "settings list %s 2>/dev/null || true", namespaces[i]);
        fp = popen(cmd, "r");
        if (!fp) continue;
        char buf[OUT_BUF];
        size_t r = fread(buf, 1, sizeof(buf) - 1, fp);
        buf[r] = 0;
        pclose(fp);
        if (r > 10) {
            char op[MAX_PATH];
            snprintf(op, sizeof(op), "%s/settings_%s.txt", subdir, namespaces[i]);
            _write_file(op, buf);
            count++;
        }
    }

    /* /proc files */
    const char *procs[] = {
        "cpuinfo", "meminfo", "mounts", "partitions",
        "diskstats", "devices", "filesystems", "loadavg",
        "stat", "uptime", "version",
        NULL
    };
    for (int i = 0; procs[i]; i++) {
        char p[MAX_PATH];
        snprintf(p, sizeof(p), "/proc/%s", procs[i]);
        char *data = _read_file(p);
        if (data) {
            char op[MAX_PATH];
            snprintf(op, sizeof(op), "%s/proc_%s", subdir, procs[i]);
            _write_file(op, data);
            count++;
            free(data);
        }
    }

    /* dumpsys services */
    const char *svcs[] = {
        "battery", "connectivity", "netstats", "package",
        "window", "power", "alarm", "location", "activity",
        "diskstats", "wifi", "bluetooth_manager",
        "telephony.registry", "iphonesubinfo",
        "appops", "permission", "notification",
        NULL
    };
    for (int i = 0; svcs[i]; i++) {
        char cmd[MAX_PATH];
        snprintf(cmd, sizeof(cmd), "dumpsys %s 2>/dev/null | head -500 || true", svcs[i]);
        fp = popen(cmd, "r");
        if (!fp) continue;
        char buf[OUT_BUF];
        size_t r = fread(buf, 1, sizeof(buf) - 1, fp);
        buf[r] = 0;
        pclose(fp);
        if (r > 100) {
            char op[MAX_PATH];
            snprintf(op, sizeof(op), "%s/dumpsys_%s.txt", subdir, svcs[i]);
            _write_file(op, buf);
            count++;
        }
    }

    return count;
}

/* ================================================================
 *  MODULE: PACKAGES / APKs
 * ================================================================ */

static int module_packages(const char *outdir) {
    char subdir[MAX_PATH];
    snprintf(subdir, sizeof(subdir), "%s/apks", outdir);
    _mkdir_p(subdir);
    int count = 0;

    /* pm list packages */
    FILE *fp = popen("pm list packages -f 2>/dev/null || pm list packages 2>/dev/null || true", "r");
    if (fp) {
        char buf[OUT_BUF];
        size_t r = fread(buf, 1, sizeof(buf) - 1, fp);
        buf[r] = 0;
        pclose(fp);
        if (r > 10) {
            char op[MAX_PATH];
            snprintf(op, sizeof(op), "%s/packages.txt", subdir);
            _write_file(op, buf);
            count++;
        }
    }

    /* List APK directories */
    const char *apk_dirs[] = {
        "/data/app/", "/system/app/", "/system/priv-app/",
        "/product/app/", "/vendor/app/",
        NULL
    };
    for (int i = 0; apk_dirs[i]; i++) {
        DIR *d = opendir(apk_dirs[i]);
        if (!d) continue;
        char op[MAX_PATH];
        snprintf(op, sizeof(op), "%s/apk_dir_%s.txt", subdir,
                 apk_dirs[i] + 1 + (apk_dirs[i][1] == '/' ? 0 : 0));
        /* sanitize name */
        for (char *p = op + strlen(subdir) + 9; *p; p++)
            if (*p == '/') *p = '_';
        FILE *out = fopen(op, "w");
        if (!out) { closedir(d); continue; }
        struct dirent *e;
        while ((e = readdir(d)) != NULL) {
            if (e->d_name[0] == '.') continue;
            char full[MAX_PATH];
            snprintf(full, sizeof(full), "%s%s", apk_dirs[i], e->d_name);
            struct stat st;
            if (lstat(full, &st) == 0)
                fprintf(out, "%s\t%lld\t%o\n", full, (long long)st.st_size, st.st_mode & 07777);
        }
        fclose(out);
        closedir(d);
        count++;
    }

    return count;
}

/* ================================================================
 *  MODULE: MEDIA SCANNER
 * ================================================================ */

static int is_media_ext(const char *name) {
    const char *e = strrchr(name, '.');
    if (!e) return 0;
    const char *exts[] = {
        ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp",
        ".mp4", ".mkv", ".3gp", ".webm", ".avi", ".mov",
        ".mp3", ".wav", ".aac", ".ogg", ".flac", ".m4a",
        NULL
    };
    for (int i = 0; exts[i]; i++)
        if (strcasecmp(e, exts[i]) == 0) return 1;
    return 0;
}

static int scan_media_dir(const char *dirpath, FILE *img, FILE *vid, FILE *aud, int depth) {
    if (depth > 8) return 0;
    DIR *d = opendir(dirpath);
    if (!d) return 0;
    int count = 0;
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.') continue;
        char full[MAX_PATH];
        snprintf(full, sizeof(full), "%s/%s", dirpath, e->d_name);
        struct stat st;
        if (lstat(full, &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) {
            count += scan_media_dir(full, img, vid, aud, depth + 1);
        } else if (S_ISREG(st.st_mode)) {
            const char *ext = strrchr(e->d_name, '.');
            if (!ext) continue;
            struct tm *tm = localtime(&st.st_mtime);
            char tb[32];
            strftime(tb, sizeof(tb), "%Y-%m-%d %H:%M:%S", tm);

            if (strcasecmp(ext, ".jpg") == 0 || strcasecmp(ext, ".jpeg") == 0 ||
                strcasecmp(ext, ".png") == 0 || strcasecmp(ext, ".gif") == 0 ||
                strcasecmp(ext, ".bmp") == 0 || strcasecmp(ext, ".webp") == 0) {
                fprintf(img, "%s\t%lld\t%s\n", full, (long long)st.st_size, tb);
                count++;
            } else if (strcasecmp(ext, ".mp4") == 0 || strcasecmp(ext, ".mkv") == 0 ||
                       strcasecmp(ext, ".3gp") == 0 || strcasecmp(ext, ".webm") == 0 ||
                       strcasecmp(ext, ".avi") == 0 || strcasecmp(ext, ".mov") == 0) {
                fprintf(vid, "%s\t%lld\t%s\n", full, (long long)st.st_size, tb);
                count++;
            } else if (strcasecmp(ext, ".mp3") == 0 || strcasecmp(ext, ".wav") == 0 ||
                       strcasecmp(ext, ".aac") == 0 || strcasecmp(ext, ".ogg") == 0 ||
                       strcasecmp(ext, ".flac") == 0 || strcasecmp(ext, ".m4a") == 0) {
                fprintf(aud, "%s\t%lld\t%s\n", full, (long long)st.st_size, tb);
                count++;
            }
        }
    }
    closedir(d);
    return count;
}

static int module_media(const char *outdir) {
    char subdir[MAX_PATH];
    snprintf(subdir, sizeof(subdir), "%s/media", outdir);
    _mkdir_p(subdir);

    char ipath[MAX_PATH], vpath[MAX_PATH], apath[MAX_PATH];
    snprintf(ipath, sizeof(ipath), "%s/images.txt", subdir);
    snprintf(vpath, sizeof(vpath), "%s/videos.txt", subdir);
    snprintf(apath, sizeof(apath), "%s/audio.txt", subdir);

    FILE *img = fopen(ipath, "w");
    FILE *vid = fopen(vpath, "w");
    FILE *aud = fopen(apath, "w");
    if (!img || !vid || !aud) {
        if (img) fclose(img);
        if (vid) fclose(vid);
        if (aud) fclose(aud);
        return 0;
    }

    fprintf(img, "# Path\tSize\tDate\n");
    fprintf(vid, "# Path\tSize\tDate\n");
    fprintf(aud, "# Path\tSize\tDate\n");

    const char *targets[] = {
        "/sdcard/DCIM", "/sdcard/Pictures", "/sdcard/Movies",
        "/sdcard/Music", "/sdcard/Download", "/sdcard/WhatsApp/Media",
        "/sdcard/Telegram", "/sdcard/Android/media",
        NULL
    };
    int total = 0;
    for (int t = 0; targets[t]; t++) {
        total += scan_media_dir(targets[t], img, vid, aud, 0);
    }

    fclose(img); fclose(vid); fclose(aud);
    return total;
}

/* ================================================================
 *  MODULE: FULL BACKUP
 * ================================================================ */

static int module_backup(const char *outdir) {
    char subdir[MAX_PATH];
    snprintf(subdir, sizeof(subdir), "%s/backup", outdir);
    _mkdir_p(subdir);

    char filelist[MAX_PATH];
    snprintf(filelist, sizeof(filelist), "%s/filelist.txt", subdir);
    FILE *fl = fopen(filelist, "w");
    if (!fl) return 0;

    /* Walk /sdcard/ and write file list */
    int total_files = 0;
    long long total_bytes = 0;

    /* Use find command if available, much faster */
    FILE *fp = popen("find /sdcard/ -type f 2>/dev/null | head -200000 || true", "r");
    if (fp) {
        char buf[MAX_PATH];
        while (fgets(buf, sizeof(buf), fp)) {
            char *nl = strchr(buf, '\n');
            if (nl) *nl = 0;
            if (strlen(buf) == 0) continue;
            fprintf(fl, "%s\n", buf);
            total_files++;
            struct stat st;
            if (stat(buf, &st) == 0) total_bytes += st.st_size;
        }
        pclose(fp);
    }

    fclose(fl);

    /* Write summary */
    char sumpath[MAX_PATH];
    snprintf(sumpath, sizeof(sumpath), "%s/summary.txt", subdir);
    char sumbuf[4096];
    snprintf(sumbuf, sizeof(sumbuf),
        "Total files: %d\nTotal bytes: %lld\n",
        total_files, total_bytes);
    _write_file(sumpath, sumbuf);

    /* DF output */
    fp = popen("df -h /sdcard 2>/dev/null || true", "r");
    if (fp) {
        char dfbuf[4096];
        size_t r = fread(dfbuf, 1, sizeof(dfbuf) - 1, fp);
        dfbuf[r] = 0;
        pclose(fp);
        if (r > 10) {
            char dfpath[MAX_PATH];
            snprintf(dfpath, sizeof(dfpath), "%s/disk_free.txt", subdir);
            _write_file(dfpath, dfbuf);
        }
    }

    return total_files;
}

/* ================================================================
 *  MODULE: HIDDEN FILES
 * ================================================================ */

static int module_hidden(const char *outdir) {
    char subdir[MAX_PATH];
    snprintf(subdir, sizeof(subdir), "%s/hidden", outdir);
    _mkdir_p(subdir);

    char hp[MAX_PATH];
    snprintf(hp, sizeof(hp), "%s/hidden_files.txt", subdir);
    FILE *hf = fopen(hp, "w");
    if (!hf) return 0;

    int count = 0;
    fprintf(hf, "# Hidden / notable files\n\n");

    /* Find hidden files (starting with .) */
    FILE *fp = popen("find /sdcard/ -name '.*' -type f 2>/dev/null | head -1000 || true", "r");
    if (fp) {
        char buf[MAX_PATH];
        while (fgets(buf, sizeof(buf), fp)) {
            char *nl = strchr(buf, '\n');
            if (nl) *nl = 0;
            if (strlen(buf) > 0) {
                fprintf(hf, "%s\n", buf);
                count++;
            }
        }
        pclose(fp);
    }

    /* Large files >50MB */
    fprintf(hf, "\n# Large files (>50MB)\n");
    fp = popen("find /sdcard/ -type f -size +50M 2>/dev/null | head -500 || true", "r");
    if (fp) {
        char buf[MAX_PATH];
        while (fgets(buf, sizeof(buf), fp)) {
            char *nl = strchr(buf, '\n');
            if (nl) *nl = 0;
            if (strlen(buf) > 0) {
                fprintf(hf, "%s\n", buf);
                count++;
            }
        }
        pclose(fp);
    }

    /* Backup/token files */
    fprintf(hf, "\n# Potential backup/key files\n");
    fp = popen("find /sdcard/ \\( -name '*.backup' -o -name '*.key' -o -name '*.token' -o -name '*.pem' -o -name '*password*' -o -name '*.vault' \\) -type f 2>/dev/null | head -500 || true", "r");
    if (fp) {
        char buf[MAX_PATH];
        while (fgets(buf, sizeof(buf), fp)) {
            char *nl = strchr(buf, '\n');
            if (nl) *nl = 0;
            if (strlen(buf) > 0) {
                fprintf(hf, "%s\n", buf);
                count++;
            }
        }
        pclose(fp);
    }

    fclose(hf);
    return count;
}

/* ================================================================
 *  MODULE: PROCESS SCANNER
 * ================================================================ */

static int module_proc(const char *outdir) {
    char subdir[MAX_PATH];
    snprintf(subdir, sizeof(subdir), "%s/proc", outdir);
    _mkdir_p(subdir);

    char pp[MAX_PATH];
    snprintf(pp, sizeof(pp), "%s/processes.txt", subdir);
    FILE *pf = fopen(pp, "w");
    if (!pf) return 0;

    fprintf(pf, "%-8s %-5s %-30s %-10s %s\n", "PID", "STATE", "NAME", "RSS(KB)", "CMDLINE");
    fprintf(pf, "%.*s\n", 100, "----------------------------------------------------------------------------------------------------");

    DIR *d = opendir("/proc");
    if (!d) { fclose(pf); return 0; }

    int count = 0;
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        if (e->d_type != DT_DIR) continue;
        if (!isdigit(e->d_name[0])) continue;
        pid_t pid = atoi(e->d_name);

        char spath[MAX_PATH];
        snprintf(spath, sizeof(spath), "/proc/%d/status", pid);
        char *status = _read_file(spath);
        if (!status) continue;

        /* Extract name */
        char *name_str = strstr(status, "Name:");
        char name[256] = "?";
        if (name_str) {
            char *p = name_str + 5;
            while (*p == ' ' || *p == '\t') p++;
            char *nl = strchr(p, '\n');
            if (nl) *nl = 0;
            strncpy(name, p, sizeof(name) - 1);
        }

        /* Extract state */
        char state = '?';
        char *st_str = strstr(status, "State:");
        if (st_str) {
            char *p = st_str + 6;
            while (*p == ' ' || *p == '\t') p++;
            state = *p;
        }

        /* Extract RSS */
        long rss = -1;
        char *vm = strstr(status, "VmRSS:");
        if (vm) {
            char *p = vm + 6;
            while (*p == ' ' || *p == '\t') p++;
            rss = atol(p);
        }
        free(status);

        /* Get cmdline */
        char clpath[MAX_PATH];
        snprintf(clpath, sizeof(clpath), "/proc/%d/cmdline", pid);
        char *cmdline = _read_file(clpath);
        char cmd_disp[512] = "";
        if (cmdline) {
            strncpy(cmd_disp, cmdline, sizeof(cmd_disp) - 1);
            for (char *p = cmd_disp; *p; p++)
                if (*p == 0) *p = ' ';
            free(cmdline);
        }

        fprintf(pf, "%-8d %-5c %-30s %-10ld %s\n", pid, state, name, rss, cmd_disp);
        count++;
    }
    closedir(d);
    fclose(pf);

    return count;
}

/* ================================================================
 *  MODULE: NETWORK INFO
 * ================================================================ */

static int module_network(const char *outdir) {
    char subdir[MAX_PATH];
    snprintf(subdir, sizeof(subdir), "%s/network", outdir);
    _mkdir_p(subdir);
    int count = 0;

    const char *proc_net[] = {
        "/proc/net/arp", "/proc/net/dev", "/proc/net/route",
        "/proc/net/tcp", "/proc/net/tcp6", "/proc/net/udp",
        "/proc/net/udp6", "/proc/net/unix", "/proc/net/netstat",
        "/proc/net/wireless", "/proc/net/if_inet6",
        NULL
    };
    for (int i = 0; proc_net[i]; i++) {
        char *data = _read_file(proc_net[i]);
        if (data) {
            char op[MAX_PATH];
            const char *name = strrchr(proc_net[i], '/');
            name = name ? name + 1 : proc_net[i];
            snprintf(op, sizeof(op), "%s/%s", subdir, name);
            _write_file(op, data);
            count++;
            free(data);
        }
    }

    /* Network interfaces via /sys/class/net/ */
    char ipath[MAX_PATH];
    snprintf(ipath, sizeof(ipath), "%s/interfaces.txt", subdir);
    FILE *if_out = fopen(ipath, "w");
    if (if_out) {
        DIR *nd = opendir("/sys/class/net");
        if (nd) {
            struct dirent *ne;
            while ((ne = readdir(nd)) != NULL) {
                if (ne->d_name[0] == '.') continue;
                fprintf(if_out, "Interface: %s\n", ne->d_name);
                char syspath[MAX_PATH];
                snprintf(syspath, sizeof(syspath), "/sys/class/net/%s/address", ne->d_name);
                char *mac = _read_file(syspath);
                if (mac) { fprintf(if_out, "  MAC: %s", mac); free(mac); }
                snprintf(syspath, sizeof(syspath), "/sys/class/net/%s/operstate", ne->d_name);
                char *state = _read_file(syspath);
                if (state) { fprintf(if_out, "  State: %s", state); free(state); }
                snprintf(syspath, sizeof(syspath), "/sys/class/net/%s/speed", ne->d_name);
                char *speed = _read_file(syspath);
                if (speed) { fprintf(if_out, "  Speed: %s", speed); free(speed); }
                fprintf(if_out, "\n");
            }
            closedir(nd);
            count++;
        }
        fclose(if_out);
    }

    return count;
}

/* ================================================================
 *  MODULE: USER DATA (list /sdcard/)
 * ================================================================ */

static int module_userdata(const char *outdir) {
    char subdir[MAX_PATH];
    snprintf(subdir, sizeof(subdir), "%s/userdata", outdir);
    _mkdir_p(subdir);

    char lp[MAX_PATH];
    snprintf(lp, sizeof(lp), "%s/sdcard_listing.txt", subdir);
    FILE *lf = fopen(lp, "w");
    if (!lf) return 0;

    int total = 0;
    long long bytes = 0;

    /* List top-level dirs */
    FILE *fp = popen("ls -la /sdcard/ 2>/dev/null || true", "r");
    if (fp) {
        char buf[4096];
        while (fgets(buf, sizeof(buf), fp)) fputs(buf, lf);
        pclose(fp);
    }

    /* Count all files */
    fprintf(lf, "\n\n=== File count by type ===\n");
    fp = popen("find /sdcard/ -type f 2>/dev/null | wc -l", "r");
    if (fp) {
        char buf[256];
        if (fgets(buf, sizeof(buf), fp)) {
            fprintf(lf, "Total files: %s", buf);
            total = atoi(buf);
        }
        pclose(fp);
    }

    /* Disk usage */
    fprintf(lf, "\n=== Disk Usage ===\n");
    fp = popen("du -sh /sdcard/*/ 2>/dev/null | sort -rh | head -30 || true", "r");
    if (fp) {
        char buf[4096];
        while (fgets(buf, sizeof(buf), fp)) fputs(buf, lf);
        pclose(fp);
    }

    fclose(lf);

    /* Also copy download dir listing */
    fp = popen("ls -laR /sdcard/Download/ 2>/dev/null | head -500 || true", "r");
    if (fp) {
        char buf[OUT_BUF];
        size_t r = fread(buf, 1, sizeof(buf) - 1, fp);
        buf[r] = 0;
        pclose(fp);
        if (r > 10) {
            char dp[MAX_PATH];
            snprintf(dp, sizeof(dp), "%s/download_listing.txt", subdir);
            _write_file(dp, buf);
        }
    }

    return total;
}

/* ================================================================
 *  MODULE: BROWSER
 * ================================================================ */

static void scan_browser_db_dir(const char *db_dir, const char *outdir, const char *bname) {
    DIR *d = opendir(db_dir);
    if (!d) return;
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.') continue;
        if (!strstr(e->d_name, ".db") && !strstr(e->d_name, ".sqlite")) continue;
        char full[MAX_PATH];
        snprintf(full, sizeof(full), "%s/%s", db_dir, e->d_name);
        char op[MAX_PATH];
        snprintf(op, sizeof(op), "%s/%s_%s", outdir, bname, e->d_name);
        _copy_file(full, op);
    }
    closedir(d);
}

static int module_browser(const char *outdir) {
    char subdir[MAX_PATH];
    snprintf(subdir, sizeof(subdir), "%s/browser", outdir);
    _mkdir_p(subdir);

    const char *browsers[] = {
        "com.android.chrome", "Chrome",
        "org.mozilla.firefox", "Firefox",
        "com.brave.browser", "Brave",
        "com.microsoft.emmx", "Edge",
        "com.duckduckgo.mobile.android", "DuckDuckGo",
        "com.opera.browser", "Opera",
        "com.vivaldi.browser", "Vivaldi",
        "com.kiwibrowser.browser", "Kiwi",
        NULL
    };

    int found = 0;
    for (int i = 0; browsers[i]; i += 2) {
        const char *pkg = browsers[i];
        const char *name = browsers[i + 1];

        char db_path[MAX_PATH];
        snprintf(db_path, sizeof(db_path), "/data/data/%s/databases", pkg);
        if (!_file_exists(db_path)) {
            snprintf(db_path, sizeof(db_path), "/data/user/0/%s/databases", pkg);
            if (!_file_exists(db_path)) continue;
        }

        char bp[MAX_PATH];
        snprintf(bp, sizeof(bp), "%s/%s", subdir, name);
        _mkdir_p(bp);
        scan_browser_db_dir(db_path, bp, name);

        /* Try shared_prefs */
        char prefs_path[MAX_PATH];
        snprintf(prefs_path, sizeof(prefs_path), "%s/../shared_prefs", db_path);
        DIR *pd = opendir(prefs_path);
        if (pd) {
            struct dirent *e;
            while ((e = readdir(pd)) != NULL) {
                if (e->d_name[0] == '.') continue;
                char full[MAX_PATH];
                snprintf(full, sizeof(full), "%s/%s", prefs_path, e->d_name);
                char op[MAX_PATH];
                snprintf(op, sizeof(op), "%s/%s_%s", bp, name, e->d_name);
                _copy_file(full, op);
            }
            closedir(pd);
        }
        found++;
    }

    /* Also scan /sdcard/ for browser data */
    FILE *fp = popen("find /sdcard/ -maxdepth 3 -name 'Bookmarks' -o -name 'bookmarks.html' -o -name 'history.db' 2>/dev/null | head -100 || true", "r");
    if (fp) {
        char buf[4096];
        size_t r = fread(buf, 1, sizeof(buf) - 1, fp);
        buf[r] = 0;
        pclose(fp);
        if (r > 10) {
            char op[MAX_PATH];
            snprintf(op, sizeof(op), "%s/sdcard_browser_data.txt", subdir);
            _write_file(op, buf);
        }
    }

    return found;
}

/* ================================================================
 *  MODULE: ACCOUNTS
 * ================================================================ */

static int module_accounts(const char *outdir) {
    char subdir[MAX_PATH];
    snprintf(subdir, sizeof(subdir), "%s/accounts", outdir);
    _mkdir_p(subdir);
    int count = 0;

    /* dumpsys account */
    FILE *fp = popen("dumpsys account 2>/dev/null | head -500 || true", "r");
    if (fp) {
        char buf[OUT_BUF];
        size_t r = fread(buf, 1, sizeof(buf) - 1, fp);
        buf[r] = 0;
        pclose(fp);
        if (r > 50) {
            char op[MAX_PATH];
            snprintf(op, sizeof(op), "%s/accounts.txt", subdir);
            _write_file(op, buf);
            count++;
        }
    }

    /* dumpsys user */
    fp = popen("pm list users 2>/dev/null || true", "r");
    if (fp) {
        char buf[OUT_BUF];
        size_t r = fread(buf, 1, sizeof(buf) - 1, fp);
        buf[r] = 0;
        pclose(fp);
        if (r > 10) {
            char op[MAX_PATH];
            snprintf(op, sizeof(op), "%s/users.txt", subdir);
            _write_file(op, buf);
            count++;
        }
    }

    /* WiFi info via cmd/wifi dumpsys */
    fp = popen("dumpsys wifi 2>/dev/null | grep -E 'SSID|ssid|Key|PreSharedKey|password' | head -30 || echo '(no wifi credentials accessible)'", "r");
    if (fp) {
        char buf[OUT_BUF];
        size_t r = fread(buf, 1, sizeof(buf) - 1, fp);
        buf[r] = 0;
        pclose(fp);
        if (r > 10) {
            char op[MAX_PATH];
            snprintf(op, sizeof(op), "%s/wifi_networks.txt", subdir);
            _write_file(op, buf);
            count++;
        }
    }

    return count;
}

/* ================================================================
 *  MODULE: CLIPBOARD
 * ================================================================ */

static int module_clipboard(const char *outdir) {
    char subdir[MAX_PATH];
    snprintf(subdir, sizeof(subdir), "%s/clipboard", outdir);
    _mkdir_p(subdir);

    int saved = 0;
    const char *cmds[] = {
        "content read --uri content://clipboard 2>/dev/null || true",
        "dumpsys clipboard 2>/dev/null | head -100 || true",
        NULL
    };
    const char *names[] = {"clipboard.txt", "clipboard_dumpsys.txt"};

    for (int i = 0; cmds[i]; i++) {
        FILE *fp = popen(cmds[i], "r");
        if (!fp) continue;
        char buf[OUT_BUF];
        size_t r = fread(buf, 1, sizeof(buf) - 1, fp);
        buf[r] = 0;
        pclose(fp);
        if (r > 10) {
            char op[MAX_PATH];
            snprintf(op, sizeof(op), "%s/%s", subdir, names[i]);
            _write_file(op, buf);
            saved = 1;
        }
    }
    if (!saved) {
        char op[MAX_PATH];
        snprintf(op, sizeof(op), "%s/clipboard.txt", subdir);
        _write_file(op, "[empty]");
    }
    return saved;
}

/* ================================================================
 *  MAIN — Subcommand dispatcher
 * ================================================================ */

typedef struct {
    const char *name;
    int (*func)(const char *);
    const char *desc;
} ModuleEntry;

static const ModuleEntry modules[] = {
    {"imei",         module_imei,         "IMEI and device identifiers"},
    {"communications", module_communications, "SMS, contacts, call log"},
    {"contacts",     module_communications, "Alias for communications"},
    {"sms",          module_communications, "Alias for communications"},
    {"system",       module_system,       "System properties, settings, dumpsys"},
    {"packages",     module_packages,     "APK and package listing"},
    {"apks",         module_packages,     "Alias for packages"},
    {"media",        module_media,        "Photos, videos, audio scanner"},
    {"backup",       module_backup,       "Full /sdcard/ file list and summary"},
    {"hidden",       module_hidden,       "Hidden files and large files"},
    {"proc",         module_proc,         "Process scanner"},
    {"network",      module_network,      "Network interfaces and stats"},
    {"userdata",     module_userdata,     "/sdcard/ listing and disk usage"},
    {"browser",      module_browser,      "Browser databases"},
    {"accounts",     module_accounts,     "Account and WiFi info"},
    {"clipboard",    module_clipboard,    "Clipboard content"},
    {NULL, NULL, NULL}
};

static int run_all(const char *outdir) {
    int total = 0;
    for (int i = 0; modules[i].name; i++) {
        /* Skip aliases */
        if (strcmp(modules[i].name, "contacts") == 0 ||
            strcmp(modules[i].name, "sms") == 0 ||
            strcmp(modules[i].name, "apks") == 0) continue;

        fprintf(stderr, "  [%s] %s...\n", modules[i].name, modules[i].desc);
        int r = modules[i].func(outdir);
        fprintf(stderr, "    -> %d items\n", r);
        total += r;
    }
    return total;
}

int main(int argc, char **argv) {
    const char *outdir = "/data/local/tmp/extract_results";
    const char *mode = "all";

    if (argc >= 2) outdir = argv[1];
    if (argc >= 3) mode = argv[2];

    _mkdir_p(outdir);

    fprintf(stderr, "extract_droid v2.0 — Universal Android Extraction Engine\n");
    fprintf(stderr, "  Output: %s\n", outdir);
    fprintf(stderr, "  Mode: %s\n\n", mode);

    int total_items = 0;

    if (strcmp(mode, "--all") == 0 || strcmp(mode, "all") == 0) {
        total_items = run_all(outdir);
    } else {
        /* Strip leading -- if present */
        if (mode[0] == '-' && mode[1] == '-') mode += 2;

        int found = 0;
        for (int i = 0; modules[i].name; i++) {
            if (strcmp(modules[i].name, mode) == 0) {
                total_items = modules[i].func(outdir);
                found = 1;
                break;
            }
        }

        if (!found) {
            fprintf(stderr, "Unknown module: %s\n\nAvailable modules:\n", mode);
            for (int i = 0; modules[i].name; i++)
                fprintf(stderr, "  --%-15s %s\n", modules[i].name, modules[i].desc);
            return 1;
        }
    }

    /* Write JSON result */
    _json_open("/data/local/tmp/extract_droid_result.json");
    _json_kv("engine", "extract_droid");
    _json_kv("version", "2.0");
    _json_kv("output_dir", outdir);
    _json_kv("mode", mode);
    _json_ki("total_items", total_items);
    _json_close();

    fprintf(stderr, "\nDone. Total items: %d\n", total_items);
    printf("%s\n", outdir);
    return 0;
}
