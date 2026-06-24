package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type EngineResult struct {
	Name    string `json:"name"`
	Status  string `json:"status"`
	Output  string `json:"output"`
	Error   string `json:"error,omitempty"`
	Elapsed string `json:"elapsed"`
}

func adb(serial string, args ...string) (string, error) {
	cmdArgs := []string{}
	if serial != "" {
		cmdArgs = append(cmdArgs, "-s", serial)
	}
	cmdArgs = append(cmdArgs, args...)
	out, err := exec.Command("adb", cmdArgs...).CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

func buildWithNDK(srcDir, buildDir string) (string, error) {
	ndk := os.Getenv("ANDROID_NDK_HOME")
	if ndk == "" {
		return "", fmt.Errorf("ANDROID_NDK_HOME not set")
	}
	tc := filepath.Join(ndk, "toolchains", "llvm", "prebuilt", "linux-x86_64")
	cc := filepath.Join(tc, "bin", "aarch64-linux-android21-clang")
	bin := filepath.Join(buildDir, "extract_droid")
	src := filepath.Join(srcDir, "extract_droid.c")

	if _, err := os.Stat(cc); err != nil {
		return "", fmt.Errorf("compiler not found: %s", cc)
	}

	os.MkdirAll(buildDir, 0755)
	cmd := exec.Command(cc, "-Os", "-fPIE", "-static", "-Wall", "-o", bin, src, "-lz")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("build failed: %v\n%s", err, string(out))
	}
	return bin, nil
}

func checkDevice(serial string) (string, error) {
	out, err := adb(serial, "devices")
	if err != nil {
		return "", err
	}
	lines := strings.Split(out, "\n")
	var devices []string
	for _, line := range lines {
		parts := strings.Fields(line)
		if len(parts) >= 2 && parts[1] == "device" {
			devices = append(devices, parts[0])
		}
	}
	if serial != "" {
		for _, d := range devices {
			if d == serial {
				return serial, nil
			}
		}
		return "", fmt.Errorf("device %s not found", serial)
	}
	if len(devices) == 0 {
		return "", fmt.Errorf("no device connected")
	}
	if len(devices) > 1 {
		return "", fmt.Errorf("multiple devices: %s — use -device flag", strings.Join(devices, ", "))
	}
	return devices[0], nil
}

func main() {
	serial := flag.String("device", "", "ADB device serial")
	srcDir := flag.String("src", "../../c_engines", "C source directory")
	buildDir := flag.String("build", "../../c_engines/build", "Build directory")
	outDir := flag.String("output", "./cengine_results", "Local output directory")
	remoteDir := flag.String("remote", "/data/local/tmp", "Remote output on device")
	verbose := flag.Bool("verbose", false, "Verbose output")
	mode := flag.String("mode", "auto", "Build mode: ndk, device, auto")
	flag.Parse()

	fmt.Println("╔══════════════════════════════════════╗")
	fmt.Println("║  extract_droid Runner v1.0           ║")
	fmt.Println("╚══════════════════════════════════════╝")

	dev, err := checkDevice(*serial)
	if err != nil {
		fmt.Fprintf(os.Stderr, "[!] %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("[+] Device: %s\n\n", dev)

	results := []EngineResult{}
	start := time.Now()

	// Build
	fmt.Println("[*] Building extract_droid...")
	binPath := ""
	switch *mode {
	case "ndk":
		binPath, err = buildWithNDK(*srcDir, *buildDir)
	case "device":
		err = fmt.Errorf("on-device build not supported in Go runner; use bash runner")
	case "auto":
		binPath, err = buildWithNDK(*srcDir, *buildDir)
		if err != nil {
			fmt.Printf("  NDK build failed: %v\n", err)
			fmt.Println("  Falling back to: cd c_engines && bash run_c_engine.sh")
			err = fmt.Errorf("NDK not available; use bash runner or build manually")
		}
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "[!] %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("  Built: %s\n", binPath)

	// Push
	fmt.Print("[*] Pushing to device... ")
	if out, err := adb(dev, "push", binPath, *remoteDir+"/extract_droid"); err != nil {
		fmt.Fprintf(os.Stderr, "FAIL: %v\n%s\n", err, out)
		os.Exit(1)
	}
	adb(dev, "shell", "chmod 755", *remoteDir+"/extract_droid")
	fmt.Println("OK")

	// Prepare remote output dir
	remoteOut := *remoteDir + "/extract_results"
	adb(dev, "shell", "mkdir", "-p", remoteOut)

	// Run all modules
	fmt.Println("[*] Running extract_droid --all...")
	runStart := time.Now()
	out, err := adb(dev, "shell", *remoteDir+"/extract_droid", remoteOut, "--all")
	elapsed := time.Since(runStart)
	if err != nil {
		fmt.Printf("  Warning: %v\n", err)
	}
	if *verbose {
		fmt.Printf("  Output:\n%s\n", out)
	}
	fmt.Printf("  Done in %v\n", elapsed)

	results = append(results, EngineResult{
		Name:    "extract_droid",
		Status:  "success",
		Output:  strings.TrimSpace(out),
		Elapsed: elapsed.String(),
	})

	// Pull results
	fmt.Print("[*] Pulling results... ")
	os.MkdirAll(*outDir, 0755)
	if pullOut, err := adb(dev, "pull", remoteOut, *outDir); err != nil {
		fmt.Printf("WARN: %v\n%s\n", err, pullOut)
	} else {
		fmt.Println("OK")
	}

	// Pull JSON result
	adb(dev, "pull", *remoteDir+"/extract_droid_result.json", *outDir)

	// Cleanup
	adb(dev, "shell", "rm", "-rf", remoteOut, *remoteDir+"/extract_droid")

	// Summary
	total := time.Since(start)
	fmt.Printf("\n═══════════════════════════════════════\n")
	fmt.Printf("  Total time: %v\n", total)
	fmt.Printf("  Results: %s\n", *outDir)

	jsonPath := filepath.Join(*outDir, "runner_results.json")
	jsonData, _ := json.MarshalIndent(results, "", "  ")
	os.WriteFile(jsonPath, jsonData, 0644)
	fmt.Printf("  JSON: %s\n", jsonPath)
}
