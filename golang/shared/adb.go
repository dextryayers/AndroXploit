package shared

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"
)

type Result struct {
	Success  bool        `json:"success"`
	Command  string      `json:"command,omitempty"`
	Output   string      `json:"output,omitempty"`
	Error    string      `json:"error,omitempty"`
	Data     interface{} `json:"data,omitempty"`
	Device   string      `json:"device,omitempty"`
	Duration float64     `json:"duration_seconds,omitempty"`
	Attempts int         `json:"attempts,omitempty"`
}

func ExecADB(args ...string) (string, string, error) {
	cmd := exec.Command("adb", args...)
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	return stdout.String(), stderr.String(), err
}

func ExecADBWithDevice(device string, args ...string) (string, string, error) {
	if device != "" {
		fullArgs := append([]string{"-s", device}, args...)
		return ExecADB(fullArgs...)
	}
	return ExecADB(args...)
}

type DeviceInfo struct {
	Serial       string `json:"serial"`
	Status       string `json:"status"`
	Model        string `json:"model,omitempty"`
	Manufacturer string `json:"manufacturer,omitempty"`
	AndroidVer   string `json:"android_version,omitempty"`
	SDKVer       string `json:"sdk_version,omitempty"`
}

func ListDevices() []DeviceInfo {
	stdout, _, err := ExecADB("devices", "-l")
	if err != nil {
		return nil
	}
	lines := strings.Split(strings.TrimSpace(stdout), "\n")
	var devices []DeviceInfo
	for _, line := range lines[1:] {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.Fields(line)
		d := DeviceInfo{Serial: parts[0]}
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
	return devices
}

func GetActiveDevices() []string {
	devices := ListDevices()
	var active []string
	for _, d := range devices {
		if d.Status == "device" {
			active = append(active, d.Serial)
		}
	}
	return active
}

func ExecOnDevice(device string, args []string, retries int) Result {
	start := time.Now()
	var lastOut, lastErr string
	for attempt := 1; attempt <= retries; attempt++ {
		stdout, stderr, err := ExecADBWithDevice(device, args...)
		if err == nil {
			return Result{
				Success:  true,
				Command:  strings.Join(args, " "),
				Output:   stdout,
				Device:   device,
				Duration: time.Since(start).Seconds(),
				Attempts: attempt,
			}
		}
		lastOut = stdout
		lastErr = stderr
		if attempt < retries {
			time.Sleep(time.Duration(attempt) * time.Second)
		}
	}
	return Result{
		Success:  false,
		Command:  strings.Join(args, " "),
		Output:   lastOut,
		Error:    lastErr,
		Device:   device,
		Duration: time.Since(start).Seconds(),
		Attempts: retries,
	}
}

func ExecOnAllDevices(args []string, retries int) []Result {
	devices := GetActiveDevices()
	if len(devices) == 0 {
		r := ExecOnDevice("", args, retries)
		return []Result{r}
	}
	var mu sync.Mutex
	var wg sync.WaitGroup
	results := make([]Result, len(devices))
	for i, d := range devices {
		wg.Add(1)
		go func(idx int, serial string) {
			defer wg.Done()
			r := ExecOnDevice(serial, args, retries)
			mu.Lock()
			results[idx] = r
			mu.Unlock()
		}(i, d)
	}
	wg.Wait()
	return results
}

func EmitJSON(v interface{}) {
	data, _ := json.Marshal(v)
	fmt.Println(string(data))
}

func EmitJSONPretty(v interface{}) {
	data, _ := json.MarshalIndent(v, "", "  ")
	fmt.Println(string(data))
}

type JSONStream struct {
	encoder *json.Encoder
	file    *os.File
}

func NewJSONStream(path string) (*JSONStream, error) {
	f, err := os.Create(path)
	if err != nil {
		return nil, err
	}
	return &JSONStream{encoder: json.NewEncoder(f), file: f}, nil
}

func (s *JSONStream) Emit(v interface{}) error {
	return s.encoder.Encode(v)
}

func (s *JSONStream) Close() error {
	return s.file.Close()
}

var UseJSONStream = false
var Stream *JSONStream

func InitStream(path string) error {
	var err error
	Stream, err = NewJSONStream(path)
	if err != nil {
		return err
	}
	UseJSONStream = true
	return nil
}

func Output(v interface{}) {
	if UseJSONStream && Stream != nil {
		Stream.Emit(v)
	} else {
		EmitJSON(v)
	}
}

type CmdResult struct {
	Stdout string
	Stderr string
	Err    error
}

func ExecADBWithTimeout(args []string, timeout time.Duration) CmdResult {
	ctx, cancel := withTimeout(timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "adb", args...)
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	return CmdResult{Stdout: stdout.String(), Stderr: stderr.String(), Err: err}
}

func withTimeout(d time.Duration) (interface{}, func()) {
	type timerCtx struct {
		timer *time.Timer
		done  chan struct{}
	}
	ctx := &timerCtx{
		timer: time.NewTimer(d),
		done:  make(chan struct{}),
	}
	go func() {
		<-ctx.timer.C
		close(ctx.done)
	}()
	cancel := func() {
		ctx.timer.Stop()
		select {
		case <-ctx.done:
		default:
			close(ctx.done)
		}
	}
	return ctx, cancel
}

func Recover() {
	if r := recover(); r != nil {
		Output(Result{
			Success: false,
			Error:   fmt.Sprintf("panic recovered: %v", r),
		})
	}
}
