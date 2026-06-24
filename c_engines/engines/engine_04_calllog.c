// engine_04_calllog.c - Call log extraction
#include "common.h"
static int write_file_with_name(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH], buf[65536];
    snprintf(res, sizeof(res), "%s/calllog", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_04.json", outdir); json_start(jsonname);
    int count = 0;
    // Call log database
    const char *dbs[] = {
        "/data/data/com.android.providers.contacts/databases/calllog.db",
        "/data/data/com.android.providers.contacts/databases/contacts2.db",
        NULL
    };
    for (int i = 0; dbs[i]; i++) {
        char dst[MAX_PATH], cmd[MAX_PATH * 2];
        const char *l = strrchr(dbs[i], '/');
        snprintf(dst, sizeof(dst), "%s/%s", res, l ? l + 1 : "calllog.db");
        save_with_root_fallback(dbs[i], dst);
        if (file_exists(dst) && file_size(dst) > 100) { count++;
            snprintf(cmd, sizeof(cmd), "strings %s 2>/dev/null | grep -iE '(call|dial|incoming|outgoing|missed|duration)' | head -500 || true", dst);
            if (run_cmd(cmd, buf, sizeof(buf)) >= 0 && strlen(buf) > 5) {
                snprintf(dst, sizeof(dst), "%s/strings_calllog.txt", res); write_file(dst, buf); count++; } }
    }
    // Content provider
    const char *uris[] = {"content://call_log/calls", NULL};
    for (int i = 0; uris[i]; i++) {
        char cmd[256]; snprintf(cmd, sizeof(cmd), "content query --uri %s 2>/dev/null | head -5000 || true", uris[i]);
        if (run_cmd(cmd, buf, sizeof(buf)) >= 0 && strlen(buf) > 10) {
            write_file_with_name(res, "call_log_content.txt", buf); count++; }
    }
    // dumpsys
    run_cmd("dumpsys dropbox 2>/dev/null | grep -i call | head -200 || true", buf, sizeof(buf));
    if (strlen(buf) > 10) { write_file_with_name(res, "dropbox_calls.txt", buf); count++; }
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"calllog\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
