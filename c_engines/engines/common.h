#ifndef _CE_COMMON_H_
#define _CE_COMMON_H_

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
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/sysmacros.h>

#define MAX_PATH 4096
#define BUF_SZ 65536

static void mkdir_p(const char *path) {
    char tmp[MAX_PATH]; char *p; int r;
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (p = tmp + 1; *p; p++) {
        if (*p == '/') { *p = 0; r = mkdir(tmp, 0755); (void)r; *p = '/'; }
    }
    r = mkdir(tmp, 0755); (void)r;
}

static char *read_file(const char *path) {
    FILE *f = fopen(path, "rb"); if (!f) return NULL;
    fseek(f, 0, SEEK_END); long len = ftell(f);
    if (len > 52428800) { fclose(f); return NULL; }
    fseek(f, 0, SEEK_SET);
    char *b = malloc(len + 1); if (!b) { fclose(f); return NULL; }
    size_t r = fread(b, 1, len, f); b[r] = 0; fclose(f);
    return b;
}

static int write_file(const char *path, const char *content) {
    FILE *f = fopen(path, "w"); if (!f) return -1;
    if (content) { fputs(content, f); } fclose(f); return 0;
}

static long long file_size(const char *path) {
    struct stat st; return (stat(path, &st) == 0) ? (long long)st.st_size : 0;
}

static int copy_file(const char *src, const char *dst) {
    char *d = read_file(src); if (!d) return -1;
    int r = write_file(dst, d); free(d); return r;
}

static int file_exists(const char *p) { struct stat st; return stat(p, &st) == 0; }

static int dir_exists(const char *p) { struct stat st; return stat(p, &st) == 0 && S_ISDIR(st.st_mode); }

static int run_cmd(const char *cmd, char *out, size_t outsz) {
    FILE *fp = popen(cmd, "r"); if (!fp) return -1;
    size_t r = fread(out, 1, outsz - 1, fp); out[r] = 0;
    return pclose(fp);
}

static int try_root(const char *path) {
    char cmd[MAX_PATH * 2]; char buf[256];
    snprintf(cmd, sizeof(cmd), "su -c 'cat %s' 2>/dev/null | head -c 100 || true", path);
    FILE *fp = popen(cmd, "r");
    if (!fp) return 0;
    size_t r = fread(buf, 1, sizeof(buf) - 1, fp); buf[r] = 0;
    pclose(fp);
    return r > 5;
}

static void save_with_root_fallback(const char *src, const char *dst) {
    if (copy_file(src, dst) == 0) return;
    char cmd[MAX_PATH * 3];
    snprintf(cmd, sizeof(cmd), "su -c 'cp %s %s' 2>/dev/null || true", src, dst);
    FILE *fp = popen(cmd, "r"); if (fp) pclose(fp);
}

static int count_dir(const char *dir) {
    DIR *d = opendir(dir); if (!d) return 0;
    int n = 0; struct dirent *e;
    while ((e = readdir(d)) != NULL) { if (e->d_name[0] != '.') n++; }
    closedir(d); return n;
}

static int has_ext(const char *name, const char *ext) {
    const char *e = strrchr(name, '.'); if (!e) return 0;
    return strcasecmp(e, ext) == 0;
}

/* JSON output helpers */
static FILE *jfp = NULL;
static int jfirst = 0;
static void json_start(const char *path) {
    jfp = fopen(path, "w"); if (!jfp) return;
    fprintf(jfp, "{\n"); jfirst = 1;
}
static void json_kv(const char *k, const char *v) {
    if (!jfp) return; if (!jfirst) { fprintf(jfp, ",\n"); } else { jfirst = 0; }
    fprintf(jfp, "  \"%s\": \"%s\"", k, v ? v : ""); fflush(jfp);
}
static void json_ki(const char *k, long long v) {
    if (!jfp) return; if (!jfirst) { fprintf(jfp, ",\n"); } else { jfirst = 0; }
    fprintf(jfp, "  \"%s\": %lld", k, v); fflush(jfp);
}
static void json_end(void) {
    if (!jfp) return; fprintf(jfp, "\n}\n"); fclose(jfp); jfp = NULL;
}

#endif
