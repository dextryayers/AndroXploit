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
	Total    int             `json:"total"`
	Success  int             `json:"success"`
	Failed   int             `json:"failed"`
	Results  []InstallResult `json:"results"`
	Duration float64         `json:"total_duration_seconds"`
	Devices  []string        `json:"devices_found"`
	Error    string          `json:"error,omitempty"`
}

type DeviceEntry struct {
	Serial string `json:"serial"`
	Status string `json:"status"`
	Model  string `json:"model,omitempty"`
}

var (
	streamMode   bool
	outputPath   string
	maxRetries   = 3
	concurrency  = 4
	targetDevice string
)

func main() {
	defer func() {
		if r := recover(); r != nil {
			emitJSON(map[string]interface{}{"success": false, "error": fmt.Sprintf("panic: %v", r)})
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
				targetDevice = args[i+1]
				i++
			}
		case "--retries":
			if i+1 < len(args) {
				maxRetries, _ = fmt.Sscanf(args[i+1], "%d", &maxRetries)
				if maxRetries < 1 {
					maxRetries = 1
				}
				i++
			}
		case "--concurrency":
			if i+1 < len(args) {
				fmt.Sscanf(args[i+1], "%d", &concurrency)
				if concurrency < 1 {
					concurrency = 1
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
	case "install":
		if len(rest) < 1 {
			emitJSON(InstallResult{Success: false, Error: "APK path required"})
			return
		}
		emitJSON(cmdInstall(rest[0]))
	case "batch":
		if len(rest) < 1 {
			emitJSON(BatchResult{Error: "directory or APK list required"})
			return
		}
		emitJSON(cmdBatch(rest[0]))
	case "devices":
		cmdDevices()
	case "wait":
		cmdWait()
	case "uninstall":
		if len(rest) < 1 {
			emitJSON(map[string]interface{}{"success": false, "error": "package name required"})
			return
		}
		emitJSON(cmdUninstall(rest[0]))
	case "connect":
		if len(rest) < 1 {
			emitJSON(map[string]interface{}{"success": false, "error": "host:port required"})
			return
		}
		emitJSON(cmdConnect(rest[0]))
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", command)
		usage()
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, "Usage: %s [flags] <command> [args]\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "Flags:\n")
	fmt.Fprintf(os.Stderr, "  --stream              JSON line-by-line output\n")
	fmt.Fprintf(os.Stderr, "  --output <path>       Write output to file\n")
	fmt.Fprintf(os.Stderr, "  --device <serial>     Target specific device\n")
	fmt.Fprintf(os.Stderr, "  --retries <n>         Max retries per install (default: 3)\n")
	fmt.Fprintf(os.Stderr, "  --concurrency <n>     Batch install concurrency (default: 4)\n")
	fmt.Fprintf(os.Stderr, "Commands:\n")
	fmt.Fprintf(os.Stderr, "  install <apk>                 Install single APK with retry\n")
	fmt.Fprintf(os.Stderr, "  batch <dir|apk1,apk2,...>    Install multiple APKs in parallel\n")
	fmt.Fprintf(os.Stderr, "  devices                      List connected devices\n")
	fmt.Fprintf(os.Stderr, "  wait                         Wait for device connection\n")
	fmt.Fprintf(os.Stderr, "  uninstall <package>          Uninstall package\n")
	fmt.Fprintf(os.Stderr, "  connect <host:port>          Connect to remote device\n")
}

func execAdb(args ...string) (string, string, error) {
	cmd := exec.Command("adb", args...)
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	return stdout.String(), stderr.String(), err
}

func execAdbWithRetry(device string, args []string, retries int) (string, string, error) {
	var lastOut, lastErr string
	var lastErrVal error
	for attempt := 1; attempt <= retries; attempt++ {
		cmdArgs := args
		if device != "" {
			cmdArgs = append([]string{"-s", device}, args...)
		}
		stdout, stderr, err := execAdb(cmdArgs...)
		if err == nil {
			return stdout, stderr, nil
		}
		lastOut, lastErr, lastErrVal = stdout, stderr, err
		if attempt < retries {
			time.Sleep(time.Duration(attempt) * 2 * time.Second)
		}
	}
	return lastOut, lastErr, lastErrVal
}

func listConnectedDevices() []string {
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

func cmdInstall(apk string) InstallResult {
	if _, err := os.Stat(apk); os.IsNotExist(err) {
		return InstallResult{Success: false, ApkFile: apk, Error: fmt.Sprintf("file not found: %s", apk)}
	}

	device := targetDevice
	if device == "" {
		devices := listConnectedDevices()
		if len(devices) > 0 {
			device = devices[0]
		}
	}

	start := time.Now()
	args := []string{"install", "-r", "-t", apk}
	_, stderr, err := execAdbWithRetry(device, args, maxRetries)

	elapsed := time.Since(start).Seconds()
	if err != nil || strings.Contains(stderr, "Failure") {
		return InstallResult{
			Success:  false,
			ApkFile:  apk,
			Device:   device,
			Error:    stderr,
			Duration: elapsed,
			Attempts: maxRetries,
		}
	}
	return InstallResult{
		Success:  true,
		ApkFile:  apk,
		Device:   device,
		Duration: elapsed,
		Attempts: 1,
	}
}

func cmdBatch(input string) BatchResult {
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
		return BatchResult{Error: "no APK files found"}
	}

	devices := listConnectedDevices()
	device := targetDevice
	if device == "" && len(devices) > 0 {
		device = devices[0]
	}

	start := time.Now()
	var mu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, concurrency)
	results := make([]InstallResult, len(apkFiles))

	for i, apk := range apkFiles {
		wg.Add(1)
		sem <- struct{}{}
		go func(idx int, path string) {
			defer wg.Done()
			defer func() { <-sem }()

			if _, err := os.Stat(path); os.IsNotExist(err) {
				mu.Lock()
				results[idx] = InstallResult{Success: false, ApkFile: path, Error: "file not found"}
				mu.Unlock()
				return
			}

			instStart := time.Now()
			args := []string{"install", "-r", "-t", path}
			_, stderr, err := execAdbWithRetry(device, args, maxRetries)

			r := InstallResult{
				ApkFile:  path,
				Device:   device,
				Duration: time.Since(instStart).Seconds(),
				Attempts: maxRetries,
			}
			if err != nil || strings.Contains(stderr, "Failure") {
				r.Error = stderr
			} else {
				r.Success = true
				r.Attempts = 1
			}
			mu.Lock()
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

	return BatchResult{
		Total:    len(results),
		Success:  success,
		Failed:   failed,
		Results:  results,
		Duration: time.Since(start).Seconds(),
		Devices:  devices,
	}
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
			entry := DeviceEntry{Serial: fields[0], Status: fields[1]}
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

func cmdUninstall(pkg string) map[string]interface{} {
	args := []string{"uninstall", pkg}
	if targetDevice != "" {
		args = append([]string{"-s", targetDevice}, args...)
	}
	stdout, stderr, err := execAdb(args...)
	if err != nil {
		return map[string]interface{}{"success": false, "package": pkg, "error": stderr}
	}
	return map[string]interface{}{"success": true, "package": pkg, "output": stdout}
}

func cmdConnect(target string) map[string]interface{} {
	stdout, stderr, err := execAdb("connect", target)
	if err != nil {
		return map[string]interface{}{"success": false, "target": target, "error": stderr}
	}
	return map[string]interface{}{"success": true, "target": target, "output": stdout}
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
