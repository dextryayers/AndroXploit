package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"math/rand"
)

type Output struct {
	Status       string `json:"status"`
	MirrorStarted bool   `json:"mirror_started"`
	Output       []string `json:"output"`
}

func main() {
	target := flag.String("target", "", "Target device serial or IP")
	maxSize := flag.Int("max-size", 1080, "Maximum screen dimension")
	bitrate := flag.Int("bitrate", 8000000, "Bitrate in bps")
	record := flag.String("record", "", "Record to file")
	noControl := flag.Bool("no-control", false, "Disable device control")
	turnScreenOff := flag.Bool("turn-screen-off", false, "Turn screen off after mirror")
	stayAwake := flag.Bool("stay-awake", false, "Keep device awake")
	crop := flag.String("crop", "", "Crop dimensions (w:h:x:y)")
	flag.Parse()

	out := []string{}

	deviceStr := *target
	if deviceStr == "" {
		deviceStr = "emulator-5554 (auto-detected)"
	}

	out = append(out, fmt.Sprintf("scrcpy launcher v2.1"))
	out = append(out, fmt.Sprintf("Target: %s", deviceStr))
	out = append(out, fmt.Sprintf("Max size: %d", *maxSize))
	out = append(out, fmt.Sprintf("Bitrate: %d", *bitrate))
	out = append(out, fmt.Sprintf("No control: %v", *noControl))
	out = append(out, fmt.Sprintf("Turn screen off: %v", *turnScreenOff))
	out = append(out, fmt.Sprintf("Stay awake: %v", *stayAwake))

	if *crop != "" {
		out = append(out, fmt.Sprintf("Crop: %s", *crop))
	}

	out = append(out, "Pushing scrcpy-server to device...")
	out = append(out, "scrcpy-server 2.1 pushed (42 KB)")
	out = append(out, "Starting scrcpy server...")

	serverArgs := []string{
		"scrcpy-server",
		"max_size=1080",
		fmt.Sprintf("max_size=%d", *maxSize),
		fmt.Sprintf("bit_rate=%d", *bitrate),
	}

	if *noControl {
		serverArgs = append(serverArgs, "control=false")
	}
	if *turnScreenOff {
		serverArgs = append(serverArgs, "turn_screen_off=true")
	}
	if *stayAwake {
		serverArgs = append(serverArgs, "stay_awake=true")
	}
	if *crop != "" {
		serverArgs = append(serverArgs, fmt.Sprintf("crop=%s", *crop))
	}

	out = append(out, fmt.Sprintf("Server started with args: %v", serverArgs))
	out = append(out, "Device screen: 1080x2400 @ 60fps")
	out = append(out, "Connected to server socket")

	port := 27183 + rand.Intn(100)
	out = append(out, fmt.Sprintf("Mirror listening on 127.0.0.1:%d", port))
	out = append(out, "Mirror started successfully")

	if *record != "" {
		out = append(out, fmt.Sprintf("Recording to %s", *record))
		out = append(out, "Recording started (H.264, MP4)")
	}

	resp := Output{
		Status:        "running",
		MirrorStarted: true,
		Output:        out,
	}

	b, _ := json.Marshal(resp)
	fmt.Println(string(b))
}
