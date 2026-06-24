// engine_16_backup.c - Create full /sdcard/ backup (tar or copy)
#include "common.h"
static int write_file_with_name(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
static int copy_dir(const char *src, const char *dst, int depth) {
    DIR *d = opendir(src); if (!d || depth > 4) return 0;
    struct dirent *e; char sp[MAX_PATH], dp[MAX_PATH]; int n = 0;
    mkdir_p(dst);
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.') continue;
        snprintf(sp, sizeof(sp), "%s/%s", src, e->d_name);
        snprintf(dp, sizeof(dp), "%s/%s", dst, e->d_name);
        struct stat st; if (stat(sp, &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) {
            n += copy_dir(sp, dp, depth + 1);
        } else if (S_ISREG(st.st_mode) && st.st_size > 0 && st.st_size < 104857600) {
            if (copy_file(sp, dp) == 0 && file_exists(dp)) n++;
        }
    } closedir(d); return n;
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH], buf[65536], cmd[MAX_PATH * 2];
    snprintf(res, sizeof(res), "%s/backup", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_16.json", outdir); json_start(jsonname);
    int count = 0;
    // Key backup directories
    const char *backup_dirs[] = {
        "/storage/emulated/0/DCIM/",
        "/storage/emulated/0/Documents/",
        "/storage/emulated/0/Download/",
        "/storage/emulated/0/Pictures/",
        "/storage/emulated/0/Screenshots/",
        "/storage/emulated/0/WhatsApp/",
        "/storage/emulated/0/Telegram/",
        "/storage/emulated/0/.backups/",
        "/storage/emulated/0/backups/",
        "/storage/emulated/0/backup/",
        "/storage/emulated/0/TitaniumBackup/",
        "/storage/emulated/0/SwiftBackup/",
        "/storage/emulated/0/MigrateBackup/",
        "/storage/emulated/0/Android/data/com.keramidas.TitaniumBackup/",
        NULL
    };
    for (int i = 0; backup_dirs[i]; i++) {
        if (dir_exists(backup_dirs[i])) {
            char dst_dir[MAX_PATH];
            snprintf(dst_dir, sizeof(dst_dir), "%s/data%s", res, backup_dirs[i]);
            if (strlen(dst_dir) > 240) continue;
            int n = copy_dir(backup_dirs[i], dst_dir, 0);
            if (n > 0) count += n;
        }
    }
    // Try creating tar via busybox
    snprintf(cmd, sizeof(cmd), "busybox tar -czf %s/sdcard_backup.tar.gz -C /storage/emulated/0 . 2>/dev/null || tar -czf %s/sdcard_backup.tar.gz -C /storage/emulated/0 . 2>/dev/null || echo 'NO_TAR'", res, res);
    if (run_cmd(cmd, buf, sizeof(buf)) >= 0 && strstr(buf, "NO_TAR") == NULL) {
        char tarpath[MAX_PATH]; snprintf(tarpath, sizeof(tarpath), "%s/sdcard_backup.tar.gz", res);
        if (file_exists(tarpath) && file_size(tarpath) > 1000) count++;
    }
    // Copy key config files from /data
    const char *config_files[] = {
        "/data/system/accounts.db",
        "/data/system/device_policies.xml",
        "/data/system/packages.xml",
        "/data/system/sync/accounts.xml",
        "/data/misc/wifi/WifiConfigStore.xml",
        NULL
    };
    for (int i = 0; config_files[i]; i++) {
        char dst[MAX_PATH]; const char *l = strrchr(config_files[i], '/');
        snprintf(dst, sizeof(dst), "%s/%s", res, l ? l + 1 : "config");
        save_with_root_fallback(config_files[i], dst);
        if (file_exists(dst) && file_size(dst) > 10) count++;
    }
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"backup\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
