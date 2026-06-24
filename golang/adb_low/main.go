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
	Success  bool        `json:"success"`
	Command  string      `json:"command"`
	Output   string      `json:"output"`
	Error    string      `json:"error,omitempty"`
	Data     interface{} `json:"data,omitempty"`
	Elapsed  float64     `json:"elapsed_seconds,omitempty"`
	Device   string      `json:"device,omitempty"`
	Attempts int         `json:"attempts,omitempty"`
}

var (
	streamMode    bool
	targetDevices []string
	retryCount    = 1
	outputPath    string
)

func main() {
	defer func() {
		if r := recover(); r != nil {
			emitJSON(ADBResult{Success: false, Error: fmt.Sprintf("panic: %v", r)})
			os.Exit(2)
		}
	}()

	args := os.Args[1:]
	var commandArgs []string

	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--stream":
			streamMode = true
		case "--output":
			if i+1 < len(args) {
				outputPath = args[i+1]
				i++
			}
		case "--device":
			if i+1 < len(args) {
				targetDevices = append(targetDevices, args[i+1])
				i++
			}
		case "--retries":
			if i+1 < len(args) {
				retryCount, _ = strconv.Atoi(args[i+1])
				if retryCount < 1 {
					retryCount = 1
				}
				i++
			}
		default:
			commandArgs = append(commandArgs, args[i])
		}
	}

	if len(commandArgs) < 1 {
		usage()
		os.Exit(1)
	}

	command := commandArgs[0]
	rest := commandArgs[1:]

	switch command {
	case "devices":
		emitJSON(listDevices())
	case "info":
		if len(targetDevices) > 0 {
			emitMultiDevice(func(device string) ADBResult { return getDeviceInfo(device) })
		} else {
			emitJSON(getDeviceInfo(""))
		}
	case "shell":
		if len(rest) < 1 {
			emitJSON(ADBResult{Success: false, Error: "shell requires a command"})
			return
		}
		cmd := strings.Join(rest, " ")
		if len(targetDevices) > 0 {
			emitMultiDevice(func(device string) ADBResult { return runShell(device, cmd) })
		} else {
			emitJSON(runShell("", cmd))
		}
	case "install":
		if len(rest) < 1 {
			emitJSON(ADBResult{Success: false, Error: "install requires an APK path"})
			return
		}
		apk := rest[0]
		if len(targetDevices) > 0 {
			emitMultiDevice(func(device string) ADBResult { return installAPK(device, apk) })
		} else {
			emitJSON(installAPK("", apk))
		}
	case "screenshot":
		if len(targetDevices) > 0 {
			emitMultiDevice(func(device string) ADBResult { return takeScreenshot(device) })
		} else {
			emitJSON(takeScreenshot(""))
		}
	case "screenrecord":
		if len(targetDevices) > 0 {
			emitMultiDevice(func(device string) ADBResult { return screenRecord(device) })
		} else {
			emitJSON(screenRecord(""))
		}
	case "pull":
		if len(rest) < 1 {
			emitJSON(ADBResult{Success: false, Error: "pull requires a remote path"})
			return
		}
		localPath := ""
		if len(rest) > 1 {
			localPath = rest[1]
		}
		if len(targetDevices) > 0 {
			emitMultiDevice(func(device string) ADBResult { return pullFile(device, rest[0], localPath) })
		} else {
			emitJSON(pullFile("", rest[0], localPath))
		}
	case "push":
		if len(rest) < 2 {
			emitJSON(ADBResult{Success: false, Error: "push requires <local> <remote>"})
			return
		}
		if len(targetDevices) > 0 {
			emitMultiDevice(func(device string) ADBResult { return pushFile(device, rest[0], rest[1]) })
		} else {
			emitJSON(pushFile("", rest[0], rest[1]))
		}
	case "logcat":
		if len(targetDevices) > 0 {
			emitMultiDevice(func(device string) ADBResult { return captureLogcat(device) })
		} else {
			emitJSON(captureLogcat(""))
		}
	case "reboot":
		mode := "normal"
		if len(rest) > 0 {
			mode = rest[0]
		}
		if len(targetDevices) > 0 {
			emitMultiDevice(func(device string) ADBResult { return rebootDevice(device, mode) })
		} else {
			emitJSON(rebootDevice("", mode))
		}
	case "root":
		if len(targetDevices) > 0 {
			emitMultiDevice(func(device string) ADBResult { return checkRoot(device) })
		} else {
			emitJSON(checkRoot(""))
		}
	case "monitor":
		monitorDevices()
		return
	case "tcpip":
		if len(rest) < 1 {
			emitJSON(ADBResult{Success: false, Error: "tcpip requires a port"})
			return
		}
		if len(targetDevices) > 0 {
			emitMultiDevice(func(device string) ADBResult { return enableTCPIP(device, rest[0]) })
		} else {
			emitJSON(enableTCPIP("", rest[0]))
		}
	default:
		emitJSON(ADBResult{Success: false, Error: fmt.Sprintf("Unknown command: %s", command)})
	}

	if s, err := os.Stdout.Stat(); err == nil && (s.Mode()&os.ModeCharDevice) == 0 {
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, "Usage: %s [flags] <command> [args...]\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "Flags:\n")
	fmt.Fprintf(os.Stderr, "  --stream               Emit JSON line-by-line (streaming mode)\n")
	fmt.Fprintf(os.Stderr, "  --device <serial>      Target specific device(s), may repeat\n")
	fmt.Fprintf(os.Stderr, "  --retries <n>          Retry count on failure (default: 1)\n")
	fmt.Fprintf(os.Stderr, "  --output <path>        Write output to file\n")
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

func execADBWithDevice(device string, args ...string) (string, string, error) {
	if device != "" {
		fullArgs := append([]string{"-s", device}, args...)
		return execADB(fullArgs...)
	}
	return execADB(args...)
}

func execADBWithRetry(device string, retries int, args ...string) (string, string, error) {
	var lastOut, lastErr string
	var lastErrVal error
	for attempt := 1; attempt <= retries; attempt++ {
		stdout, stderr, err := execADBWithDevice(device, args...)
		if err == nil {
			return stdout, stderr, nil
		}
		lastOut, lastErr, lastErrVal = stdout, stderr, err
		if attempt < retries {
			time.Sleep(time.Duration(attempt) * time.Second)
		}
	}
	return lastOut, lastErr, lastErrVal
}

func emitJSON(v interface{}) {
	var data []byte
	if streamMode {
		data, _ = json.Marshal(v)
	} else {
		data, _ = json.MarshalIndent(v, "", "  ")
	}
	out := string(data)
	if outputPath != "" {
		f, err := os.OpenFile(outputPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err == nil {
			f.WriteString(out + "\n")
			f.Close()
		}
	}
	fmt.Println(out)
}

func emitMultiDevice(fn func(string) ADBResult) {
	devices := targetDevices
	if len(devices) == 0 {
		d := getActiveDevices()
		devices = d
	}
	if len(devices) == 0 {
		emitJSON(ADBResult{Success: false, Error: "No devices found"})
		return
	}
	var mu sync.Mutex
	var wg sync.WaitGroup
	for _, device := range devices {
		wg.Add(1)
		go func(d string) {
			defer wg.Done()
			r := fn(d)
			mu.Lock()
			emitJSON(r)
			mu.Unlock()
		}(device)
	}
	wg.Wait()
}

func getActiveDevices() []string {
	stdout, _, err := execADB("devices")
	if err != nil {
		return nil
	}
	lines := strings.Split(strings.TrimSpace(stdout), "\n")
	var devices []string
	for _, line := range lines[1:] {
		line = strings.TrimSpace(line)
		if strings.HasSuffix(line, "\tdevice") || strings.Contains(line, "device") {
			parts := strings.Fields(line)
			if len(parts) > 0 {
				devices = append(devices, parts[0])
			}
		}
	}
	return devices
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

func getDeviceInfo(device string) ADBResult {
	info := DeviceInfo{Serial: device}
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
		if device == "" {
			out, _, _ := execADB("get-serialno")
			mu.Lock()
			info.Serial = strings.TrimSpace(out)
			mu.Unlock()
		}
	})
	fetch(func() {
		out, _, _ := execADBWithDevice(device, "shell", "getprop", "ro.product.model")
		mu.Lock()
		info.Model = strings.TrimSpace(out)
		mu.Unlock()
	})
	fetch(func() {
		out, _, _ := execADBWithDevice(device, "shell", "getprop", "ro.build.version.release")
		mu.Lock()
		info.AndroidVer = strings.TrimSpace(out)
		mu.Unlock()
	})
	fetch(func() {
		out, _, _ := execADBWithDevice(device, "shell", "getprop", "ro.build.version.sdk")
		mu.Lock()
		info.SDKVer = strings.TrimSpace(out)
		mu.Unlock()
	})
	fetch(func() {
		out, _, _ := execADBWithDevice(device, "shell", "which", "su")
		mu.Lock()
		info.Rooted = strings.TrimSpace(out) != ""
		mu.Unlock()
	})
	fetch(func() {
		out, _, _ := execADBWithDevice(device, "shell", "dumpsys", "battery")
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
		out, _, _ := execADBWithDevice(device, "shell", "dumpsys", "window", "policy")
		mu.Lock()
		info.ScreenOn = strings.Contains(out, "screenState=ON") || strings.Contains(out, "mScreenOnFully=true")
		mu.Unlock()
	})
	fetch(func() {
		out, _, _ := execADBWithDevice(device, "shell", "getprop", "ro.product.manufacturer")
		mu.Lock()
		info.Manufacturer = strings.TrimSpace(out)
		mu.Unlock()
	})
	fetch(func() {
		out, _, _ := execADBWithDevice(device, "shell", "getprop", "ro.build.fingerprint")
		mu.Lock()
		info.BuildFinger = strings.TrimSpace(out)
		mu.Unlock()
	})
	fetch(func() {
		out, _, _ := execADBWithDevice(device, "shell", "getprop", "ro.product.cpu.abi")
		mu.Lock()
		info.CPUAbi = strings.TrimSpace(out)
		mu.Unlock()
	})
	fetch(func() {
		out, _, _ := execADBWithDevice(device, "shell", "cat", "/proc/meminfo")
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
		Device:  device,
	}
}

func runShell(device, cmd string) ADBResult {
	stdout, stderr, err := execADBWithRetry(device, retryCount, "shell", cmd)
	if err != nil {
		return ADBResult{Success: false, Command: cmd, Output: stdout, Error: stderr, Device: device}
	}
	lines := strings.Split(strings.TrimSpace(stdout), "\n")
	return ADBResult{
		Success: true,
		Command: cmd,
		Output:  stdout,
		Data:    map[string]interface{}{"lines": len(lines)},
		Device:  device,
	}
}

func installAPK(device, apkPath string) ADBResult {
	if _, err := os.Stat(apkPath); os.IsNotExist(err) {
		return ADBResult{Success: false, Command: "install", Error: fmt.Sprintf("file not found: %s", apkPath), Device: device}
	}
	start := time.Now()
	stdout, stderr, err := execADBWithRetry(device, retryCount, "install", "-r", "-t", apkPath)
	elapsed := time.Since(start).Seconds()

	if err != nil || strings.Contains(stderr, "Failure") {
		return ADBResult{
			Success: false,
			Command: fmt.Sprintf("install %s", apkPath),
			Output:  stdout,
			Error:   stderr,
			Elapsed: elapsed,
			Device:  device,
		}
	}
	return ADBResult{
		Success: true,
		Command: fmt.Sprintf("install %s", apkPath),
		Output:  stdout,
		Data:    map[string]interface{}{"apk": apkPath, "elapsed_seconds": elapsed},
		Elapsed: elapsed,
		Device:  device,
	}
}

func takeScreenshot(device string) ADBResult {
	ts := time.Now().Unix()
	remotePath := fmt.Sprintf("/sdcard/screenshot_%d.png", ts)
	stdout, stderr, err := execADBWithDevice(device, "shell", "screencap", "-p", remotePath)
	if err != nil {
		return ADBResult{Success: false, Error: stderr, Device: device}
	}

	os.MkdirAll("output", 0755)
	devicePrefix := ""
	if device != "" {
		devicePrefix = device + "_"
	}
	localPath := fmt.Sprintf("output/%sscreenshot_%d.png", devicePrefix, ts)
	_, pullStderr, pullErr := execADBWithDevice(device, "pull", remotePath, localPath)
	if pullErr != nil {
		return ADBResult{Success: false, Error: pullStderr, Device: device}
	}

	execADBWithDevice(device, "shell", "rm", remotePath)

	return ADBResult{
		Success: true,
		Command: "screenshot",
		Output:  stdout,
		Data:    map[string]interface{}{"local_path": localPath},
		Device:  device,
	}
}

func screenRecord(device string) ADBResult {
	ts := time.Now().Unix()
	remotePath := fmt.Sprintf("/sdcard/screenrecord_%d.mp4", ts)
	devicePrefix := ""
	if device != "" {
		devicePrefix = device + "_"
	}
	localPath := fmt.Sprintf("output/%sscreenrecord_%d.mp4", devicePrefix, ts)

	stdout, stderr, err := execADBWithDevice(device, "shell", "screenrecord", "--time-limit", "30", remotePath)
	if err != nil {
		return ADBResult{Success: false, Error: stderr, Device: device}
	}

	os.MkdirAll("output", 0755)
	time.Sleep(32 * time.Second)
	_, pushStderr, pushErr := execADBWithDevice(device, "pull", remotePath, localPath)
	if pushErr != nil {
		return ADBResult{Success: false, Error: pushStderr, Device: device}
	}

	execADBWithDevice(device, "shell", "rm", remotePath)

	return ADBResult{
		Success: true,
		Command: "screenrecord",
		Output:  stdout,
		Data:    map[string]interface{}{"local_path": localPath, "duration_seconds": 30},
		Device:  device,
	}
}

func pullFile(device, remotePath, localPath string) ADBResult {
	if localPath == "" {
		localPath = filepath.Base(remotePath)
	}
	stdout, stderr, err := execADBWithRetry(device, retryCount, "pull", remotePath, localPath)
	if err != nil {
		return ADBResult{Success: false, Error: stderr, Device: device}
	}
	return ADBResult{
		Success: true,
		Command: fmt.Sprintf("pull %s", remotePath),
		Output:  stdout,
		Data:    map[string]interface{}{"local_path": localPath},
		Device:  device,
	}
}

func pushFile(device, localPath, remotePath string) ADBResult {
	stdout, stderr, err := execADBWithRetry(device, retryCount, "push", localPath, remotePath)
	if err != nil {
		return ADBResult{Success: false, Error: stderr, Device: device}
	}
	return ADBResult{
		Success: true,
		Command: fmt.Sprintf("push %s %s", localPath, remotePath),
		Output:  stdout,
		Device:  device,
	}
}

func captureLogcat(device string) ADBResult {
	stdout, stderr, err := execADBWithDevice(device, "logcat", "-d", "-v", "threadtime")
	if err != nil {
		return ADBResult{Success: false, Error: stderr, Device: device}
	}
	lines := strings.Split(strings.TrimSpace(stdout), "\n")
	return ADBResult{
		Success: true,
		Command: "logcat",
		Output:  stdout,
		Data:    map[string]interface{}{"lines": len(lines)},
		Device:  device,
	}
}

func rebootDevice(device, mode string) ADBResult {
	var cmdStr string
	switch mode {
	case "bootloader":
		cmdStr = "reboot-bootloader"
	case "recovery":
		cmdStr = "shell reboot recovery"
	case "normal":
		cmdStr = "reboot"
	default:
		return ADBResult{Success: false, Error: fmt.Sprintf("unknown mode: %s (use: normal, bootloader, recovery)", mode), Device: device}
	}

	args := strings.Split(cmdStr, " ")
	stdout, stderr, err := execADBWithDevice(device, args...)
	if err != nil {
		return ADBResult{Success: false, Error: stderr, Device: device}
	}
	return ADBResult{Success: true, Command: cmdStr, Output: stdout, Device: device}
}

func checkRoot(device string) ADBResult {
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
			out, _, err := execADBWithDevice(device, "shell", c)
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
		Device:  device,
		Data: map[string]interface{}{
			"rooted":        rootDetected,
			"evidence":      evidence,
			"check_results": results,
		},
	}
}

func enableTCPIP(device, port string) ADBResult {
	stdout, stderr, err := execADBWithDevice(device, "tcpip", port)
	if err != nil {
		return ADBResult{Success: false, Error: stderr, Device: device}
	}
	return ADBResult{
		Success: true,
		Command: fmt.Sprintf("tcpip %s", port),
		Output:  stdout,
		Device:  device,
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
