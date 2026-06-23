package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

type DeviceInfo struct {
	Serial       string `json:"serial"`
	Model        string `json:"model"`
	AndroidVer   string `json:"android_version"`
	SDKVer       string `json:"sdk_version"`
	BatteryLevel int    `json:"battery_level"`
	Rooted       bool   `json:"rooted"`
	ScreenOn     bool   `json:"screen_on"`
	Manufacturer string `json:"manufacturer,omitempty"`
	BuildFinger  string `json:"build_fingerprint,omitempty"`
	CPUAbi       string `json:"cpu_abi,omitempty"`
	TotalMem     int64  `json:"total_memory_kb,omitempty"`
}

type ADBResult struct {
	Success bool        `json:"success"`
	Command string      `json:"command"`
	Output  string      `json:"output"`
	Error   string      `json:"error,omitempty"`
	Data    interface{} `json:"data,omitempty"`
	Elapsed float64     `json:"elapsed_seconds,omitempty"`
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	command := os.Args[1]
	var result ADBResult
	start := time.Now()

	switch command {
	case "devices":
		result = listDevices()
	case "info":
		result = getDeviceInfo()
	case "shell":
		if len(os.Args) < 3 {
			result = ADBResult{Success: false, Error: "shell requires a command argument"}
		} else {
			result = runShell(strings.Join(os.Args[2:], " "))
		}
	case "install":
		if len(os.Args) < 3 {
			result = ADBResult{Success: false, Error: "install requires an APK path"}
		} else {
			result = installAPK(os.Args[2])
		}
	case "screenshot":
		result = takeScreenshot()
	case "screenrecord":
		result = screenRecord()
	case "pull":
		if len(os.Args) < 3 {
			result = ADBResult{Success: false, Error: "pull requires a remote path"}
		} else {
			result = pullFile(os.Args[2])
		}
	case "push":
		if len(os.Args) < 4 {
			result = ADBResult{Success: false, Error: "push requires <local> <remote>"}
		} else {
			result = pushFile(os.Args[2], os.Args[3])
		}
	case "logcat":
		result = captureLogcat()
	case "reboot":
		if len(os.Args) < 3 {
			result = ADBResult{Success: false, Error: "reboot requires mode: normal|bootloader|recovery"}
		} else {
			result = rebootDevice(os.Args[2])
		}
	case "root":
		result = checkRoot()
	case "monitor":
		monitorDevices()
		return
	case "tcpip":
		if len(os.Args) < 3 {
			result = ADBResult{Success: false, Error: "tcpip requires a port"}
		} else {
			result = enableTCPIP(os.Args[2])
		}
	default:
		result = ADBResult{Success: false, Error: fmt.Sprintf("Unknown command: %s", command)}
	}

	result.Elapsed = time.Since(start).Seconds()
	emitJSON(result)
}

func usage() {
	fmt.Fprintf(os.Stderr, "Usage: %s <command> [args...]\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "Commands:\n")
	fmt.Fprintf(os.Stderr, "  devices                   List connected devices\n")
	fmt.Fprintf(os.Stderr, "  info                      Get detailed device info\n")
	fmt.Fprintf(os.Stderr, "  shell <cmd>               Run shell command\n")
	fmt.Fprintf(os.Stderr, "  install <apk>             Install APK\n")
	fmt.Fprintf(os.Stderr, "  screenshot                Take screenshot\n")
	fmt.Fprintf(os.Stderr, "  screenrecord              Record device screen (30s)\n")
	fmt.Fprintf(os.Stderr, "  pull <remote> [local]     Pull file from device\n")
	fmt.Fprintf(os.Stderr, "  push <local> <remote>     Push file to device\n")
	fmt.Fprintf(os.Stderr, "  logcat                    Capture logcat output\n")
	fmt.Fprintf(os.Stderr, "  reboot <mode>             Reboot device (normal/bootloader/recovery)\n")
	fmt.Fprintf(os.Stderr, "  root                      Check root status\n")
	fmt.Fprintf(os.Stderr, "  monitor                   Monitor device connections (live)\n")
	fmt.Fprintf(os.Stderr, "  tcpip <port>              Restart ADB in TCP/IP mode\n")
}

func execADB(args ...string) (string, string, error) {
	cmd := exec.Command("adb", args...)
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	return stdout.String(), stderr.String(), err
}

func listDevices() ADBResult {
	stdout, stderr, err := execADB("devices", "-l")
	if err != nil {
		return ADBResult{Success: false, Output: stdout, Error: stderr}
	}

	lines := strings.Split(strings.TrimSpace(stdout), "\n")
	type devInfo struct {
		Serial string `json:"serial"`
		Status string `json:"status"`
		Model  string `json:"model,omitempty"`
	}
	var devices []devInfo
	for _, line := range lines[1:] {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.Fields(line)
		d := devInfo{Serial: parts[0]}
		if len(parts) >= 2 {
			d.Status = parts[1]
		}
		for _, p := range parts[2:] {
			if strings.HasPrefix(p, "model:") {
				d.Model = strings.TrimPrefix(p, "model:")
			}
		}
		devices = append(devices, d)
	}
	return ADBResult{
		Success: true,
		Command: "devices",
		Output:  stdout,
		Data:    map[string]interface{}{"devices": devices, "count": len(devices)},
	}
}

func getDeviceInfo() ADBResult {
	info := DeviceInfo{}
	var wg sync.WaitGroup
	var mu sync.Mutex

	fetch := func(fn func()) {
		wg.Add(1)
		go func() {
			defer wg.Done()
			fn()
		}()
	}

	fetch(func() {
		out, _, _ := execADB("get-serialno")
		mu.Lock()
		info.Serial = strings.TrimSpace(out)
		mu.Unlock()
	})
	fetch(func() {
		out, _, _ := execADB("shell", "getprop", "ro.product.model")
		mu.Lock()
		info.Model = strings.TrimSpace(out)
		mu.Unlock()
	})
	fetch(func() {
		out, _, _ := execADB("shell", "getprop", "ro.build.version.release")
		mu.Lock()
		info.AndroidVer = strings.TrimSpace(out)
		mu.Unlock()
	})
	fetch(func() {
		out, _, _ := execADB("shell", "getprop", "ro.build.version.sdk")
		mu.Lock()
		info.SDKVer = strings.TrimSpace(out)
		mu.Unlock()
	})
	fetch(func() {
		out, _, _ := execADB("shell", "which", "su")
		mu.Lock()
		info.Rooted = strings.TrimSpace(out) != ""
		mu.Unlock()
	})
	fetch(func() {
		out, _, _ := execADB("shell", "dumpsys", "battery")
		for _, line := range strings.Split(out, "\n") {
			if strings.Contains(line, "level:") {
				parts := strings.Split(line, ":")
				if len(parts) == 2 {
					val, _ := strconv.Atoi(strings.TrimSpace(parts[1]))
					mu.Lock()
					info.BatteryLevel = val
					mu.Unlock()
				}
				break
			}
		}
	})
	fetch(func() {
		out, _, _ := execADB("shell", "dumpsys", "window", "policy")
		mu.Lock()
		info.ScreenOn = strings.Contains(out, "screenState=ON") || strings.Contains(out, "mScreenOnFully=true")
		mu.Unlock()
	})
	fetch(func() {
		out, _, _ := execADB("shell", "getprop", "ro.product.manufacturer")
		mu.Lock()
		info.Manufacturer = strings.TrimSpace(out)
		mu.Unlock()
	})
	fetch(func() {
		out, _, _ := execADB("shell", "getprop", "ro.build.fingerprint")
		mu.Lock()
		info.BuildFinger = strings.TrimSpace(out)
		mu.Unlock()
	})
	fetch(func() {
		out, _, _ := execADB("shell", "getprop", "ro.product.cpu.abi")
		mu.Lock()
		info.CPUAbi = strings.TrimSpace(out)
		mu.Unlock()
	})
	fetch(func() {
		out, _, _ := execADB("shell", "cat", "/proc/meminfo")
		for _, line := range strings.Split(out, "\n") {
			if strings.HasPrefix(line, "MemTotal:") {
				parts := strings.Fields(line)
				if len(parts) >= 2 {
					val, _ := strconv.ParseInt(parts[1], 10, 64)
					mu.Lock()
					info.TotalMem = val
					mu.Unlock()
				}
				break
			}
		}
	})
	wg.Wait()

	return ADBResult{
		Success: true,
		Command: "info",
		Data:    info,
	}
}

func runShell(cmd string) ADBResult {
	stdout, stderr, err := execADB("shell", cmd)
	if err != nil {
		return ADBResult{Success: false, Command: cmd, Output: stdout, Error: stderr}
	}
	lines := strings.Split(strings.TrimSpace(stdout), "\n")
	return ADBResult{
		Success: true,
		Command: cmd,
		Output:  stdout,
		Data:    map[string]interface{}{"lines": len(lines)},
	}
}

func installAPK(apkPath string) ADBResult {
	start := time.Now()
	stdout, stderr, err := execADB("install", "-r", "-t", apkPath)
	elapsed := time.Since(start).Seconds()

	if err != nil || strings.Contains(stderr, "Failure") {
		return ADBResult{
			Success: false,
			Command: fmt.Sprintf("install %s", apkPath),
			Output:  stdout,
			Error:   stderr,
		}
	}
	return ADBResult{
		Success: true,
		Command: fmt.Sprintf("install %s", apkPath),
		Output:  stdout,
		Data:    map[string]interface{}{"apk": apkPath, "elapsed_seconds": elapsed},
	}
}

func takeScreenshot() ADBResult {
	ts := time.Now().Unix()
	remotePath := fmt.Sprintf("/sdcard/screenshot_%d.png", ts)
	stdout, stderr, err := execADB("shell", "screencap", "-p", remotePath)
	if err != nil {
		return ADBResult{Success: false, Error: stderr}
	}

	os.MkdirAll("output", 0755)
	localPath := fmt.Sprintf("output/screenshot_%d.png", ts)
	_, pullStderr, pullErr := execADB("pull", remotePath, localPath)
	if pullErr != nil {
		return ADBResult{Success: false, Error: pullStderr}
	}

	execADB("shell", "rm", remotePath)

	return ADBResult{
		Success: true,
		Command: "screenshot",
		Output:  stdout,
		Data:    map[string]interface{}{"local_path": localPath},
	}
}

func screenRecord() ADBResult {
	ts := time.Now().Unix()
	remotePath := fmt.Sprintf("/sdcard/screenrecord_%d.mp4", ts)
	localPath := fmt.Sprintf("output/screenrecord_%d.mp4", ts)

	stdout, stderr, err := execADB("shell", "screenrecord", "--time-limit", "30", remotePath)
	if err != nil {
		return ADBResult{Success: false, Error: stderr}
	}

	os.MkdirAll("output", 0755)
	time.Sleep(32 * time.Second)
	_, pushStderr, pushErr := execADB("pull", remotePath, localPath)
	if pushErr != nil {
		return ADBResult{Success: false, Error: pushStderr}
	}

	execADB("shell", "rm", remotePath)

	return ADBResult{
		Success: true,
		Command: "screenrecord",
		Output:  stdout,
		Data:    map[string]interface{}{"local_path": localPath, "duration_seconds": 30},
	}
}

func pullFile(remotePath string) ADBResult {
	localPath := filepath.Base(remotePath)
	if len(os.Args) > 3 {
		localPath = os.Args[3]
	}
	stdout, stderr, err := execADB("pull", remotePath, localPath)
	if err != nil {
		return ADBResult{Success: false, Error: stderr}
	}
	return ADBResult{
		Success: true,
		Command: fmt.Sprintf("pull %s", remotePath),
		Output:  stdout,
		Data:    map[string]interface{}{"local_path": localPath},
	}
}

func pushFile(localPath, remotePath string) ADBResult {
	stdout, stderr, err := execADB("push", localPath, remotePath)
	if err != nil {
		return ADBResult{Success: false, Error: stderr}
	}
	return ADBResult{
		Success: true,
		Command: fmt.Sprintf("push %s %s", localPath, remotePath),
		Output:  stdout,
	}
}

func captureLogcat() ADBResult {
	stdout, stderr, err := execADB("logcat", "-d", "-v", "threadtime")
	if err != nil {
		return ADBResult{Success: false, Error: stderr}
	}
	lines := strings.Split(strings.TrimSpace(stdout), "\n")
	return ADBResult{
		Success: true,
		Command: "logcat",
		Output:  stdout,
		Data:    map[string]interface{}{"lines": len(lines)},
	}
}

func rebootDevice(mode string) ADBResult {
	cmd := "reboot"
	switch mode {
	case "bootloader":
		cmd = "reboot-bootloader"
	case "recovery":
		cmd = "reboot recovery"
	case "normal":
		cmd = "reboot"
	default:
		return ADBResult{Success: false, Error: fmt.Sprintf("unknown mode: %s (use: normal, bootloader, recovery)", mode)}
	}

	if cmd == "reboot recovery" {
		stdout, stderr, err := execADB("shell", cmd)
		if err != nil {
			return ADBResult{Success: false, Error: stderr}
		}
		return ADBResult{Success: true, Command: cmd, Output: stdout}
	}

	stdout, stderr, err := execADB(cmd)
	if err != nil {
		return ADBResult{Success: false, Error: stderr}
	}
	return ADBResult{Success: true, Command: cmd, Output: stdout}
}

func checkRoot() ADBResult {
	var wg sync.WaitGroup
	var mu sync.Mutex
	results := make(map[string]bool)

	checks := []string{
		"which su",
		"ls -la /system/bin/su",
		"ls -la /system/xbin/su",
		"ls -la /sbin/su",
		"ls -la /su/bin/su",
		"test -f /system/app/Superuser.apk",
		"test -f /system/etc/init.d/99SuperSUDaemon",
		"getprop ro.debuggable",
	}

	for _, check := range checks {
		wg.Add(1)
		go func(c string) {
			defer wg.Done()
			out, _, err := execADB("shell", c)
			mu.Lock()
			results[c] = err == nil && strings.TrimSpace(out) != ""
			mu.Unlock()
		}(check)
	}
	wg.Wait()

	rootDetected := false
	var evidence []string
	for check, found := range results {
		if found {
			rootDetected = true
			evidence = append(evidence, check)
		}
	}

	return ADBResult{
		Success: true,
		Command: "root",
		Data: map[string]interface{}{
			"rooted":        rootDetected,
			"evidence":      evidence,
			"check_results": results,
		},
	}
}

func enableTCPIP(port string) ADBResult {
	stdout, stderr, err := execADB("tcpip", port)
	if err != nil {
		return ADBResult{Success: false, Error: stderr}
	}
	return ADBResult{
		Success: true,
		Command: fmt.Sprintf("tcpip %s", port),
		Output:  stdout,
	}
}

func monitorDevices() {
	fmt.Fprintf(os.Stderr, "Monitoring device connections... (Ctrl+C to stop)\n")
	prev := ""
	for {
		stdout, _, err := execADB("devices")
		if err == nil && stdout != prev {
			prev = stdout
			lines := strings.Split(strings.TrimSpace(stdout), "\n")
			type monDev struct {
				Serial string `json:"serial"`
				Status string `json:"status"`
			}
			var devs []monDev
			for _, line := range lines[1:] {
				line = strings.TrimSpace(line)
				if line == "" {
					continue
				}
				parts := strings.Fields(line)
				s := parts[0]
				st := ""
				if len(parts) >= 2 {
					st = parts[1]
				}
				devs = append(devs, monDev{Serial: s, Status: st})
			}
			emitJSON(map[string]interface{}{
				"event":   "device_change",
				"devices": devs,
				"count":   len(devs),
			})
		}
		time.Sleep(2 * time.Second)
	}
}

func emitJSON(v interface{}) {
	data, _ := json.MarshalIndent(v, "", "  ")
	fmt.Println(string(data))
}
