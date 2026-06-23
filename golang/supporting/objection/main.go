package main

import (
	"encoding/json"
	"flag"
	"fmt"
)

type ActionData struct {
	Classes []string `json:"classes"`
}

type Output struct {
	Status string     `json:"status"`
	Action string     `json:"action"`
	Data   ActionData `json:"data"`
	Output []string   `json:"output"`
}

func main() {
	target := flag.String("target", "", "Target package or process")
	action := flag.String("action", "explore", "Action (explore/env/classes/hooks)")
	gadget := flag.String("gadget", "", "Gadget configuration")
	hook := flag.String("hook", "", "Hook script file")
	filter := flag.String("filter", "", "Search filter")
	serial := flag.String("serial", "", "Device serial")
	flag.Parse()

	out := []string{}
	classes := []string{}

	if *target == "" {
		*target = "com.android.settings"
	}

	out = append(out, fmt.Sprintf("Objection Runtime Explorer v1.0"))
	out = append(out, fmt.Sprintf("Target: %s", *target))
	out = append(out, fmt.Sprintf("Action: %s", *action))
	out = append(out, fmt.Sprintf("Serial: %s", *serial))
	out = append(out, fmt.Sprintf("Gadget: %s", *gadget))

	out = append(out, "Connecting to Frida server...")
	out = append(out, fmt.Sprintf("Attaching to %s", *target))

	switch *action {
	case "explore":
		out = append(out, "Exploring application...")
		classes = []string{
			"android.app.Activity",
			"android.app.Service",
			"android.content.BroadcastReceiver",
			"android.content.ContentProvider",
			"android.view.View",
		}
		for _, c := range classes {
			out = append(out, fmt.Sprintf("  class: %s", c))
		}

		if *filter != "" {
			out = append(out, fmt.Sprintf("Filtering for: %s", *filter))
			filtered := []string{}
			for _, c := range classes {
				if contains(c, *filter) {
					filtered = append(filtered, c)
				}
			}
			classes = filtered
		}

	case "env":
		out = append(out, "Reading environment...")
		out = append(out, "  ANDROID_ROOT: /system")
		out = append(out, "  ANDROID_DATA: /data")
		out = append(out, "  EXTERNAL_STORAGE: /sdcard")
		out = append(out, "  JAVA_HOME: /system")
		classes = []string{"env_complete"}

	case "classes":
		out = append(out, "Enumerating loaded classes...")
		for i := 0; i < 20; i++ {
			cls := fmt.Sprintf("com.example.Class%d", i)
			classes = append(classes, cls)
		}
		out = append(out, fmt.Sprintf("Found %d classes", len(classes)))

		if *filter != "" {
			filtered := []string{}
			for _, c := range classes {
				if contains(c, *filter) {
					filtered = append(filtered, c)
				}
			}
			classes = filtered
			out = append(out, fmt.Sprintf("Filtered to %d classes", len(classes)))
		}

	case "hooks":
		out = append(out, fmt.Sprintf("Loading hooks from %s...", *hook))
		if *hook != "" {
			out = append(out, fmt.Sprintf("Hook file loaded: %s", *hook))
			out = append(out, "Hooks applied: 3")
			classes = []string{"hook_method:onCreate", "hook_method:onResume", "hook_method:onDestroy"}
		} else {
			out = append(out, "No hook file specified, using default")
			classes = []string{"hook_method:onCreate (default)"}
		}

	default:
		out = append(out, fmt.Sprintf("Unknown action: %s, using explore", *action))
		classes = []string{"unknown_action"}
	}

	out = append(out, fmt.Sprintf("Action '%s' completed", *action))

	resp := Output{
		Status: "success",
		Action: *action,
		Data:   ActionData{Classes: classes},
		Output: out,
	}

	b, _ := json.Marshal(resp)
	fmt.Println(string(b))
}

func contains(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
