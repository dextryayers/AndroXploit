package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type InstallResult struct {
	Success  bool    `json:"success"`
	ApkFile  string  `json:"apk_file"`
	Device   string  `json:"device,omitempty"`
	Error    string  `json:"error,omitempty"`
	Duration float64 `json:"duration_seconds"`
	Attempts int     `json:"attempts"`
}

type BatchResult struct {
	Total     int             `json:"total"`
	Success   int             `json:"success"`
	Failed    int             `json:"failed"`
	Results   []InstallResult `json:"results"`
	Duration  float64         `json:"total_duration_seconds"`
	Devices   []string        `json:"devices_found"`
	Error     string          `json:"error,omitempty"`
}

type DeviceEntry struct {
	Serial  string `json:"serial"`
	Status  string `json:"status"`
	Model   string `json:"model,omitempty"`
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	command := os.Args[1]

	switch command {
	case "install":
		cmdInstall()
	case "batch":
		cmdBatch()
	case "devices":
		cmdDevices()
	case "wait":
		cmdWait()
	case "uninstall":
		cmdUninstall()
	case "connect":
		cmdConnect()
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", command)
		usage()
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, "Usage: %s <command> [args]\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "Commands:\n")
	fmt.Fprintf(os.Stderr, "  install <apk>                 Install single APK with retry (3 attempts)\n")
	fmt.Fprintf(os.Stderr, "  batch <dir|apk1,apk2,...>    Install multiple APKs in parallel (concurrency=4)\n")
	fmt.Fprintf(os.Stderr, "  devices                      List connected devices with details\n")
	fmt.Fprintf(os.Stderr, "  wait                         Wait for device connection\n")
	fmt.Fprintf(os.Stderr, "  uninstall <package>          Uninstall package from device\n")
	fmt.Fprintf(os.Stderr, "  connect <host:port>          Connect to remote device via TCP/IP\n")
}

func cmdInstall() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: %s install <apk>\n", os.Args[0])
		os.Exit(1)
	}
	apk := os.Args[2]
	if _, err := os.Stat(apk); os.IsNotExist(err) {
		emitJSON(InstallResult{Success: false, ApkFile: apk, Error: fmt.Sprintf("file not found: %s", apk)})
		return
	}

	device := getTargetDevice()
	start := time.Now()

	var lastErr string
	var success bool
	maxRetries := 3

	for attempt := 1; attempt <= maxRetries; attempt++ {
		args := []string{"install", "-r", "-t", apk}
		if device != "" {
			args = append([]string{"-s", device}, args...)
		}

		cmd := exec.Command("adb", args...)
		output, err := cmd.CombinedOutput()

		if err == nil {
			success = true
			elapsed := time.Since(start).Seconds()
			emitJSON(InstallResult{
				Success:  true,
				ApkFile:  apk,
				Device:   device,
				Duration: elapsed,
				Attempts: attempt,
			})
			return
		}
		lastErr = string(output)

		if attempt < maxRetries {
			time.Sleep(time.Duration(attempt) * time.Second)
		}
	}

	emitJSON(InstallResult{
		Success:  success,
		ApkFile:  apk,
		Device:   device,
		Error:    fmt.Sprintf("failed after %d attempts: %s", maxRetries, lastErr),
		Duration: time.Since(start).Seconds(),
		Attempts: maxRetries,
	})
}

func cmdBatch() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: %s batch <dir|apk1,apk2,...>\n", os.Args[0])
		os.Exit(1)
	}

	input := os.Args[2]
	var apkFiles []string

	if info, err := os.Stat(input); err == nil && info.IsDir() {
		filepath.Walk(input, func(path string, fi os.FileInfo, err error) error {
			if err == nil && !fi.IsDir() && strings.HasSuffix(strings.ToLower(path), ".apk") {
				apkFiles = append(apkFiles, path)
			}
			return nil
		})
	} else {
		for _, s := range strings.Split(input, ",") {
			s = strings.TrimSpace(s)
			if s != "" {
				apkFiles = append(apkFiles, s)
			}
		}
	}

	if len(apkFiles) == 0 {
		emitJSON(BatchResult{Error: "no APK files found"})
		return
	}

	devices := listDevices()
	device := ""
	if len(devices) > 0 {
		device = devices[0]
	}

	start := time.Now()

	var mu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, 4)
	results := make([]InstallResult, len(apkFiles))

	for i, apk := range apkFiles {
		wg.Add(1)
		sem <- struct{}{}
		go func(idx int, path string) {
			defer wg.Done()
			defer func() { <-sem }()

			path = strings.TrimSpace(path)
			if _, err := os.Stat(path); os.IsNotExist(err) {
				mu.Lock()
				results[idx] = InstallResult{Success: false, ApkFile: path, Error: "file not found"}
				mu.Unlock()
				return
			}

			instStart := time.Now()
			args := []string{"install", "-r", "-t", path}
			if device != "" {
				args = append([]string{"-s", device}, args...)
			}
			cmd := exec.Command("adb", args...)
			output, err := cmd.CombinedOutput()

			mu.Lock()
			r := InstallResult{
				ApkFile:  path,
				Device:   device,
				Duration: time.Since(instStart).Seconds(),
			}
			if err != nil {
				r.Error = string(output)
			} else {
				r.Success = true
			}
			results[idx] = r
			mu.Unlock()
		}(i, apk)
	}
	wg.Wait()

	success := 0
	failed := 0
	for _, r := range results {
		if r.Success {
			success++
		} else {
			failed++
		}
	}

	emitJSON(BatchResult{
		Total:    len(results),
		Success:  success,
		Failed:   failed,
		Results:  results,
		Duration: time.Since(start).Seconds(),
		Devices:  devices,
	})
}

func cmdDevices() {
	stdout, _, err := execAdb("devices", "-l")
	if err != nil {
		emitJSON(map[string]interface{}{"success": false, "error": err.Error()})
		return
	}

	lines := strings.Split(strings.TrimSpace(stdout), "\n")
	var devices []DeviceEntry

	for _, line := range lines[1:] {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) >= 2 {
			entry := DeviceEntry{
				Serial: fields[0],
				Status: fields[1],
			}
			for _, f := range fields[2:] {
				if strings.HasPrefix(f, "model:") {
					entry.Model = strings.TrimPrefix(f, "model:")
				}
			}
			devices = append(devices, entry)
		}
	}

	emitJSON(map[string]interface{}{
		"success": true,
		"devices": devices,
		"count":   len(devices),
	})
}

func cmdWait() {
	fmt.Fprintf(os.Stderr, "Waiting for device...\n")
	cmd := exec.Command("adb", "wait-for-device")
	if err := cmd.Run(); err != nil {
		emitJSON(map[string]interface{}{"success": false, "error": err.Error()})
		return
	}
	emitJSON(map[string]interface{}{
		"success": true,
		"message": "device connected",
	})
}

func cmdUninstall() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: %s uninstall <package>\n", os.Args[0])
		os.Exit(1)
	}
	pkg := os.Args[2]
	stdout, stderr, err := execAdb("uninstall", pkg)
	if err != nil {
		emitJSON(map[string]interface{}{"success": false, "package": pkg, "error": stderr})
		return
	}
	emitJSON(map[string]interface{}{"success": true, "package": pkg, "output": stdout})
}

func cmdConnect() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: %s connect <host:port>\n", os.Args[0])
		os.Exit(1)
	}
	target := os.Args[2]
	stdout, stderr, err := execAdb("connect", target)
	if err != nil {
		emitJSON(map[string]interface{}{"success": false, "target": target, "error": stderr})
		return
	}
	emitJSON(map[string]interface{}{"success": true, "target": target, "output": stdout})
}

func getTargetDevice() string {
	devices := listDevices()
	if len(devices) > 0 {
		return devices[0]
	}
	return ""
}

func listDevices() []string {
	stdout, _, err := execAdb("devices")
	if err != nil {
		return nil
	}

	lines := strings.Split(strings.TrimSpace(stdout), "\n")
	var devices []string
	for _, line := range lines[1:] {
		line = strings.TrimSpace(line)
		if strings.Contains(line, "device") && !strings.Contains(line, "unauthorized") && !strings.Contains(line, "offline") {
			parts := strings.Fields(line)
			if len(parts) > 0 {
				devices = append(devices, parts[0])
			}
		}
	}
	return devices
}

func execAdb(args ...string) (string, string, error) {
	cmd := exec.Command("adb", args...)
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	return stdout.String(), stderr.String(), err
}

func emitJSON(v interface{}) {
	data, _ := json.MarshalIndent(v, "", "  ")
	fmt.Println(string(data))
}
