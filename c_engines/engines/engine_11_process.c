// engine_11_process.c - Process, memory & running services scanner
#include "common.h"
static int write_file_with_name(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
static int dump_cmd(const char *res, const char *name, const char *cmd, char *buf, size_t bufsz) {
    if (run_cmd(cmd, buf, bufsz) < 0 || strlen(buf) < 5) return 0;
    write_file_with_name(res, name, buf); return 1;
}
static int read_proc_dir(const char *pid, const char *field, const char *outdir, const char *label) {
    char path[MAX_PATH], dst[MAX_PATH], buf[4096];
    snprintf(path, sizeof(path), "/proc/%s/%s", pid, field);
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 0;
    int r = read(fd, buf, sizeof(buf) - 1); close(fd);
    if (r <= 0) return 0; buf[r] = 0;
    snprintf(dst, sizeof(dst), "%s/proc_%s_%s.txt", outdir, pid, label);
    write_file(dst, buf); return 1;
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH], buf[65536];
    snprintf(res, sizeof(res), "%s/process", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_11.json", outdir); json_start(jsonname);
    int count = 0;
    // Process list
    count += dump_cmd(res, "ps_all.txt", "ps -A -o PID,PPID,USER,NAME 2>/dev/null | head -2000 || ps 2>/dev/null | head -2000 || true", buf, sizeof(buf));
    count += dump_cmd(res, "ps_thread.txt", "ps -AT -o PID,TID,USER,NAME 2>/dev/null | head -2000 || true", buf, sizeof(buf));
    count += dump_cmd(res, "top.txt", "top -b -n 1 2>/dev/null | head -200 || true", buf, sizeof(buf));
    // Read /proc/[pid]/ for each process
    DIR *d = opendir("/proc"); if (d) {
        struct dirent *e; int pcount = 0;
        while ((e = readdir(d)) != NULL && pcount < 100) {
            if (!isdigit(e->d_name[0])) continue;
            read_proc_dir(e->d_name, "cmdline", res, e->d_name);
            read_proc_dir(e->d_name, "status", res, e->d_name);
            read_proc_dir(e->d_name, "environ", res, e->d_name);
            read_proc_dir(e->d_name, "oom_score", res, e->d_name);
            read_proc_dir(e->d_name, "oom_score_adj", res, e->d_name);
            read_proc_dir(e->d_name, "cgroup", res, e->d_name);
            read_proc_dir(e->d_name, "limits", res, e->d_name);
            read_proc_dir(e->d_name, "maps", res, e->d_name);
            pcount++;
        } closedir(d); count += pcount * 8;
    }
    // dumpsys services
    count += dump_cmd(res, "dumpsys_activity.txt", "dumpsys activity 2>/dev/null | grep -iE '(Proc|Process|Running|Recent)' | head -500 || true", buf, sizeof(buf));
    count += dump_cmd(res, "dumpsys_process.txt", "dumpsys process 2>/dev/null | head -1000 || true", buf, sizeof(buf));
    count += dump_cmd(res, "dumpsys_app.txt", "dumpsys app 2>/dev/null | head -1000 || true", buf, sizeof(buf));
    count += dump_cmd(res, "service_list.txt", "service list 2>/dev/null || true", buf, sizeof(buf));
    // lsof
    count += dump_cmd(res, "lsof.txt", "lsof 2>/dev/null | head -2000 || true", buf, sizeof(buf));
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"process\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
