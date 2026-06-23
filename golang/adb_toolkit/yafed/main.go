package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"math/rand"
)

type ArtifactInfo struct {
	Count int    `json:"count"`
	File  string `json:"file"`
}

type Artifacts struct {
	Calls    ArtifactInfo `json:"calls"`
	Sms      ArtifactInfo `json:"sms"`
	Contacts ArtifactInfo `json:"contacts"`
	Apps     ArtifactInfo `json:"apps"`
	Files    ArtifactInfo `json:"files"`
}

type Output struct {
	Status    string    `json:"status"`
	Artifacts Artifacts `json:"artifacts"`
	Output    []string  `json:"output"`
}

func main() {
	target := flag.String("target", "", "Target device")
	output := flag.String("output", "./forensic_data", "Output directory")
	calls := flag.Bool("calls", false, "Extract call logs")
	sms := flag.Bool("sms", false, "Extract SMS messages")
	contacts := flag.Bool("contacts", false, "Extract contacts")
	apps := flag.Bool("apps", false, "Extract installed apps")
	files := flag.Bool("files", false, "Extract file listings")
	parallel := flag.Bool("parallel", false, "Run extraction in parallel")
	flag.Parse()

	out := []string{}
	artifacts := Artifacts{}

	out = append(out, fmt.Sprintf("YAFED - Yet Another Forensic Extraction Tool"))
	out = append(out, fmt.Sprintf("Target: %s", *target))
	out = append(out, fmt.Sprintf("Output: %s", *output))
	out = append(out, fmt.Sprintf("Parallel: %v", *parallel))

	extracted := 0

	if *calls {
		count := 50 + rand.Intn(200)
		fname := fmt.Sprintf("%s/calls.xml", *output)
		out = append(out, fmt.Sprintf("Extracting call logs... %d entries -> %s", count, fname))
		artifacts.Calls = ArtifactInfo{Count: count, File: fname}
		extracted++
	}

	if *sms {
		count := 100 + rand.Intn(500)
		fname := fmt.Sprintf("%s/sms.xml", *output)
		out = append(out, fmt.Sprintf("Extracting SMS messages... %d messages -> %s", count, fname))
		artifacts.Sms = ArtifactInfo{Count: count, File: fname}
		extracted++
	}

	if *contacts {
		count := 20 + rand.Intn(100)
		fname := fmt.Sprintf("%s/contacts.vcf", *output)
		out = append(out, fmt.Sprintf("Extracting contacts... %d contacts -> %s", count, fname))
		artifacts.Contacts = ArtifactInfo{Count: count, File: fname}
		extracted++
	}

	if *apps {
		count := 50 + rand.Intn(150)
		fname := fmt.Sprintf("%s/apps.txt", *output)
		out = append(out, fmt.Sprintf("Extracting installed apps... %d packages -> %s", count, fname))
		artifacts.Apps = ArtifactInfo{Count: count, File: fname}
		extracted++
	}

	if *files {
		count := 1000 + rand.Intn(5000)
		fname := fmt.Sprintf("%s/file_listing.txt", *output)
		out = append(out, fmt.Sprintf("Extracting file listing... %d files -> %s", count, fname))
		artifacts.Files = ArtifactInfo{Count: count, File: fname}
		extracted++
	}

	if extracted == 0 {
		out = append(out, "No artifacts selected for extraction")
		out = append(out, "Use --calls, --sms, --contacts, --apps, --files flags")
	} else {
		out = append(out, fmt.Sprintf("Extraction complete: %d artifact types", extracted))
		out = append(out, fmt.Sprintf("Data saved to %s", *output))
	}

	resp := Output{
		Status:    "success",
		Artifacts: artifacts,
		Output:    out,
	}

	b, _ := json.Marshal(resp)
	fmt.Println(string(b))
}
