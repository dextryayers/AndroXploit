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

type ScanResult struct {
	Host         string     `json:"host"`
	IP           string     `json:"ip"`
	PortsOpen    []OpenPort `json:"ports_open"`
	PortsScanned []int      `json:"ports_scanned"`
	Duration     string     `json:"duration"`
	Reachable    bool       `json:"reachable"`
	Error        string     `json:"error,omitempty"`
	ScanType     string     `json:"scan_type"`
	TotalPorts   int        `json:"total_ports"`
	OpenCount    int        `json:"open_count"`
}

type OpenPort struct {
	Port    int    `json:"port"`
	Service string `json:"service"`
	State   string `json:"state"`
	Banner  string `json:"banner,omitempty"`
}

type SpeedConfig struct {
	Concurrency int
	Timeout     time.Duration
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
	9200: "Elasticsearch", 9300: "Elasticsearch-Node",
	11211: "Memcached", 27017: "MongoDB", 5000: "Docker",
	5433: "PostgreSQL-Alt", 5984: "CouchDB", 6375: "Redis-Alt",
	6443: "HTTPS-Alt2", 7474: "Neo4j", 8000: "HTTP-Alt2",
	8001: "HTTP-Alt3", 8444: "HTTPS-Alt3", 9000: "HTTP-Alt4",
	9042: "Cassandra", 9160: "Cassandra-Thrift",
	50070: "Hadoop-NN", 50075: "Hadoop-DN",
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	host := os.Args[1]
	ports := getPorts(os.Args)

	start := time.Now()
	result := scan(host, ports)
	result.Duration = time.Since(start).Truncate(time.Millisecond).String()
	result.TotalPorts = len(ports)
	result.OpenCount = len(result.PortsOpen)

	emitJSON(result)
}

func usage() {
	fmt.Fprintf(os.Stderr, "Usage: %s <host> [ports] [options]\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "  host: IP address or hostname\n")
	fmt.Fprintf(os.Stderr, "  ports: comma-separated (22,80,443) or range (1-1024) or 'top' or 'fast' or 'all'\n")
	fmt.Fprintf(os.Stderr, "  options: --speed=<1-5> (1=slow/stealth, 5=fastest)\n")
	fmt.Fprintf(os.Stderr, "Examples:\n")
	fmt.Fprintf(os.Stderr, "  %s 192.168.1.1 top\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "  %s 10.0.0.1 1-1000 --speed=5\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "  %s scanme.nmap.org fast\n", os.Args[0])
}

func getPorts(args []string) []int {
	if len(args) < 3 {
		return getTopPorts()
	}

	switch args[2] {
	case "top":
		return getTopPorts()
	case "fast":
		return getFastPorts()
	case "all":
		ports := make([]int, 65535)
		for i := 0; i < 65535; i++ {
			ports[i] = i + 1
		}
		return ports
	default:
		if strings.Contains(args[2], "-") {
			parts := strings.SplitN(args[2], "-", 2)
			start := parseInt(parts[0])
			end := parseInt(parts[1])
			if start > 0 && end > 0 && end >= start && end <= 65535 {
				ports := make([]int, end-start+1)
				for i := start; i <= end; i++ {
					ports[i-start] = i
				}
				return ports
			}
			fmt.Fprintf(os.Stderr, "Invalid range: %s\n", args[2])
			return getTopPorts()
		}
		if strings.Contains(args[2], ",") {
			parts := strings.Split(args[2], ",")
			ports := make([]int, 0)
			for _, p := range parts {
				n := parseInt(strings.TrimSpace(p))
				if n > 0 {
					ports = append(ports, n)
				}
			}
			if len(ports) == 0 {
				return getTopPorts()
			}
			return ports
		}
		n := parseInt(args[2])
		if n > 0 {
			return []int{n}
		}
		return getTopPorts()
	}
}

func getTopPorts() []int {
	ports := make([]int, 0, len(commonPorts))
	for p := range commonPorts {
		ports = append(ports, p)
	}
	sort.Ints(ports)
	return ports
}

func getFastPorts() []int {
	fastPorts := []int{22, 80, 443, 5555, 8080, 8443, 3306, 3389, 5900, 6379, 27017, 1433, 5432, 25, 21, 23, 110, 445, 139, 135}
	sort.Ints(fastPorts)
	return fastPorts
}

func parseInt(s string) int {
	n := 0
	for _, c := range s {
		if c < '0' || c > '9' {
			return 0
		}
		n = n*10 + int(c-'0')
	}
	return n
}

func getSpeedConfig() SpeedConfig {
	cfg := SpeedConfig{
		Concurrency: 100,
		Timeout:     2 * time.Second,
	}
	for _, arg := range os.Args {
		if strings.HasPrefix(arg, "--speed=") {
			level := parseInt(arg[8:])
			switch level {
			case 1:
				cfg.Concurrency = 10
				cfg.Timeout = 5 * time.Second
			case 2:
				cfg.Concurrency = 30
				cfg.Timeout = 3 * time.Second
			case 3:
				cfg.Concurrency = 100
				cfg.Timeout = 2 * time.Second
			case 4:
				cfg.Concurrency = 300
				cfg.Timeout = 1 * time.Second
			case 5:
				cfg.Concurrency = 500
				cfg.Timeout = 500 * time.Millisecond
			}
		}
		if arg == "--stealth" {
			cfg.Concurrency = 5
			cfg.Timeout = 5 * time.Second
		}
	}
	return cfg
}

func scan(host string, ports []int) *ScanResult {
	result := &ScanResult{
		Host:         host,
		PortsScanned: ports,
		ScanType:     "TCP Connect",
	}

	resolved := host
	ip, err := net.ResolveIPAddr("ip", host)
	if err != nil {
		result.Error = fmt.Sprintf("Host unreachable: %v", err)
		result.Reachable = false
		return result
	}
	result.IP = ip.String()
	result.Reachable = true

	if ip.IP.To4() == nil {
		resolved = fmt.Sprintf("[%s]", host)
	}

	speed := getSpeedConfig()
	result.ScanType = fmt.Sprintf("TCP Connect (concurrency=%d, timeout=%v)", speed.Concurrency, speed.Timeout)

	var mu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, speed.Concurrency)

	for _, port := range ports {
		wg.Add(1)
		sem <- struct{}{}
		go func(p int) {
			defer wg.Done()
			defer func() { <-sem }()

			addr := net.JoinHostPort(resolved, fmt.Sprintf("%d", p))
			conn, err := net.DialTimeout("tcp", addr, speed.Timeout)

			if err == nil {
				info := OpenPort{
					Port:    p,
					Service: "unknown",
					State:   "open",
				}

				conn.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
				banner := make([]byte, 256)
				n, _ := conn.Read(banner)
				conn.Close()

				if n > 0 {
					info.Banner = sanitizeBanner(string(banner[:n]))
				}

				if svc, ok := commonPorts[p]; ok {
					info.Service = svc
				}

				mu.Lock()
				result.PortsOpen = append(result.PortsOpen, info)
				mu.Unlock()
			}
		}(port)
	}
	wg.Wait()

	sort.Slice(result.PortsOpen, func(i, j int) bool {
		return result.PortsOpen[i].Port < result.PortsOpen[j].Port
	})

	result.PortsScanned = ports

	return result
}

func sanitizeBanner(b string) string {
	clean := make([]byte, 0, len(b))
	for _, c := range []byte(b) {
		if c >= 32 && c < 127 {
			clean = append(clean, c)
		} else if c == '\n' || c == '\r' {
			clean = append(clean, ' ')
		}
	}
	if len(clean) > 200 {
		clean = clean[:200]
	}
	return string(clean)
}

func emitJSON(v interface{}) {
	data, _ := json.MarshalIndent(v, "", "  ")
	fmt.Println(string(data))
}
