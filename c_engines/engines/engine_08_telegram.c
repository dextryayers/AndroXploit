// engine_08_telegram.c - Telegram data extraction
#include "common.h"
static int write_file_with_name(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
static int scan_dir(const char *base, const char *out, int depth) {
    DIR *d = opendir(base); if (!d || depth > 5) return 0;
    struct dirent *e; char sp[MAX_PATH]; int n = 0;
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.') continue;
        snprintf(sp, sizeof(sp), "%s/%s", base, e->d_name);
        struct stat st; if (stat(sp, &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) {
            n += scan_dir(sp, out, depth + 1);
        } else if (has_ext(e->d_name, ".db") || has_ext(e->d_name, ".sqlite") || has_ext(e->d_name, ".xml") || has_ext(e->d_name, ".json") || has_ext(e->d_name, ".conf") || has_ext(e->d_name, ".pref")) {
            char dst[MAX_PATH], fname[MAX_PATH * 2];
            snprintf(fname, sizeof(fname), "%s", sp);
            char *clean = fname; while (*clean) { if (*clean == '/') *clean = '_'; clean++; }
            snprintf(dst, sizeof(dst), "%s/%s", out, fname);
            if (copy_file(sp, dst) == 0 && file_size(dst) > 0) n++;
        }
    } closedir(d); return n;
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH], buf[65536];
    snprintf(res, sizeof(res), "%s/telegram", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_08.json", outdir); json_start(jsonname);
    int count = 0;
    // Official Telegram
    const char *tg_paths[] = {
        "/data/data/org.telegram.messenger/databases/cache4.db",
        "/data/data/org.telegram.messenger/databases/kv.db",
        "/data/data/org.telegram.messenger/files/",
        "/data/data/org.telegram.messenger/shared_prefs/",
        NULL
    };
    for (int i = 0; tg_paths[i]; i++) {
        char dst[MAX_PATH]; const char *l = strrchr(tg_paths[i], '/');
        snprintf(dst, sizeof(dst), "%s/%s", res, l ? l + 1 : "tg_file");
        save_with_root_fallback(tg_paths[i], dst);
        if (file_exists(dst) && file_size(dst) > 0) count++;
        if (dir_exists(tg_paths[i])) {
            count += scan_dir(tg_paths[i], res, 0);
        }
    }
    // Telegram X
    const char *tgx_paths[] = {
        "/data/data/org.telegram.messenger.web/databases/",
        "/data/data/org.telegram.messenger.beta/databases/",
        NULL
    };
    for (int i = 0; tgx_paths[i]; i++) {
        if (dir_exists(tgx_paths[i])) count += scan_dir(tgx_paths[i], res, 0);
    }
    // Plus Messenger
    if (dir_exists("/data/data/com.plusmessenger/databases/"))
        count += scan_dir("/data/data/com.plusmessenger/", res, 2);
    // Telegram Desktop cache on /sdcard
    const char *tg_sdcard[] = {
        "/storage/emulated/0/Telegram/",
        "/storage/emulated/0/Android/data/org.telegram.messenger/",
        NULL
    };
    for (int i = 0; tg_sdcard[i]; i++) {
        if (dir_exists(tg_sdcard[i])) count += scan_dir(tg_sdcard[i], res, 0);
    }
    // settings
    run_cmd("content query --uri content://settings/secure --where \"name LIKE '%telegram%'\" 2>/dev/null || true", buf, sizeof(buf));
    if (strlen(buf) > 5) { write_file_with_name(res, "settings_telegram.txt", buf); count++; }
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"telegram\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
