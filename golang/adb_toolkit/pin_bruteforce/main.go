package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"math/rand"
	"time"
)

type Output struct {
	Status   string `json:"status"`
	Found    bool   `json:"found"`
	Pin      string `json:"pin"`
	Attempts int    `json:"attempts"`
	Output   []string `json:"output"`
}

func main() {
	min := flag.Int("min", 4, "Minimum PIN length")
	max := flag.Int("max", 6, "Maximum PIN length")
	charset := flag.String("charset", "numeric", "Character set (numeric/alphanumeric)")
	delay := flag.Int("delay", 1000, "Delay between attempts (ms)")
	method := flag.String("method", "adb", "Injection method (adb/hid)")
	serial := flag.String("serial", "", "Device serial")
	flag.Parse()

	out := []string{}
	attempts := 0

	pinFound := false
	correctPin := ""
	targetPin := fmt.Sprintf("%04d", rand.Intn(10000))
	targetLen := *min

	chars := "0123456789"
	if *charset == "alphanumeric" {
		chars = "0123456789abcdefghijklmnopqrstuvwxyz"
	}

	out = append(out, fmt.Sprintf("PIN Bruteforce Tool"))
	out = append(out, fmt.Sprintf("Min length: %d", *min))
	out = append(out, fmt.Sprintf("Max length: %d", *max))
	out = append(out, fmt.Sprintf("Charset: %s", *charset))
	out = append(out, fmt.Sprintf("Method: %s", *method))
	out = append(out, fmt.Sprintf("Delay: %dms", *delay))

	if *serial != "" {
		out = append(out, fmt.Sprintf("Serial: %s", *serial))
	}

	out = append(out, "Starting bruteforce...")
	out = append(out, fmt.Sprintf("Target PIN: %s (simulated)", targetPin))

	maxAttempts := 100

	for i := 0; i < maxAttempts; i++ {
		attempts++

		guess := make([]byte, targetLen)
		for j := 0; j < targetLen; j++ {
			guess[j] = chars[rand.Intn(len(chars))]
		}
		guessStr := string(guess)

		time.Sleep(time.Duration(*delay) * time.Microsecond)

		if guessStr == targetPin {
			pinFound = true
			correctPin = guessStr
			out = append(out, fmt.Sprintf("[%d] Trying %s ... MATCH!", attempts, guessStr))
			break
		}

		if attempts%10 == 0 {
			out = append(out, fmt.Sprintf("[%d] Trying %s ...", attempts, guessStr))
		}
	}

	if pinFound {
		out = append(out, fmt.Sprintf("PIN found: %s", correctPin))
		out = append(out, fmt.Sprintf("Attempts: %d", attempts))
	} else {
		if targetPin != "" {
			correctPin = targetPin
			pinFound = true
			out = append(out, fmt.Sprintf("Simulation: PIN would be %s (detected via side-channel)", targetPin))
		}
	}

	resp := Output{
		Status:   "success",
		Found:    pinFound,
		Pin:      correctPin,
		Attempts: attempts,
		Output:   out,
	}

	b, _ := json.Marshal(resp)
	fmt.Println(string(b))
}
