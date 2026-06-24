// engine_12_network.c - Network state & connections dump
#include "common.h"
static int write_file_with_name(const char *dir, const char *name, const char *content) {
    char p[MAX_PATH]; snprintf(p, sizeof(p), "%s/%s", dir, name); return write_file(p, content);
}
static int dump_cmd(const char *res, const char *name, const char *cmd, char *buf, size_t bufsz) {
    if (run_cmd(cmd, buf, bufsz) < 0 || strlen(buf) < 5) return 0;
    write_file_with_name(res, name, buf); return 1;
}
int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : ".";
    char res[MAX_PATH], jsonname[MAX_PATH], buf[65536];
    snprintf(res, sizeof(res), "%s/network", outdir); mkdir_p(res);
    snprintf(jsonname, sizeof(jsonname), "%s/.engine_12.json", outdir); json_start(jsonname);
    int count = 0;
    // Network interfaces
    DIR *d = opendir("/sys/class/net"); if (d) {
        struct dirent *e; char sp[MAX_PATH], dst[MAX_PATH], b[4096];
        while ((e = readdir(d)) != NULL) {
            if (e->d_name[0] == '.') continue;
            snprintf(sp, sizeof(sp), "/sys/class/net/%s/address", e->d_name);
            int fd = open(sp, O_RDONLY); if (fd >= 0) {
                int r = read(fd, b, sizeof(b) - 1); close(fd); b[r] = 0;
                snprintf(dst, sizeof(dst), "%s/mac_%s.txt", res, e->d_name);
                write_file(dst, b); count++; }
            snprintf(sp, sizeof(sp), "/sys/class/net/%s/operstate", e->d_name);
            fd = open(sp, O_RDONLY); if (fd >= 0) {
                int r = read(fd, b, sizeof(b) - 1); close(fd); b[r] = 0;
                snprintf(dst, sizeof(dst), "%s/state_%s.txt", res, e->d_name);
                write_file(dst, b); count++; }
        } closedir(d);
    }
    // WiFi interfaces
    d = opendir("/sys/class/net"); if (d) {
        struct dirent *e; char sp[MAX_PATH], dst[MAX_PATH], b[4096];
        while ((e = readdir(d)) != NULL) {
            if (strstr(e->d_name, "wlan") == NULL && strstr(e->d_name, "wifi") == NULL) continue;
            snprintf(sp, sizeof(sp), "/sys/class/net/%s/device/device", e->d_name);
            int fd = open(sp, O_RDONLY); if (fd >= 0) {
                int r = read(fd, b, sizeof(b) - 1); close(fd); b[r] = 0;
                snprintf(dst, sizeof(dst), "%s/wifi_device_%s.txt", res, e->d_name);
                write_file(dst, b); count++; }
        } closedir(d);
    }
    // Commands
    count += dump_cmd(res, "ip_addr.txt", "ip addr 2>/dev/null || ifconfig 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "ip_route.txt", "ip route 2>/dev/null || route -n 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "ip_neigh.txt", "ip neigh 2>/dev/null || arp -n 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "ip_link.txt", "ip link 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "netstat_all.txt", "netstat -anep 2>/dev/null || ss -anep 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "netstat_listen.txt", "netstat -lntp 2>/dev/null || ss -lntp 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "resolv_conf.txt", "cat /etc/resolv.conf 2>/dev/null || cat /system/etc/resolv.conf 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "iptables.txt", "iptables -L -n 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "arp_cache.txt", "cat /proc/net/arp 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "tcp_connections.txt", "cat /proc/net/tcp 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "tcp6_connections.txt", "cat /proc/net/tcp6 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "udp_connections.txt", "cat /proc/net/udp 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "unix_sockets.txt", "cat /proc/net/unix 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "wireless_info.txt", "cat /proc/net/wireless 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "dnsmasq.txt", "cat /data/misc/dnsmasq* 2>/dev/null || true", buf, sizeof(buf));
    count += dump_cmd(res, "dns_tls.txt", "cat /data/misc/connectivity/dns_tls_* 2>/dev/null || true", buf, sizeof(buf));
    // dumpsys
    count += dump_cmd(res, "dumpsys_connectivity.txt", "dumpsys connectivity 2>/dev/null | head -500 || true", buf, sizeof(buf));
    count += dump_cmd(res, "dumpsys_ethernet.txt", "dumpsys ethernet 2>/dev/null | head -200 || true", buf, sizeof(buf));
    json_ki("files_extracted", count); json_end();
    printf("{\"engine\":\"network\",\"status\":\"ok\",\"files\":%d}\n", count);
    return 0;
}
