// engine_06_accounts.c - Account & authenticator extraction
#include "common.h"
static int write_file_with_name(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH], buf[65536], cmd[MAX_PATH * 2];
    snprintf(res, sizeof(res), "%s/accounts", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_06.json", outdir); json_start(jsonname);
    int count = 0;
    // Account databases
    const char *db_paths[] = {
        "/data/data/com.android.settings/databases/accounts.db",
        "/data/system/users/0/accounts.db",
        "/data/system/sync/accounts.xml",
        "/data/system/registered_services/android.accounts.AccountAuthenticator.xml",
        NULL
    };
    for (int i = 0; db_paths[i]; i++) {
        char dst[MAX_PATH]; const char *l = strrchr(db_paths[i], '/');
        snprintf(dst, sizeof(dst), "%s/%s", res, l ? l + 1 : "account.db");
        save_with_root_fallback(db_paths[i], dst);
        if (file_exists(dst) && file_size(dst) > 10) count++;
    }
    // Content providers
    const char *uris[] = {
        "content://settings/global", "content://settings/secure", "content://settings/system",
        NULL
    };
    for (int i = 0; uris[i]; i++) {
        snprintf(cmd, sizeof(cmd), "content query --uri %s 2>/dev/null | head -5000 || true", uris[i]);
        if (run_cmd(cmd, buf, sizeof(buf)) >= 0 && strlen(buf) > 50) {
            char fn[64]; snprintf(fn, sizeof(fn), "settings_%s.txt", strrchr(uris[i], '/') + 1);
            write_file_with_name(res, fn, buf); count++; }
    }
    // dumpsys account
    run_cmd("dumpsys account 2>/dev/null | head -2000 || true", buf, sizeof(buf));
    if (strlen(buf) > 10) { write_file_with_name(res, "dumpsys_account.txt", buf); count++; }
    // dumpsys user
    run_cmd("dumpsys user 2>/dev/null | head -1000 || true", buf, sizeof(buf));
    if (strlen(buf) > 10) { write_file_with_name(res, "dumpsys_user.txt", buf); count++; }
    // pm list users
    run_cmd("pm list users 2>/dev/null || true", buf, sizeof(buf));
    if (strlen(buf) > 10) { write_file_with_name(res, "pm_users.txt", buf); count++; }
    // List authenticators
    run_cmd("pm query-services --user 0 android.accounts.AccountAuthenticator 2>/dev/null || true", buf, sizeof(buf));
    if (strlen(buf) > 10) { write_file_with_name(res, "authenticators.txt", buf); count++; }
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"accounts\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
