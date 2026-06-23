package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"math/rand"
)

type Output struct {
	Status string                 `json:"status"`
	Action string                 `json:"action"`
	Data   map[string]interface{} `json:"data"`
	Output []string               `json:"output"`
}

func main() {
	target := flag.String("target", "", "Target device IP:port or serial")
	action := flag.String("action", "shell", "Action to perform")
	file := flag.String("file", "", "File to push/pull")
	dest := flag.String("dest", "", "Destination path")
	lat := flag.Float64("lat", 0, "Spoof latitude")
	lon := flag.Float64("lon", 0, "Spoof longitude")
	flag.Parse()

	out := []string{}
	data := make(map[string]interface{})

	if *target == "" {
		*target = "device (USB)"
	}

	out = append(out, fmt.Sprintf("ADBSploit v2.0"))
	out = append(out, fmt.Sprintf("Target: %s", *target))
	out = append(out, fmt.Sprintf("Action: %s", *action))

	switch *action {
	case "shell":
		out = append(out, "Opening shell on device...")
		out = append(out, "Connected")
		out = append(out, "u0_a123@android:/ $")
		data["shell"] = "opened"
		data["target"] = *target

	case "push":
		out = append(out, fmt.Sprintf("Pushing %s to %s...", *file, *dest))
		if *dest == "" {
			*dest = "/data/local/tmp/"
		}
		out = append(out, fmt.Sprintf("Pushed %d bytes", 1024+rand.Intn(65536)))
		data["source"] = *file
		data["destination"] = *dest

	case "pull":
		out = append(out, fmt.Sprintf("Pulling %s...", *file))
		out = append(out, fmt.Sprintf("Pulled %d bytes", 1024+rand.Intn(65536)))
		data["source"] = *file
		data["destination"] = *dest

	case "screenshot":
		out = append(out, "Taking screenshot...")
		out = append(out, "Screenshot saved to screen_20240101_120000.png")
		data["file"] = "screen_20240101_120000.png"
		data["resolution"] = "1080x2400"

	case "spoof_gps":
		out = append(out, fmt.Sprintf("Spoofing GPS to lat=%f, lon=%f...", *lat, *lon))
		out = append(out, "GPS location updated")
		data["latitude"] = *lat
		data["longitude"] = *lon

	case "info":
		out = append(out, "Gathering device info...")
		data["model"] = "Pixel 8 Pro"
		data["android_ver"] = "14"
		data["api_level"] = 34
		data["serial"] = "ABCDEF123456"
		out = append(out, "Model: Pixel 8 Pro")
		out = append(out, "Android: 14 (API 34)")
		out = append(out, "Serial: ABCDEF123456")

	case "list_packages":
		out = append(out, "Listing packages...")
		pkgs := []string{"com.android.chrome", "com.whatsapp", "com.instagram.android"}
		data["packages"] = pkgs
		for _, p := range pkgs {
			out = append(out, fmt.Sprintf("package:%s", p))
		}

	default:
		out = append(out, fmt.Sprintf("Unknown action: %s", *action))
		out = append(out, "Using shell fallback")
		data["action"] = *action
		data["fallback"] = true
	}

	out = append(out, fmt.Sprintf("Action '%s' completed", *action))

	resp := Output{
		Status: "success",
		Action: *action,
		Data:   data,
		Output: out,
	}

	b, _ := json.Marshal(resp)
	fmt.Println(string(b))
}
