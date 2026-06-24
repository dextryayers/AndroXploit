// engine_03_sms.c - SMS/MMS database extraction
#include "common.h"
static int write_file_with_name(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH], buf[65536];
    snprintf(res, sizeof(res), "%s/sms", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_03.json", outdir); json_start(jsonname);
    int count = 0;
    // Database paths
    const char *db_paths[] = {
        "/data/data/com.android.providers.telephony/databases/mmssms.db",
        "/data/data/com.android.providers.telephony/databases/telephony.db",
        "/data/data/com.android.providers.telephony/databases/carriers.db",
        NULL
    };
    for (int i = 0; db_paths[i]; i++) {
        char dst[MAX_PATH], cmd[MAX_PATH * 2];
        const char *label = strrchr(db_paths[i], '/'); label = label ? label + 1 : db_paths[i];
        snprintf(dst, sizeof(dst), "%s/%s", res, label);
        save_with_root_fallback(db_paths[i], dst);
        if (file_exists(dst) && file_size(dst) > 100) {
            count++;
            snprintf(cmd, sizeof(cmd), "strings %s 2>/dev/null | grep -iE '(sms|mms|text|message|inbox|sent)' | head -500 || true", dst);
            if (run_cmd(cmd, buf, sizeof(buf)) >= 0 && strlen(buf) > 5) {
                snprintf(dst, sizeof(dst), "%s/strings_%s.txt", res, label); write_file(dst, buf); count++; }
        }
    }
    // Content provider dump
    const char *uris[] = {
        "content://sms", "content://sms/inbox", "content://sms/sent",
        "content://mms", "content://mms/inbox", "content://telephony/carriers",
        NULL
    };
    for (int i = 0; uris[i]; i++) {
        char cmd[256]; snprintf(cmd, sizeof(cmd), "content query --uri %s 2>/dev/null | head -2000 || true", uris[i]);
        if (run_cmd(cmd, buf, sizeof(buf)) >= 0 && strlen(buf) > 10) {
            char fn[MAX_PATH]; const char *l = strrchr(uris[i], '/');
            snprintf(fn, sizeof(fn), "content_%s.txt", l ? l + 1 : uris[i] + 9);
            write_file_with_name(res, fn, buf); count++; }
    }
    // dumpsys telephony
    run_cmd("dumpsys telephony.registry 2>/dev/null | head -1000 || true", buf, sizeof(buf));
    if (strlen(buf) > 10) { write_file_with_name(res, "dumpsys_telephony.txt", buf); count++; }
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"sms\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
