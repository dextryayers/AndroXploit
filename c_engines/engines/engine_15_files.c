// engine_15_files.c - Recursive full file crawler with metadata index
#include "common.h"
static int write_file_with_name(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
static FILE *fopen_append(const char *dir, const char *name) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name);
    return fopen(p, "w");
}
static int scan_files(const char *base, const char *out, int depth, FILE *idx) {
    DIR *d = opendir(base); if (!d || depth > 5) return 0;
    struct dirent *e; char sp[MAX_PATH]; int n = 0;
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.') continue;
        snprintf(sp, sizeof(sp), "%s/%s", base, e->d_name);
        struct stat st; if (stat(sp, &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) {
            n += scan_files(sp, out, depth + 1, idx);
        } else if (S_ISREG(st.st_mode)) {
            if (idx) fprintf(idx, "%s,%lld,%lo,%ld\n", sp, (long long)st.st_size,
                (unsigned long)(st.st_mode & 0777), (long)st.st_mtime);
            n++;
        }
    } closedir(d); return n;
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH];
    snprintf(res, sizeof(res), "%s/files", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_15.json", outdir); json_start(jsonname);
    int total = 0;
    // Index file
    char idxpath[MAX_PATH]; snprintf(idxpath, sizeof(idxpath), "%s/files_index.csv", res);
    FILE *idx = fopen(idxpath, "w");
    if (idx) fprintf(idx, "path,size,perms,mtime\n");
    // Scan key directories
    const char *dirs[] = {
        "/storage/emulated/0/", "/sdcard/",
        "/storage/emulated/0/Android/data/",
        "/storage/emulated/0/Android/obb/",
        "/storage/emulated/0/Android/media/",
        NULL
    };
    for (int i = 0; dirs[i]; i++) {
        if (dir_exists(dirs[i])) total += scan_files(dirs[i], res, 0, idx);
    }
    if (idx) { fclose(idx); total++; }
    // Also try root paths if available
    const char *root_dirs[] = {
        "/data/data/", "/data/system/", "/data/misc/",
        NULL
    };
    if (try_root("/data")) {
        FILE *ridx = fopen_append(res, "root_files_index.csv");
        if (ridx) {
            fprintf(ridx, "path,size,perms,mtime\n");
            for (int i = 0; root_dirs[i]; i++) {
                if (dir_exists(root_dirs[i])) total += scan_files(root_dirs[i], res, 0, ridx);
            }
            fclose(ridx); total++;
        }
    }
    json_ki("files_extracted", total); json_end();
    printf("{\"engine\":\"files\",\"status\":\"ok\",\"files\":%d}\n", total);
    return 0;
}

