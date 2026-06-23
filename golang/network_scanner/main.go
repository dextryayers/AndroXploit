package main

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"sort"
	"strings"
	"sync"
	"time"
)

type HostResult struct {
	IP        string     `json:"ip"`
	Hostname  string     `json:"hostname,omitempty"`
	MAC       string     `json:"mac,omitempty"`
	Vendor    string     `json:"vendor,omitempty"`
	PortsOpen []PortInfo `json:"ports_open,omitempty"`
	Alive     bool       `json:"alive"`
	TTL       int        `json:"ttl,omitempty"`
	OS        string     `json:"os_guess,omitempty"`
}

type PortInfo struct {
	Port     int    `json:"port"`
	Service  string `json:"service"`
	Banner   string `json:"banner,omitempty"`
	Protocol string `json:"protocol"`
	State    string `json:"state"`
	Product  string `json:"product,omitempty"`
	Version  string `json:"version,omitempty"`
}

type ScanSummary struct {
	Subnet     string       `json:"subnet"`
	TotalHosts int          `json:"total_hosts"`
	AliveHosts int          `json:"alive_hosts"`
	TotalPorts int          `json:"total_ports_found"`
	Hosts      []HostResult `json:"hosts"`
	Duration   string       `json:"duration"`
	ScanType   string       `json:"scan_type"`
}

var commonPorts = map[int]string{
	21: "FTP", 22: "SSH", 23: "Telnet", 25: "SMTP",
	53: "DNS", 80: "HTTP", 110: "POP3", 111: "RPC",
	135: "MSRPC", 139: "NetBIOS", 143: "IMAP",
	443: "HTTPS", 445: "SMB", 993: "IMAPS", 995: "POP3S",
	1433: "MSSQL", 1521: "Oracle", 2049: "NFS",
	3306: "MySQL", 3389: "RDP", 5432: "PostgreSQL",
	5555: "ADB", 5900: "VNC", 6379: "Redis",
	8080: "HTTP-Proxy", 8443: "HTTPS-Alt", 9090: "HTTP-Alt",
	27017: "MongoDB", 5000: "Docker", 11211: "Memcached",
}

var serviceBannerProbes = map[int]string{
	21:   "220 ",
	22:   "SSH-",
	25:   "220 ",
	80:   "HTTP/",
	110:  "+OK",
	143:  "* OK",
	220:  "220 ",
	443:  "HTTP/",
	3306: "",
	5432: "",
	6379: "",
	8080: "HTTP/",
	8443: "HTTP/",
}

var portProtocols = map[int]string{
	21: "tcp", 22: "tcp", 23: "tcp", 25: "tcp",
	53: "tcp/udp", 80: "tcp", 443: "tcp",
	161: "udp", 162: "udp", 514: "udp",
	3306: "tcp", 5432: "tcp", 6379: "tcp",
	27017: "tcp", 5555: "tcp",
}

func main() {
	target := "192.168.1.0/24"
	var ports []int

	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	target = os.Args[1]

	if len(os.Args) > 2 {
		ports = parsePorts(os.Args[2])
	} else {
		ports = getCommonPorts()
	}

	start := time.Now()
	summary := scanNetwork(target, ports)
	summary.Duration = time.Since(start).String()

	emitJSON(summary)
}

func usage() {
	fmt.Fprintf(os.Stderr, "Usage: %s <target> [ports]\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "  target: IP, CIDR (192.168.1.0/24), or hostname\n")
	fmt.Fprintf(os.Stderr, "  ports: comma-separated (22,80,443) or range (1-1000) or 'common'\n")
	fmt.Fprintf(os.Stderr, "Examples:\n")
	fmt.Fprintf(os.Stderr, "  %s 192.168.1.0/24\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "  %s 10.0.0.1 22,80,443,8080\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "  %s scanme.nmap.org common\n", os.Args[0])
}

func parsePorts(arg string) []int {
	var ports []int
	if arg == "common" || arg == "top" {
		return getCommonPorts()
	}
	if strings.Contains(arg, "-") {
		parts := strings.SplitN(arg, "-", 2)
		start, end := 0, 0
		fmt.Sscanf(parts[0], "%d", &start)
		fmt.Sscanf(parts[1], "%d", &end)
		if start > 0 && end > 0 && end >= start && end <= 65535 {
			for p := start; p <= end; p++ {
				ports = append(ports, p)
			}
			return ports
		}
	}
	for _, p := range strings.Split(arg, ",") {
		var port int
		if _, err := fmt.Sscanf(strings.TrimSpace(p), "%d", &port); err == nil && port > 0 && port <= 65535 {
			ports = append(ports, port)
		}
	}
	if len(ports) == 0 {
		ports = append(ports, 5555)
	}
	return ports
}

func getCommonPorts() []int {
	ports := make([]int, 0, len(commonPorts))
	for p := range commonPorts {
		ports = append(ports, p)
	}
	sort.Ints(ports)
	return ports
}

func scanNetwork(target string, ports []int) *ScanSummary {
	summary := &ScanSummary{Subnet: target, ScanType: "TCP Connect"}

	if ip := net.ParseIP(target); ip != nil {
		return scanSingleHost(target, ports, summary)
	}

	ipnet := parseCIDR(target)
	if ipnet == nil {
		return summary
	}

	summary.Subnet = ipnet.String()

	var mu sync.Mutex
	var wg sync.WaitGroup

	ips := generateIPs(ipnet)
	summary.TotalHosts = len(ips)

	hostSem := make(chan struct{}, 50)
	portSem := make(chan struct{}, 20)

	for _, ip := range ips {
		wg.Add(1)
		hostSem <- struct{}{}
		go func(ipStr string) {
			defer wg.Done()
			defer func() { <-hostSem }()

			host := probeHost(ipStr, ports, portSem)
			if host.Alive {
				mu.Lock()
				summary.AliveHosts++
				summary.TotalPorts += len(host.PortsOpen)
				summary.Hosts = append(summary.Hosts, host)
				mu.Unlock()
			}
		}(ip)
	}
	wg.Wait()

	sort.Slice(summary.Hosts, func(i, j int) bool {
		ip1 := net.ParseIP(summary.Hosts[i].IP)
		ip2 := net.ParseIP(summary.Hosts[j].IP)
		if ip1 == nil || ip2 == nil {
			return summary.Hosts[i].IP < summary.Hosts[j].IP
		}
		return len(ip1) < len(ip2) || (len(ip1) == len(ip2) && string(ip1) < string(ip2))
	})

	return summary
}

func scanSingleHost(ip string, ports []int, summary *ScanSummary) *ScanSummary {
	host := probeHost(ip, ports, make(chan struct{}, 50))
	if host.Alive {
		summary.AliveHosts = 1
		summary.Hosts = append(summary.Hosts, host)
		summary.TotalPorts = len(host.PortsOpen)
	}
	summary.TotalHosts = 1
	return summary
}

func probeHost(ipStr string, ports []int, sem chan struct{}) HostResult {
	var host HostResult
	host.IP = ipStr

	pingResult := pingHost(ipStr)
	if pingResult {
		host.Alive = true
	}
	if pingResult {
		host.TTL = 64
	}

	names, err := net.LookupAddr(ipStr)
	if err == nil && len(names) > 0 {
		host.Hostname = strings.TrimSuffix(names[0], ".")
	}

	var mu sync.Mutex
	var wg sync.WaitGroup

	for _, p := range ports {
		wg.Add(1)
		sem <- struct{}{}
		go func(port int) {
			defer wg.Done()
			defer func() { <-sem }()

			info := probePort(ipStr, port)
			if info != nil {
				mu.Lock()
				host.PortsOpen = append(host.PortsOpen, *info)
				mu.Unlock()
			}
		}(p)
	}
	wg.Wait()

	sort.Slice(host.PortsOpen, func(i, j int) bool {
		return host.PortsOpen[i].Port < host.PortsOpen[j].Port
	})

	host.Alive = len(host.PortsOpen) > 0
	return host
}

func pingHost(ip string) bool {
	ports := []int{5555, 80, 443, 22, 8080}
	for _, p := range ports {
		conn, err := net.DialTimeout("tcp", net.JoinHostPort(ip, fmt.Sprintf("%d", p)), 2*time.Second)
		if err == nil {
			conn.Close()
			return true
		}
	}
	return false
}

func probePort(ipStr string, port int) *PortInfo {
	addr := net.JoinHostPort(ipStr, fmt.Sprintf("%d", port))
	conn, err := net.DialTimeout("tcp", addr, 3*time.Second)
	if err != nil {
		return nil
	}
	defer conn.Close()

	conn.SetReadDeadline(time.Now().Add(2 * time.Second))

	banner := make([]byte, 1024)
	n, _ := conn.Read(banner)

	service := commonPorts[port]
	if service == "" {
		service = "unknown"
	}

	info := &PortInfo{
		Port:     port,
		Service:  service,
		Protocol: "tcp",
		State:    "open",
	}

	if n > 0 {
		bannerStr := string(banner[:n])
		info.Banner = sanitizeBanner(bannerStr)
	}

	product, version := fingerprintService(info.Banner, port)
	info.Product = product
	info.Version = version

	if portProtocols[port] == "tcp/udp" {
		info.Protocol = "tcp/udp"
	}

	return info
}

func fingerprintService(banner string, port int) (product, version string) {
	banner = strings.ToLower(banner)
	switch port {
	case 80, 443, 8080, 8443:
		if strings.Contains(banner, "apache") {
			product = "Apache httpd"
			if idx := strings.Index(banner, "apache/"); idx >= 0 {
				version = extractAfter(banner[idx:], "/")
			}
		} else if strings.Contains(banner, "nginx") {
			product = "nginx"
			if idx := strings.Index(banner, "nginx/"); idx >= 0 {
				version = extractAfter(banner[idx:], "/")
			}
		} else if strings.Contains(banner, "iis") {
			product = "IIS"
		} else if strings.Contains(banner, "lighttpd") {
			product = "Lighttpd"
		}
	case 22:
		if strings.HasPrefix(banner, "ssh-") {
			product = "OpenSSH"
			parts := strings.SplitN(banner, "-", 3)
			if len(parts) >= 2 {
				version = parts[len(parts)-1]
			}
		}
	case 21:
		if strings.Contains(banner, "vsftpd") {
			product = "vsftpd"
		} else if strings.Contains(banner, "proftpd") {
			product = "ProFTPD"
		} else if strings.Contains(banner, "pure-ftpd") {
			product = "Pure-FTPd"
		}
	case 3306:
		product = "MySQL/MariaDB"
		version = strings.TrimSpace(banner)
	case 6379:
		product = "Redis"
		version = strings.TrimSpace(banner)
	case 27017:
		product = "MongoDB"
	}
	return
}

func extractAfter(s, sep string) string {
	parts := strings.SplitN(s, sep, 2)
	if len(parts) >= 2 {
		rest := strings.TrimSpace(parts[1])
		if idx := strings.IndexAny(rest, " \t\r\n"); idx >= 0 {
			return rest[:idx]
		}
		return rest
	}
	return ""
}

func sanitizeBanner(b string) string {
	clean := make([]byte, 0, len(b))
	for _, c := range []byte(b) {
		if c >= 32 && c < 127 || c == '\n' || c == '\r' || c == '\t' {
			clean = append(clean, c)
		} else {
			clean = append(clean, '.')
		}
	}
	if len(clean) > 512 {
		clean = clean[:512]
	}
	return string(clean)
}

func parseCIDR(cidr string) *net.IPNet {
	if strings.Contains(cidr, "/") {
		_, ipnet, err := net.ParseCIDR(cidr)
		if err == nil {
			return ipnet
		}
	} else {
		ip := net.ParseIP(cidr)
		if ip != nil {
			if ip.To4() != nil {
				_, ipnet, _ := net.ParseCIDR(ip.String() + "/24")
				return ipnet
			}
			_, ipnet, _ := net.ParseCIDR(ip.String() + "/64")
			return ipnet
		}
	}
	return nil
}

func generateIPs(ipnet *net.IPNet) []string {
	var ips []string
	ip := make(net.IP, len(ipnet.IP))
	copy(ip, ipnet.IP)
	ip = ip.Mask(ipnet.Mask)

	ones, bits := ipnet.Mask.Size()
	maxHosts := 1 << (bits - ones)

	if maxHosts > 1024 {
		maxHosts = 1024
	}

	for i := 0; i < maxHosts; i++ {
		ips = append(ips, ip.String())
		incIP(ip)
	}

	return ips
}

func incIP(ip net.IP) {
	for j := len(ip) - 1; j >= 0; j-- {
		ip[j]++
		if ip[j] > 0 {
			break
		}
	}
}

func emitJSON(v interface{}) {
	data, _ := json.MarshalIndent(v, "", "  ")
	fmt.Println(string(data))
}
