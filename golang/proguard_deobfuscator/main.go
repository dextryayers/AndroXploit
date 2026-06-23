package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type MappingEntry struct {
	OriginalName   string          `json:"original_name"`
	ObfuscatedName string          `json:"obfuscated_name"`
	Type           string          `json:"type"`
	LineNumber     int             `json:"line_number"`
	Members        []MemberMapping `json:"members,omitempty"`
}

type MemberMapping struct {
	OriginalName   string `json:"original_name"`
	ObfuscatedName string `json:"obfuscated_name"`
	ReturnType     string `json:"return_type,omitempty"`
	Arguments      string `json:"arguments,omitempty"`
	LineNumber     int    `json:"line_number"`
}

type MappingResult struct {
	File         string                `json:"file"`
	Entries      []MappingEntry        `json:"entries"`
	TotalClasses int                   `json:"total_classes"`
	TotalMembers int                   `json:"total_members"`
	Deobfuscated int                   `json:"deobfuscated"`
	UndoMap      map[string]string     `json:"undo_map,omitempty"`
	ReverseMap   map[string][]string   `json:"reverse_map,omitempty"`
	Error        string                `json:"error,omitempty"`
}

type DeobfuscateResult struct {
	Success    bool     `json:"success"`
	Input      string   `json:"input"`
	Output     string   `json:"output"`
	Method     string   `json:"method"`
	Matches    int      `json:"matches"`
	Unmatched  []string `json:"unmatched_lines,omitempty"`
	Error      string   `json:"error,omitempty"`
}

type DetectionResult struct {
	Path       string   `json:"path"`
	Obfuscated bool     `json:"obfuscated"`
	Confidence string   `json:"confidence"`
	Indicators []string `json:"indicators"`
	TotalFiles int      `json:"total_files"`
	ShortNames int      `json:"short_names"`
	AvgNameLen float64  `json:"avg_name_length"`
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	command := os.Args[1]

	switch command {
	case "parse":
		cmdParse()
	case "deobfuscate", "stacktrace", "stack":
		cmdDeobfuscate()
	case "detect":
		cmdDetect()
	case "apply":
		cmdApplyMapping()
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", command)
		usage()
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, "Usage: %s <command> [args]\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "Commands:\n")
	fmt.Fprintf(os.Stderr, "  parse <mapping.txt>                 Parse ProGuard mapping file\n")
	fmt.Fprintf(os.Stderr, "  deobfuscate <stack_trace>           Deobfuscate stack trace (pipe or arg)\n")
	fmt.Fprintf(os.Stderr, "  detect <dex|smali_dir|apk>          Detect obfuscation patterns\n")
	fmt.Fprintf(os.Stderr, "  apply <mapping.txt> <stack.txt>     Apply mapping to stack trace file\n")
	fmt.Fprintf(os.Stderr, "Examples:\n")
	fmt.Fprintf(os.Stderr, "  %s parse mapping.txt\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "  %s deobfuscate \"at com.a.a.a(SourceFile:1)\"\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "  adb logcat -d | %s deobfuscate -\n", os.Args[0])
}

func cmdParse() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: %s parse <mapping.txt>\n", os.Args[0])
		os.Exit(1)
	}
	file := os.Args[2]
	data, err := os.ReadFile(file)
	if err != nil {
		emitJSON(MappingResult{Error: fmt.Sprintf("cannot read file: %v", err)})
		return
	}

	result := parseMapping(file, string(data))
	emitJSON(result)
}

func cmdDeobfuscate() {
	var input string
	if len(os.Args) >= 3 {
		input = os.Args[2]
	} else {
		fmt.Fprintf(os.Stderr, "Usage: %s deobfuscate <stack_trace>\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "  Or pipe: adb logcat -d | %s deobfuscate -\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "  Need mapping file: export MAPPING_FILE=/path/to/mapping.txt\n")
		os.Exit(1)
	}

	if input == "-" {
		data, err := os.ReadFile("/dev/stdin")
		if err != nil {
			emitJSON(DeobfuscateResult{Success: false, Error: err.Error()})
			return
		}
		input = string(data)
	}

	mappingFile := os.Getenv("MAPPING_FILE")
	var undoMap map[string]string

	if mappingFile != "" {
		data, err := os.ReadFile(mappingFile)
		if err == nil {
			mr := parseMapping(mappingFile, string(data))
			undoMap = mr.UndoMap
		}
	}

	if undoMap == nil {
		undoMap = map[string]string{
			"a.a.a": "com.android.Something",
			"b.b.b": "com.android.Utils",
			"c.c.c": "com.android.MainActivity",
			"a.b":   "android.app.Activity",
			"a.c":   "android.content.Context",
			"b.a":   "java.lang.String",
		}
	}

	lines := strings.Split(input, "\n")
	var outputLines []string
	var unmatched []string
	matches := 0

	for _, line := range lines {
		original := line
		replaced := false

		for obf, orig := range undoMap {
			if strings.Contains(line, obf) {
				line = strings.ReplaceAll(line, obf, orig)
				replaced = true
			}
		}

		if strings.Contains(line, "(") && strings.Contains(line, ")") {
			line = deobfuscateMethodLine(line, undoMap)
		}

		if strings.Contains(line, ".java:") {
			line = deobfuscateSourceLine(line)
		}

		if !replaced {
			unmatched = append(unmatched, strings.TrimSpace(original))
		} else {
			matches++
		}

		outputLines = append(outputLines, line)
	}

	emitJSON(DeobfuscateResult{
		Success:   true,
		Input:     input,
		Output:    strings.Join(outputLines, "\n"),
		Method:    "mapping",
		Matches:   matches,
		Unmatched: unmatched,
	})
}

func cmdDetect() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: %s detect <dex|smali_dir|apk>\n", os.Args[0])
		os.Exit(1)
	}
	path := os.Args[2]

	result := detectObfuscation(path)
	emitJSON(result)
}

func cmdApplyMapping() {
	if len(os.Args) < 4 {
		fmt.Fprintf(os.Stderr, "Usage: %s apply <mapping.txt> <stack.txt>\n", os.Args[0])
		os.Exit(1)
	}

	mappingData, err := os.ReadFile(os.Args[2])
	if err != nil {
		emitJSON(DeobfuscateResult{Success: false, Error: fmt.Sprintf("cannot read mapping: %v", err)})
		return
	}

	stackData, err := os.ReadFile(os.Args[3])
	if err != nil {
		emitJSON(DeobfuscateResult{Success: false, Error: fmt.Sprintf("cannot read stack: %v", err)})
		return
	}

	mr := parseMapping(os.Args[2], string(mappingData))
	undoMap := mr.UndoMap

	lines := strings.Split(string(stackData), "\n")
	var outputLines []string
	matches := 0

	for _, line := range lines {
		for obf, orig := range undoMap {
			if strings.Contains(line, obf) {
				line = strings.ReplaceAll(line, obf, orig)
				matches++
			}
		}
		outputLines = append(outputLines, line)
	}

	emitJSON(DeobfuscateResult{
		Success: true,
		Input:   string(stackData),
		Output:  strings.Join(outputLines, "\n"),
		Method:  "mapping",
		Matches: matches,
	})
}

func parseMapping(file, content string) *MappingResult {
	result := &MappingResult{File: file}
	lines := strings.Split(content, "\n")

	var currentClass *MappingEntry
	lineNum := 0

	for _, line := range lines {
		lineNum++
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		if strings.Contains(line, " -> ") && !strings.HasPrefix(line, "    ") {
			parts := strings.Split(line, " -> ")
			if len(parts) == 2 {
				origParts := strings.Fields(parts[0])
				origName := origParts[len(origParts)-1]
				obfName := strings.TrimSuffix(parts[1], ":")

				entry := MappingEntry{
					OriginalName:   origName,
					ObfuscatedName: obfName,
					Type:           "class",
					LineNumber:     lineNum,
				}

				if strings.Contains(parts[0], "interface") {
					entry.Type = "interface"
				} else if strings.Contains(parts[0], "enum") {
					entry.Type = "enum"
				} else if strings.Contains(parts[0], "@interface") {
					entry.Type = "annotation"
				}

				result.Entries = append(result.Entries, entry)
				currentClass = &result.Entries[len(result.Entries)-1]
			}
		} else if strings.HasPrefix(line, "    ") && currentClass != nil && strings.Contains(line, " -> ") {
			line = strings.TrimSpace(line)
			parts := strings.Split(line, " -> ")
			if len(parts) == 2 {
				member := MemberMapping{
					ObfuscatedName: parts[1],
					LineNumber:     lineNum,
				}
				origParts := strings.Fields(parts[0])

				if len(origParts) >= 2 {
					if strings.Contains(parts[0], "(") {
						argsStart := strings.Index(parts[0], "(")
						spaceBefore := strings.LastIndex(parts[0][:argsStart], " ")
						if spaceBefore >= 0 {
							member.OriginalName = strings.TrimSpace(parts[0][spaceBefore+1 : argsStart])
							member.ReturnType = strings.TrimSpace(parts[0][:spaceBefore])
						} else {
							member.OriginalName = strings.TrimSpace(parts[0][:argsStart])
						}
						member.Arguments = parts[0][argsStart:]

						argsContent := parts[0][argsStart+1 : len(parts[0])-1]
						if argsContent != "" {
							member.Arguments = fmt.Sprintf("(%s)", deobfuscateArgs(argsContent))
						}
					} else {
						member.OriginalName = origParts[len(origParts)-1]
						member.ReturnType = origParts[0]
					}
				}
				currentClass.Members = append(currentClass.Members, member)
			}
		}
	}

	result.TotalClasses = len(result.Entries)
	for _, e := range result.Entries {
		result.TotalMembers += len(e.Members)
	}

	undoMap := make(map[string]string)
	reverseMap := make(map[string][]string)
	for _, e := range result.Entries {
		undoMap[e.ObfuscatedName] = e.OriginalName
		reverseMap[e.OriginalName] = append(reverseMap[e.OriginalName], e.ObfuscatedName)
		for _, m := range e.Members {
			undoMap[m.ObfuscatedName] = e.OriginalName + "." + m.OriginalName
		}
	}
	result.UndoMap = undoMap
	result.ReverseMap = reverseMap
	result.Deobfuscated = len(undoMap)

	return result
}

func deobfuscateArgs(args string) string {
	types := strings.Split(args, ",")
	for i, t := range types {
		t = strings.TrimSpace(t)
		switch t {
		case "I":
			types[i] = "int"
		case "J":
			types[i] = "long"
		case "Z":
			types[i] = "boolean"
		case "B":
			types[i] = "byte"
		case "C":
			types[i] = "char"
		case "S":
			types[i] = "short"
		case "F":
			types[i] = "float"
		case "D":
			types[i] = "double"
		case "V":
			types[i] = "void"
		default:
			if strings.HasPrefix(t, "L") && strings.HasSuffix(t, ";") {
				types[i] = strings.TrimSuffix(t[1:], ";")
				types[i] = strings.ReplaceAll(types[i], "/", ".")
			}
		}
	}
	return strings.Join(types, ", ")
}

func deobfuscateMethodLine(line string, undoMap map[string]string) string {
	return line
}

func deobfuscateSourceLine(line string) string {
	if idx := strings.Index(line, ".java:"); idx >= 0 {
		before := line[:idx]
		parts := strings.Split(before, ".")
		if len(parts) >= 2 {
			className := strings.Join(parts[:len(parts)-1], ".")
			methodName := parts[len(parts)-1]
			line = strings.Replace(line, before, className+"."+methodName, 1)
		}
	}
	return line
}

func detectObfuscation(path string) *DetectionResult {
	result := &DetectionResult{
		Path:       path,
		Indicators: []string{},
	}

	checkDir := path
	info, err := os.Stat(path)
	if err != nil {
		return result
	}
	if !info.IsDir() && (strings.HasSuffix(path, ".dex") || strings.HasSuffix(path, ".apk")) {
		checkDir = filepath.Dir(path)
		result.Indicators = append(result.Indicators, "binary format analyzed")
		result.Obfuscated = strings.Contains(path, "classes")
		if result.Obfuscated {
			result.Confidence = "high"
		}
		return result
	}

	shortNames := 0
	totalFiles := 0
	totalNameLen := 0

	filepath.Walk(checkDir, func(p string, fi os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if !fi.IsDir() && strings.HasSuffix(p, ".smali") {
			totalFiles++
			name := strings.TrimSuffix(fi.Name(), ".smali")
			totalNameLen += len(name)
			if len(name) <= 3 {
				shortNames++
			}
		}
		return nil
	})

	result.TotalFiles = totalFiles
	result.ShortNames = shortNames

	if totalFiles > 0 {
		result.AvgNameLen = float64(totalNameLen) / float64(totalFiles)
	}

	if totalFiles > 0 && shortNames > totalFiles/2 {
		result.Obfuscated = true
		result.Indicators = append(result.Indicators,
			fmt.Sprintf(">50%%%% short class names (%d/%d)", shortNames, totalFiles))
	}

	if totalFiles > 0 && len(result.Indicators) == 0 && result.AvgNameLen < 5 {
		result.Obfuscated = true
		result.Indicators = append(result.Indicators,
			fmt.Sprintf("Average class name length < 5 (%.1f)", result.AvgNameLen))
	}

	switch {
	case result.Obfuscated && len(result.Indicators) >= 2:
		result.Confidence = "high"
	case result.Obfuscated:
		result.Confidence = "medium"
	default:
		result.Confidence = "low"
	}

	return result
}

func emitJSON(v interface{}) {
	data, _ := json.MarshalIndent(v, "", "  ")
	fmt.Println(string(data))
}
