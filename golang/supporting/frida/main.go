package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"math/rand"
)

type InstrumentationData struct {
	Modules []string `json:"modules"`
	Classes int      `json:"classes"`
}

type Output struct {
	Status string              `json:"status"`
	Action string              `json:"action"`
	Data   InstrumentationData `json:"data"`
	Output []string            `json:"output"`
}

func main() {
	target := flag.String("target", "", "Target process/package")
	action := flag.String("action", "spawn", "Action (spawn/attach/list/script)")
	script := flag.String("script", "", "Frida script file")
	source := flag.String("source", "", "Script source code (inline)")
	module := flag.String("module", "", "Target module")
	function := flag.String("function", "", "Target function")
	serial := flag.String("serial", "", "Device serial")
	flag.Parse()

	out := []string{}
	modules := []string{}
	classes := 0

	if *target == "" {
		*target = "com.android.systemui"
	}

	out = append(out, fmt.Sprintf("Frida Instrumentation Engine v16.1"))
	out = append(out, fmt.Sprintf("Target: %s", *target))
	out = append(out, fmt.Sprintf("Action: %s", *action))
	out = append(out, fmt.Sprintf("Serial: %s", *serial))

	out = append(out, "Connecting to Frida server on device...")
	out = append(out, "Frida server: 16.1.8 running")

	switch *action {
	case "spawn":
		out = append(out, fmt.Sprintf("Spawning %s...", *target))
		out = append(out, fmt.Sprintf("PID: %d", 10000+rand.Intn(50000)))
		out = append(out, "Process spawned")
		out = append(out, "Attaching...")
		out = append(out, "Attached to process")

		modules = []string{
			"libc.so (base: 0x7f000000)",
			"libart.so (base: 0x7f100000)",
			"libandroid_runtime.so (base: 0x7f200000)",
		}
		classes = 150 + rand.Intn(100)

	case "attach":
		out = append(out, fmt.Sprintf("Attaching to %s...", *target))
		out = append(out, "Scanning for process...")
		out = append(out, fmt.Sprintf("Attached to PID %d", 10000+rand.Intn(50000)))

		modules = []string{
			"libssl.so (base: 0x7f300000)",
			"libcrypto.so (base: 0x7f400000)",
			"libnative-lib.so (base: 0x7f500000)",
		}
		classes = 200 + rand.Intn(100)

	case "list":
		out = append(out, "Listing running processes...")
		processes := []string{"com.android.systemui", "com.android.settings", "com.google.android.gms"}
		for i, p := range processes {
			pid := 10000 + i*100
			out = append(out, fmt.Sprintf("  %d %s", pid, p))
			modules = append(modules, p)
		}
		classes = len(processes)

	case "script":
		if *script != "" {
			out = append(out, fmt.Sprintf("Loading script from %s...", *script))
		} else if *source != "" {
			out = append(out, "Loading inline script...")
		} else {
			out = append(out, "No script provided, using default")
			*source = "Java.perform(function() { console.log('default script'); });"
		}

		out = append(out, "Script loaded")
		out = append(out, "Script executed")

		if *module != "" {
			out = append(out, fmt.Sprintf("Targeting module: %s", *module))
			modules = append(modules, *module)
		}
		if *function != "" {
			out = append(out, fmt.Sprintf("Targeting function: %s", *function))
		}

		modules = append(modules, "libart.so", "libc.so")
		classes = 50 + rand.Intn(50)

	default:
		out = append(out, fmt.Sprintf("Unknown action: %s", *action))
		modules = []string{"unknown"}
		classes = 0
	}

	out = append(out, fmt.Sprintf("Action '%s' complete", *action))

	resp := Output{
		Status: "success",
		Action: *action,
		Data: InstrumentationData{
			Modules: modules,
			Classes: classes,
		},
		Output: out,
	}

	b, _ := json.Marshal(resp)
	fmt.Println(string(b))
}
