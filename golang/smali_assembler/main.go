package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type SmaliResult struct {
	Success      bool   `json:"success"`
	Input        string `json:"input"`
	Output       string `json:"output"`
	Command      string `json:"command"`
	Error        string `json:"error,omitempty"`
	Files        int    `json:"files_processed"`
	Instructions int    `json:"total_instructions,omitempty"`
	Classes      int    `json:"total_classes,omitempty"`
	Methods      int    `json:"total_methods,omitempty"`
	StringsFound int    `json:"strings_found,omitempty"`
}

type FindMatch struct {
	File    string `json:"file"`
	Line    int    `json:"line"`
	Content string `json:"content"`
	Class   string `json:"class,omitempty"`
	Method  string `json:"method,omitempty"`
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	command := os.Args[1]

	switch command {
	case "assemble":
		cmdAssemble()
	case "disassemble":
		cmdDisassemble()
	case "count", "stats", "analyze":
		cmdCount()
	case "find":
		cmdFind()
	case "instructions":
		cmdInstructions()
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", command)
		usage()
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, "Usage: %s <command> [args]\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "Commands:\n")
	fmt.Fprintf(os.Stderr, "  assemble <dir> [output.dex]         Assemble smali to DEX\n")
	fmt.Fprintf(os.Stderr, "  disassemble <dex> [output_dir]      Disassemble DEX to smali\n")
	fmt.Fprintf(os.Stderr, "  count|stats|analyze <dir|dex>       Analyze smali/dex structure\n")
	fmt.Fprintf(os.Stderr, "  find <dir> <pattern>                Find string/pattern in smali\n")
	fmt.Fprintf(os.Stderr, "  instructions <dir>                  Count instructions by type/opcode\n")
	fmt.Fprintf(os.Stderr, "Examples:\n")
	fmt.Fprintf(os.Stderr, "  %s assemble smali_dir/ classes.dex\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "  %s find smali_dir/ \"http\"\n", os.Args[0])
}

func cmdAssemble() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: %s assemble <dir> [output.dex]\n", os.Args[0])
		os.Exit(1)
	}
	inputDir := os.Args[2]
	output := "output.dex"
	if len(os.Args) > 3 {
		output = os.Args[3]
	}

	smaliPath := findSmali()
	if smaliPath == "" {
		emitJSON(SmaliResult{
			Success: false, Input: inputDir, Output: output,
			Error: "smali.jar not found. Install from https://github.com/JesusFreke/smali",
		})
		return
	}

	smaliFiles := 0
	filepath.Walk(inputDir, func(p string, fi os.FileInfo, err error) error {
		if err == nil && !fi.IsDir() && strings.HasSuffix(p, ".smali") {
			smaliFiles++
		}
		return nil
	})

	if smaliFiles == 0 {
		emitJSON(SmaliResult{
			Success: false, Input: inputDir, Output: output,
			Error: fmt.Sprintf("no .smali files found in %s", inputDir),
		})
		return
	}

	cmd := exec.Command("java", "-jar", smaliPath, "assemble", inputDir, "-o", output)
	out, err := cmd.CombinedOutput()

	result := SmaliResult{
		Input:   inputDir,
		Output:  output,
		Command: "assemble",
		Files:   smaliFiles,
	}
	if err != nil {
		result.Success = false
		result.Error = string(out)
	} else {
		result.Success = true
	}
	emitJSON(result)
}

func cmdDisassemble() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: %s disassemble <dex> [output_dir]\n", os.Args[0])
		os.Exit(1)
	}
	input := os.Args[2]
	outputDir := strings.TrimSuffix(input, ".dex") + "_smali"
	if len(os.Args) > 3 {
		outputDir = os.Args[3]
	}

	if _, err := os.Stat(input); os.IsNotExist(err) {
		emitJSON(SmaliResult{
			Success: false, Input: input, Output: outputDir,
			Error: fmt.Sprintf("file not found: %s", input),
		})
		return
	}

	baksmaliPath := findBaksmali()
	if baksmaliPath == "" {
		emitJSON(SmaliResult{
			Success: false, Input: input, Output: outputDir,
			Error: "baksmali.jar not found. Install from https://github.com/JesusFreke/smali",
		})
		return
	}

	cmd := exec.Command("java", "-jar", baksmaliPath, "disassemble", input, "-o", outputDir)
	out, err := cmd.CombinedOutput()

	result := SmaliResult{
		Input:   input,
		Output:  outputDir,
		Command: "disassemble",
	}

	if err != nil {
		result.Success = false
		result.Error = string(out)
	} else {
		result.Success = true
		filepath.Walk(outputDir, func(p string, fi os.FileInfo, err error) error {
			if err == nil && !fi.IsDir() && strings.HasSuffix(p, ".smali") {
				result.Files++
			}
			return nil
		})
	}
	emitJSON(result)
}

func cmdCount() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: %s count <dir|dex>\n", os.Args[0])
		os.Exit(1)
	}
	input := os.Args[2]

	result := analyzeSmaliDir(input)
	emitJSON(result)
}

func cmdFind() {
	if len(os.Args) < 4 {
		fmt.Fprintf(os.Stderr, "Usage: %s find <dir> <pattern>\n", os.Args[0])
		os.Exit(1)
	}
	inputDir := os.Args[2]
	pattern := os.Args[3]

	var matches []FindMatch
	stringCount := 0

	filepath.Walk(inputDir, func(p string, fi os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if !fi.IsDir() && strings.HasSuffix(p, ".smali") {
			data, err := os.ReadFile(p)
			if err != nil {
				return nil
			}
			lines := strings.Split(string(data), "\n")

			var currentClass, currentMethod string
			for i, line := range lines {
				trimmed := strings.TrimSpace(line)

				if strings.HasPrefix(trimmed, ".class ") {
					for _, part := range strings.Fields(trimmed) {
						if strings.HasPrefix(part, "L") && strings.Contains(part, "/") {
							currentClass = strings.ReplaceAll(part, "/", ".")
							currentClass = strings.TrimPrefix(currentClass, "L")
							currentClass = strings.TrimSuffix(currentClass, ";")
						}
					}
				}

				if strings.HasPrefix(trimmed, ".method ") {
					parts := strings.Split(trimmed, " ")
					if len(parts) >= 2 {
						currentMethod = parts[len(parts)-1]
					}
				}

				if strings.HasPrefix(trimmed, ".end method") {
					currentMethod = ""
				}

				if strings.Contains(strings.ToLower(trimmed), strings.ToLower(pattern)) {
					relPath, _ := filepath.Rel(inputDir, p)
					matches = append(matches, FindMatch{
						File:    relPath,
						Line:    i + 1,
						Content: strings.TrimSpace(trimmed),
						Class:   currentClass,
						Method:  currentMethod,
					})
					stringCount++
				}
			}
		}
		return nil
	})

	emitJSON(map[string]interface{}{
		"success":       true,
		"pattern":       pattern,
		"matches":       matches,
		"count":         len(matches),
		"strings_found": stringCount,
	})
}

func cmdInstructions() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: %s instructions <dir>\n", os.Args[0])
		os.Exit(1)
	}
	input := os.Args[2]

	type opCounter struct {
		Opcode string `json:"opcode"`
		Count  int    `json:"count"`
	}

	opcodes := make(map[string]int)
	total := 0
	smaliFiles := 0

	filepath.Walk(input, func(p string, fi os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if !fi.IsDir() && strings.HasSuffix(p, ".smali") {
			smaliFiles++
			data, err := os.ReadFile(p)
			if err != nil {
				return nil
			}
			lines := strings.Split(string(data), "\n")
			for _, line := range lines {
				line = strings.TrimSpace(line)
				if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, ".") || strings.HasPrefix(line, ":") {
					continue
				}
				parts := strings.Fields(line)
				if len(parts) > 0 {
					op := parts[0]
					opcodes[op]++
					total++
				}
			}
		}
		return nil
	})

	var sorted []opCounter
	for op, count := range opcodes {
		sorted = append(sorted, opCounter{Opcode: op, Count: count})
	}

	emitJSON(map[string]interface{}{
		"success":           true,
		"input":             input,
		"files":             smaliFiles,
		"total_instructions": total,
		"unique_opcodes":    len(sorted),
		"opcodes":           sorted,
	})
}

func analyzeSmaliDir(input string) SmaliResult {
	result := SmaliResult{
		Input:   input,
		Command: "analyze",
	}

	totalLines := 0
	fileCount := 0
	totalInstructions := 0
	totalClasses := 0
	totalMethods := 0

	filepath.Walk(input, func(p string, fi os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if fi.IsDir() {
			return nil
		}
		if !strings.HasSuffix(p, ".smali") && !strings.HasSuffix(p, ".dex") {
			return nil
		}

		data, err := os.ReadFile(p)
		if err != nil {
			return nil
		}
		content := string(data)
		lines := strings.Split(content, "\n")
		totalLines += len(lines)
		fileCount++

		for _, line := range lines {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, ".class ") {
				totalClasses++
			}
			if strings.HasPrefix(line, ".method ") {
				totalMethods++
			}
			if line != "" && !strings.HasPrefix(line, "#") && !strings.HasPrefix(line, ".") && !strings.HasPrefix(line, ":") {
				totalInstructions++
			}
		}
		return nil
	})

	result.Success = true
	result.Files = fileCount
	result.Instructions = totalInstructions
	result.Classes = totalClasses
	result.Methods = totalMethods

	return result
}

func findSmali() string {
	paths := []string{
		"/usr/local/bin/smali.jar",
		"/usr/share/java/smali.jar",
		"smali.jar",
	}
	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

func findBaksmali() string {
	paths := []string{
		"/usr/local/bin/baksmali.jar",
		"/usr/share/java/baksmali.jar",
		"baksmali.jar",
	}
	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

func emitJSON(v interface{}) {
	data, _ := json.MarshalIndent(v, "", "  ")
	fmt.Println(string(data))
}
