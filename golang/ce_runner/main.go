package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

type EngineResult struct {
	Name     string            `json:"name"`
	Status   string            `json:"status"`
	Files    int               `json:"files,omitempty"`
	Output   string            `json:"output,omitempty"`
	RawJSON  string            `json:"-"`
	Duration string            `json:"duration,omitempty"`
	Size     int64             `json:"size_bytes,omitempty"`
}

type AggregateReport struct {
	Device           string                  `json:"device"`
	StartTime        string                  `json:"start_time"`
	EndTime          string                  `json:"end_time"`
	Duration         string                  `json:"duration"`
	TotalEngines     int                     `json:"total_engines"`
	SuccessfulEngines int                    `json:"successful_engines"`
	TotalFiles       int64                   `json:"total_files"`
	TotalBytes       int64                   `json:"total_bytes"`
	Engines          []EngineResult          `json:"engines"`
	DirectoryTree    []DirectoryEntry        `json:"directory_tree,omitempty"`
}

type DirectoryEntry struct {
	Path    string `json:"path"`
	Size    int64  `json:"size"`
	Files   int    `json:"files"`
	IsDir   bool   `json:"is_dir"`
}

func main() {
	device := flag.String("device", "", "ADB device serial")
	outputDir := flag.String("output", "./ce_aggregate", "Local output directory")
	remoteDir := flag.String("remote", "/data/local/tmp", "Remote directory on device")
	parallel := flag.Int("parallel", 4, "Parallel engine execution count")
	verbose := flag.Bool("verbose", false, "Verbose output")
	skipBuild := flag.Bool("skip-build", false, "Skip build step")
	flag.Parse()

	banner := `
╔══════════════════════════════════════════════╗
║          AndroXploit - Crawler v2.0          ║
║        Total Android Extraction Engine       ║
╚══════════════════════════════════════════════╝`
	fmt.Println(banner)

	startTime := time.Now()

	// Detect ADB
	if _, err := exec.LookPath("adb"); err != nil {
		fmt.Fprintf(os.Stderr, "[!] adb not found in PATH\n")
		os.Exit(1)
	}

	// Get device
	devSerial := resolveDevice(*device)
	fmt.Printf("[+] Device: %s\n\n", devSerial)

	// Build engines if needed
	if !*skipBuild {
		buildEngines(*verbose)
	}

	// Push engines to device
	engineNames := getEngineNames()
	pushEngines(devSerial, engineNames, *verbose)

	// Run engines in parallel on device
	fmt.Printf("\n[+] Running %d engines on device (parallel=%d)...\n", len(engineNames), *parallel)
	engineResults := runEnginesParallel(devSerial, engineNames, *parallel, *remoteDir, *verbose)

	// Pull results
	fmt.Print("\n[+] Pulling results from device... ")
	pullResults(devSerial, *remoteDir+"/ce_results", *outputDir)
	fmt.Println("OK")

	// Aggregate and generate report
	report := aggregateResults(engineResults, *outputDir, devSerial)
	report.StartTime = startTime.Format(time.RFC3339)
	report.EndTime = time.Now().Format(time.RFC3339)
	report.Duration = time.Since(startTime).String()

	// Generate directory tree
	report.DirectoryTree = buildDirectoryTree(*outputDir)

	// Write JSON report
	reportPath := filepath.Join(*outputDir, "ce_aggregate_report.json")
	reportJSON, _ := json.MarshalIndent(report, "", "  ")
	ioutil.WriteFile(reportPath, reportJSON, 0644)

	// Write human-readable summary
	writeSummary(report, *outputDir)

	// Print summary
	fmt.Printf("\n═══════════════════════════════════════\n")
	fmt.Printf("  Engines OK:   %d/%d\n", report.SuccessfulEngines, report.TotalEngines)
	fmt.Printf("  Total Files:  %d\n", report.TotalFiles)
	fmt.Printf("  Total Size:   %s\n", formatBytes(report.TotalBytes))
	fmt.Printf("  Duration:     %s\n", report.Duration)
	fmt.Printf("  Report:       %s\n", reportPath)
	fmt.Printf("  Output Dir:   %s\n", *outputDir)
	fmt.Printf("═══════════════════════════════════════\n")

	// Cleanup remote
	fmt.Print("\n[+] Cleaning up remote... ")
	exec.Command("adb", appendDevice(devSerial, "shell", "rm", "-rf", *remoteDir+"/ce_results")...).Run()
	fmt.Println("OK")
}

func resolveDevice(serial string) string {
	if serial != "" {
		return serial
	}
	out, _ := exec.Command("adb", "devices").Output()
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	for _, line := range lines {
		parts := strings.Fields(line)
		if len(parts) >= 2 && parts[1] == "device" {
			return parts[0]
		}
	}
	fmt.Fprintf(os.Stderr, "[!] No device found\n")
	os.Exit(1)
	return ""
}

func getEngineNames() []string {
	return []string{
		"engine_01_imei", "engine_02_contacts", "engine_03_sms", "engine_04_calllog",
		"engine_05_wifi", "engine_06_accounts", "engine_07_whatsapp", "engine_08_telegram",
		"engine_09_browser", "engine_10_system", "engine_11_process", "engine_12_network",
		"engine_13_sqlite", "engine_14_media", "engine_15_files", "engine_16_backup",
		"engine_17_hidden", "engine_18_device", "engine_19_keystore", "engine_20_master",
	}
}

func buildEngines(verbose bool) {
	fmt.Println("[*] Building 20 C engines with NDK...")
	cwd, _ := os.Getwd()
	enginesDir := filepath.Join(cwd, "..", "..", "c_engines", "engines")

	cmd := exec.Command("make", "all")
	cmd.Dir = enginesDir
	cmd.Env = append(os.Environ(), "NDK_HOME="+os.Getenv("ANDROID_NDK_HOME"))

	if verbose {
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
	}

	if err := cmd.Run(); err != nil {
		fmt.Printf("  NDK build failed: %v\n", err)
		fmt.Println("  Trying host build instead (will not run on device)...")
		hostCmd := exec.Command("make", "all_host")
		hostCmd.Dir = enginesDir
		if verbose {
			hostCmd.Stdout = os.Stdout
			hostCmd.Stderr = os.Stderr
		}
		if err := hostCmd.Run(); err != nil {
			fmt.Fprintf(os.Stderr, "  Host build also failed: %v\n", err)
			os.Exit(1)
		}
	}
	fmt.Println("  Build complete")
}

func pushEngines(serial string, engines []string, verbose bool) {
	fmt.Print("[*] Pushing engines to device... ")
	cwd, _ := os.Getwd()
	enginesDir := filepath.Join(cwd, "..", "..", "c_engines", "engines", "build")

	for _, e := range engines {
		src := filepath.Join(enginesDir, e)
		dst := "/data/local/tmp/" + e
		out, err := exec.Command("adb", appendDevice(serial, "push", src, dst)...).CombinedOutput()
		if err != nil && verbose {
			fmt.Printf("  push %s: %v\n%s\n", e, err, string(out))
		}
	}
	exec.Command("adb", appendDevice(serial, "shell", "for e in", strings.Join(engines, " "), "; do chmod 755 /data/local/tmp/$e 2>/dev/null || true; done")...).Run()
	fmt.Println("OK")
}

func runEnginesParallel(serial string, engines []string, parallel int, remoteDir string, verbose bool) []EngineResult {
	var mu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, parallel)
	results := make([]EngineResult, 0, len(engines))

	remoteOut := remoteDir + "/ce_results"
	exec.Command("adb", appendDevice(serial, "shell", "mkdir", "-p", remoteOut)...).Run()

	for _, name := range engines {
		wg.Add(1)
		go func(engineName string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			engineStart := time.Now()
			cmd := exec.Command("adb", appendDevice(serial, "shell", "/data/local/tmp/"+engineName, remoteOut)...)
			out, _ := cmd.Output()
			duration := time.Since(engineStart)

			result := EngineResult{
				Name:     engineName,
				Duration: duration.Round(time.Millisecond).String(),
			}

			output := strings.TrimSpace(string(out))

			// Parse JSON from engine output
			// Engine outputs: {"engine":"...","status":"ok","files":N}
			var parsed map[string]interface{}
			if err := json.Unmarshal([]byte(output), &parsed); err == nil {
				result.RawJSON = output
				if status, ok := parsed["status"].(string); ok {
					result.Status = status
				}
				if files, ok := parsed["files"].(float64); ok {
					result.Files = int(files)
				}
				if totalFiles, ok := parsed["total_files"].(float64); ok {
					result.Files = int(totalFiles)
				}
			} else if err != nil {
				// Try to find JSON within output
				if idx := strings.Index(output, "{"); idx >= 0 {
					if idx2 := strings.LastIndex(output, "}"); idx2 > idx {
						jsonStr := output[idx : idx2+1]
						if err2 := json.Unmarshal([]byte(jsonStr), &parsed); err2 == nil {
							result.RawJSON = jsonStr
							if status, ok := parsed["status"].(string); ok {
								result.Status = status
							}
							if files, ok := parsed["files"].(float64); ok {
								result.Files = int(files)
							}
						}
					}
				}
			}

			if result.Status == "" {
				result.Status = "unknown"
			}
			if verbose || result.Status == "fail" {
				result.Output = output
			}

			mu.Lock()
			results = append(results, result)
			status := "✓"
			if result.Status != "ok" {
				status = "✗"
			}
			fmt.Printf("    %s %-20s files=%-5d %s\n", status, engineName, result.Files, result.Duration)
			mu.Unlock()
		}(name)
	}
	wg.Wait()

	// Sort results by engine number
	sort.Slice(results, func(i, j int) bool {
		return results[i].Name < results[j].Name
	})

	return results
}

func pullResults(serial, remotePath, localPath string) {
	os.MkdirAll(localPath, 0755)
	out, _ := exec.Command("adb", appendDevice(serial, "pull", remotePath, localPath)...).CombinedOutput()
	_ = out
}

func aggregateResults(results []EngineResult, outputDir, device string) AggregateReport {
	report := AggregateReport{
		Device:    device,
		Engines:   results,
	}

	totalFiles := int64(0)
	totalBytes := int64(0)
	successCount := 0

	for _, r := range results {
		if r.Status == "ok" {
			successCount++
			totalFiles += int64(r.Files)

			// Count actual file sizes from output directory
			engineDir := filepath.Join(outputDir, "ce_results", r.Name)
			filepath.Walk(engineDir, func(path string, info os.FileInfo, err error) error {
				if err == nil && !info.IsDir() {
					totalBytes += info.Size()
				}
				return nil
			})
		}
	}

	report.TotalEngines = len(results)
	report.SuccessfulEngines = successCount
	report.TotalFiles = totalFiles
	report.TotalBytes = totalBytes

	return report
}

func buildDirectoryTree(basePath string) []DirectoryEntry {
	var entries []DirectoryEntry

	filepath.Walk(basePath, func(path string, info os.FileInfo, err error) error {
		if err != nil || basePath == path {
			return nil
		}
		rel, _ := filepath.Rel(basePath, path)
		entry := DirectoryEntry{
			Path:  rel,
			Size:  info.Size(),
			IsDir: info.IsDir(),
		}
		if info.IsDir() {
			// Count files in dir
			filepath.Walk(path, func(p string, i os.FileInfo, e error) error {
				if e == nil && !i.IsDir() {
					entry.Files++
				}
				return nil
			})
		} else {
			entry.Files = 1
		}
		entries = append(entries, entry)
		return nil
	})

	return entries
}

func writeSummary(report AggregateReport, outputDir string) {
	var sb strings.Builder
	sb.WriteString("╔══════════════════════════════════════════════╗\n")
	sb.WriteString("║  20 C Engines - Total Extraction Report    ║\n")
	sb.WriteString("╚══════════════════════════════════════════════╝\n\n")
	sb.WriteString(fmt.Sprintf("Device:     %s\n", report.Device))
	sb.WriteString(fmt.Sprintf("Start:      %s\n", report.StartTime))
	sb.WriteString(fmt.Sprintf("End:        %s\n", report.EndTime))
	sb.WriteString(fmt.Sprintf("Duration:   %s\n\n", report.Duration))

	sb.WriteString("── Engine Results ──\n")
	for _, e := range report.Engines {
		status := "✓"
		if e.Status != "ok" {
			status = "✗"
		}
		sb.WriteString(fmt.Sprintf("  %s %-20s  files=%-6d  %s\n", status, e.Name, e.Files, e.Duration))
	}

	sb.WriteString(fmt.Sprintf("\n── Summary ──\n"))
	sb.WriteString(fmt.Sprintf("  Engines OK:    %d/%d\n", report.SuccessfulEngines, report.TotalEngines))
	sb.WriteString(fmt.Sprintf("  Total Files:   %d\n", report.TotalFiles))
	sb.WriteString(fmt.Sprintf("  Total Size:    %s\n", formatBytes(report.TotalBytes)))

	sb.WriteString("\n── Directory Structure ──\n")
	for _, d := range report.DirectoryTree {
		if d.IsDir {
			sb.WriteString(fmt.Sprintf("  📁 %-50s %d files\n", d.Path, d.Files))
		}
	}

	summaryPath := filepath.Join(outputDir, "ce_summary.txt")
	ioutil.WriteFile(summaryPath, []byte(sb.String()), 0644)
}

func formatBytes(b int64) string {
	const unit = 1024
	if b < unit {
		return fmt.Sprintf("%d B", b)
	}
	div, exp := int64(unit), 0
	for n := b / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(b)/float64(div), "KMGTPE"[exp])
}

func appendDevice(serial string, args ...string) []string {
	if serial == "" {
		return args
	}
	result := []string{"-s", serial}
	result = append(result, args...)
	return result
}
