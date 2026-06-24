// engine_07_whatsapp.c - WhatsApp data extraction
#include "common.h"
static int write_file_with_name(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
static int scan_dir_for_db(const char *base, const char *out, const char *filter) {
    DIR *d = opendir(base); if (!d) return 0;
    struct dirent *e; char sp[MAX_PATH]; int n = 0;
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.') continue;
        snprintf(sp, sizeof(sp), "%s/%s", base, e->d_name);
        struct stat st; if (stat(sp, &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) {
            n += scan_dir_for_db(sp, out, filter);
        } else if (has_ext(e->d_name, filter) || has_ext(e->d_name, ".db") || has_ext(e->d_name, ".sqlite")) {
            char dst[MAX_PATH]; snprintf(dst, sizeof(dst), "%s/%s_%s", out, base[0] == '/' ? base + 1 : base, e->d_name);
            char *clean = dst; while (*clean) { if (*clean == '/') *clean = '_'; clean++; }
            snprintf(dst, MAX_PATH, "%s/%s", out, dst);
            if (copy_file(sp, dst) == 0 && file_size(dst) > 0) n++;
        }
    } closedir(d); return n;
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH], buf[65536];
    snprintf(res, sizeof(res), "%s/whatsapp", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_07.json", outdir); json_start(jsonname);
    int count = 0;
    // WhatsApp paths (with root fallback)
    const char *wa_paths[] = {
        "/data/data/com.whatsapp/databases/msgstore.db",
        "/data/data/com.whatsapp/databases/wa.db",
        "/data/data/com.whatsapp/databases/axolotl.db",
        "/data/data/com.whatsapp/databases/chats.db",
        "/data/data/com.whatsapp/databases/contacts.db",
        "/data/data/com.whatsapp/databases/media.db",
        "/data/data/com.whatsapp/databases/stickers.db",
        "/data/data/com.whatsapp/databases/thumbnails.db",
        "/data/data/com.whatsapp/shared_prefs/",
        "/data/data/com.whatsapp/files/",
        NULL
    };
    for (int i = 0; wa_paths[i]; i++) {
        char dst[MAX_PATH]; const char *l = strrchr(wa_paths[i], '/');
        snprintf(dst, sizeof(dst), "%s/%s", res, l ? l + 1 : "wa_file");
        save_with_root_fallback(wa_paths[i], dst);
        if (file_exists(dst) && file_size(dst) > 0) count++;
    }
    // WhatsApp Business
    const char *wa_biz_paths[] = {
        "/data/data/com.whatsapp.w4b/databases/msgstore.db",
        "/data/data/com.whatsapp.w4b/databases/wa.db",
        NULL
    };
    for (int i = 0; wa_biz_paths[i]; i++) {
        char dst[MAX_PATH]; const char *l = strrchr(wa_biz_paths[i], '/');
        snprintf(dst, sizeof(dst), "%s/%s", res, l ? l + 1 : "wabiz_file");
        save_with_root_fallback(wa_biz_paths[i], dst);
        if (file_exists(dst) && file_size(dst) > 0) count++;
    }
    // /sdcard/ WhatsApp media
    const char *wa_media[] = {
        "/storage/emulated/0/WhatsApp/Databases/",
        "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Databases/",
        NULL
    };
    for (int i = 0; wa_media[i]; i++) {
        if (dir_exists(wa_media[i])) {
            count += scan_dir_for_db(wa_media[i], res, ".db");
        }
    }
    // Try content provider
    run_cmd("content query --uri content://settings/secure --where \"name LIKE '%whatsapp%'\" 2>/dev/null || true", buf, sizeof(buf));
    if (strlen(buf) > 5) { write_file_with_name(res, "settings_whatsapp.txt", buf); count++; }
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"whatsapp\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
