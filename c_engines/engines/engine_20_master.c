// engine_20_master.c - Master orchestrator
#include "common.h"
static int write_in(const char *d, const char *n, const char *c) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", d, n); return write_file(p, c);
}
static FILE *fopen_in(const char *d, const char *n) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", d, n); return fopen(p, "w");
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH], buf[65536], cmd[MAX_PATH * 2];
    snprintf(res, sizeof(res), "%s/master", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_20.json", outdir); json_start(jsonname);
    int total_files = 0, total_engines = 0;
    const char *engines[][2] = {
        {"imei","./engine_01_imei"},{"contacts","./engine_02_contacts"},{"sms","./engine_03_sms"},
        {"calllog","./engine_04_calllog"},{"wifi","./engine_05_wifi"},{"accounts","./engine_06_accounts"},
        {"whatsapp","./engine_07_whatsapp"},{"telegram","./engine_08_telegram"},{"browser","./engine_09_browser"},
        {"system","./engine_10_system"},{"process","./engine_11_process"},{"network","./engine_12_network"},
        {"sqlite","./engine_13_sqlite"},{"media","./engine_14_media"},{"files","./engine_15_files"},
        {"backup","./engine_16_backup"},{"hidden","./engine_17_hidden"},{"device","./engine_18_device"},
        {"keystore","./engine_19_keystore"},{NULL,NULL}
    };
    FILE *report = fopen_in(res, "master_report.json");
    if (report) fprintf(report, "{\"engine\":\"master\",\"sub_engines\":[");
    int first = 1;
    for (int i = 0; engines[i][0]; i++) {
        snprintf(cmd, sizeof(cmd), "%s %s 2>/dev/null", engines[i][1], outdir);
        int rc = run_cmd(cmd, buf, sizeof(buf));
        if (rc >= 0 && strlen(buf) > 5) {
            char *r; int n = 0;
            if ((r = strstr(buf, "\"files\":")) != NULL) { r += 7; while (*r == ' ') r++; n = atoi(r); }
            total_files += n;
            if (strstr(buf, "\"status\":\"ok\"")) {
                total_engines++;
                if (report) { if (!first) fprintf(report, ","); fprintf(report, "{\"name\":\"%s\",\"status\":\"ok\",\"files\":%d}", engines[i][0], n); first = 0; }
            } else {
                if (report) { if (!first) fprintf(report, ","); fprintf(report, "{\"name\":\"%s\",\"status\":\"fail\"}", engines[i][0]); first = 0; }
            }
        }
    }
    if (report) { fprintf(report, "],\"engines_ok\":%d,\"total_files\":%d}\n", total_engines, total_files); fclose(report); }
    char summary[256]; snprintf(summary, sizeof(summary), "Master: %d/19 engines OK, %d total files\n", total_engines, total_files);
    write_in(res, "summary.txt", summary);
    json_ki("engines_ok", total_engines); json_ki("total_files", total_files); json_end();
    printf("{\"engine\":\"master\",\"status\":\"ok\",\"engines_ok\":%d,\"total_files\":%d}\n", total_engines, total_files);
    return 0;
}
