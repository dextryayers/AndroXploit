// engine_13_sqlite.c - Find and copy ALL SQLite databases
#include "common.h"
static int write_file_with_name(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
static int is_sqlite_db(const char *path) {
    FILE *f = fopen(path, "rb"); if (!f) return 0;
    unsigned char hdr[16]; int r = fread(hdr, 1, 16, f); fclose(f);
    return (r == 16 && hdr[0] == 'S' && hdr[1] == 'Q' && hdr[2] == 'L' && hdr[3] == 'i');
}
static int scan_for_sqlite(const char *base, const char *out, int depth) {
    DIR *d = opendir(base); if (!d || depth > 8) return 0;
    struct dirent *e; char sp[MAX_PATH]; int n = 0;
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.') continue;
        snprintf(sp, sizeof(sp), "%s/%s", base, e->d_name);
        struct stat st; if (stat(sp, &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) {
            // Skip /proc, /sys, /dev
            if (strcmp(sp, "/proc") == 0 || strcmp(sp, "/sys") == 0 || strcmp(sp, "/dev") == 0) continue;
            n += scan_for_sqlite(sp, out, depth + 1);
        } else if (S_ISREG(st.st_mode) && st.st_size > 100 && st.st_size < 524288000) {
            if (has_ext(e->d_name, ".db") || has_ext(e->d_name, ".sqlite") || has_ext(e->d_name, ".sqlite3")) {
                if (is_sqlite_db(sp)) {
                    char dst[MAX_PATH * 2];
                    snprintf(dst, sizeof(dst), "%s/%s", out, sp[0] == '/' ? sp + 1 : sp);
                    char *clean = dst; while (*clean) { if (*clean == '/') *clean = '_'; clean++; }
                    snprintf(dst, MAX_PATH * 2, "%s/%s", out, dst);
                    // Truncate if too long
                    if (strlen(dst) > 240) { dst[240] = 0; strcat(dst, ".db"); }
                    if (copy_file(sp, dst) == 0 && file_size(dst) > 0) n++;
                }
            }
        }
    } closedir(d); return n;
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH];
    snprintf(res, sizeof(res), "%s/sqlite", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_13.json", outdir); json_start(jsonname);
    int count = 0;
    // Scan accessible directories
    const char *dirs[] = {
        "/data/data/", "/data/system/", "/data/misc/",
        "/storage/emulated/0/Android/data/",
        "/storage/emulated/0/Android/obb/",
        "/storage/emulated/0/",
        NULL
    };
    for (int i = 0; dirs[i]; i++) {
        if (dir_exists(dirs[i])) count += scan_for_sqlite(dirs[i], res, 0);
    }
    // pm list packages and try to find their databases via root
    char buf[65536];
    run_cmd("pm list packages 2>/dev/null | cut -d: -f2 | head -500 || true", buf, sizeof(buf));
    char *line = buf; int npkg = 0;
    while ((line = strchr(line, '\n')) != NULL && npkg < 50) {
        if (line > buf) {
            char pkg[256]; int len = line - (line - strlen(line));
            // Actually just get the line
        }
        line++; npkg++;
    }
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"sqlite\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
