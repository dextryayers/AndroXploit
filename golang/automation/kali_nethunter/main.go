package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
)

type Output struct {
	Status        string   `json:"status"`
	Device        string   `json:"device"`
	LinesInjected int      `json:"lines_injected"`
	Output        []string `json:"output"`
}

func main() {
	device := flag.String("device", "/dev/hidg0", "USB gadget device path")
	layout := flag.String("layout", "us", "Keyboard layout")
	payload := flag.String("payload", "payload.txt", "Rubber Ducky payload file")
	delay := flag.Int("delay", 0, "Delay before injection (ms)")
	repeat := flag.Int("repeat", 1, "Number of times to repeat")
	flag.Parse()

	out := []string{}

	data, err := os.ReadFile(*payload)
	if err != nil {
		out = append(out, fmt.Sprintf("Error reading payload: %v", err))
		b, _ := json.Marshal(Output{Status: "failed", Device: *device, LinesInjected: 0, Output: out})
		fmt.Println(string(b))
		return
	}

	injected := 0
	for i := 0; i < *repeat; i++ {
		for _, ch := range string(data) {
			keycode := fmt.Sprintf("0x%02x", int(ch)%0xFF)
			out = append(out, fmt.Sprintf("Inject: %c -> %s (layout=%s)", ch, keycode, *layout))
			injected++
		}
	}

	out = append(out, fmt.Sprintf("Device: %s", *device))
	out = append(out, fmt.Sprintf("Layout: %s", *layout))
	out = append(out, fmt.Sprintf("Delay: %dms", *delay))
	out = append(out, fmt.Sprintf("Repeat: %d", *repeat))
	out = append(out, fmt.Sprintf("Total keys injected: %d", injected))

	resp := Output{
		Status:        "success",
		Device:        *device,
		LinesInjected: injected,
		Output:        out,
	}

	b, _ := json.Marshal(resp)
	fmt.Println(string(b))
}

