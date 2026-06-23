package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"
)

type EncoderResult struct {
	Success   bool        `json:"success"`
	Input     string      `json:"input"`
	Output    string      `json:"output"`
	Method    string      `json:"method"`
	KeyUsed   string      `json:"key_used,omitempty"`
	LengthIn  int         `json:"length_in"`
	LengthOut int         `json:"length_out"`
	Error     string      `json:"error,omitempty"`
	Results   []EncodedVariant `json:"variants,omitempty"`
}

type EncodedVariant struct {
	Method string `json:"method"`
	Output string `json:"output"`
}

func main() {
	if len(os.Args) < 3 {
		usage()
		os.Exit(1)
	}

	method := os.Args[1]
	input := os.Args[2]
	key := ""
	if len(os.Args) > 3 {
		key = os.Args[3]
	}

	if method == "list" {
		emitJSON(EncoderResult{
			Success: true,
			Output:  "Available methods: b64, b64_decode, b64_multi, hex, hex_encode, hex_decode, xor, aes_encrypt, aes_decrypt, reverse, rot13, rot47, unicode, decimal, html_entity, escape, octal, binary, url, custom, detect, all",
		})
		return
	}

	if method == "all" {
		var results []EncodedVariant
		for _, m := range []string{"b64", "hex", "xor", "reverse", "rot13", "rot47", "unicode", "decimal", "html_entity", "escape", "octal", "binary", "url"} {
			r := encodeSingle(input, m, key)
			results = append(results, EncodedVariant{Method: m, Output: r.Output})
		}
		emitJSON(EncoderResult{
			Success:  true,
			Input:    input,
			Method:   "all",
			LengthIn: len(input),
			Results:  results,
		})
		return
	}

	result := encodeSingle(input, method, key)
	emitJSON(result)
}

func encodeSingle(input, method, key string) EncoderResult {
	var result EncoderResult
	result.Input = input
	result.Method = method
	result.LengthIn = len(input)

	switch method {
	case "b64":
		result.Output = base64.StdEncoding.EncodeToString([]byte(input))
		result.Success = true

	case "b64_decode":
		decoded, err := base64.StdEncoding.DecodeString(input)
		if err != nil {
			decoded, err = base64.URLEncoding.DecodeString(input)
		}
		if err != nil {
			result.Error = fmt.Sprintf("base64 decode failed: %v", err)
		} else {
			result.Output = string(decoded)
			result.Success = true
		}

	case "b64_multi":
		encoded := base64.StdEncoding.EncodeToString([]byte(input))
		for i := 0; i < 5; i++ {
			encoded = base64.StdEncoding.EncodeToString([]byte(encoded))
		}
		result.Output = encoded
		result.Success = true

	case "hex", "hex_encode":
		result.Output = hex.EncodeToString([]byte(input))
		result.Success = true

	case "hex_decode":
		cleaned := strings.NewReplacer(" ", "", "\n", "", "\r", "", "\t", "").Replace(input)
		decoded, err := hex.DecodeString(cleaned)
		if err != nil {
			result.Error = fmt.Sprintf("hex decode failed: %v", err)
		} else {
			result.Output = string(decoded)
			result.Success = true
		}

	case "xor":
		if key == "" {
			key = "A"
		}
		out := make([]byte, len(input))
		for i := 0; i < len(input); i++ {
			out[i] = input[i] ^ key[i%len(key)]
		}
		result.Output = base64.StdEncoding.EncodeToString(out)
		result.KeyUsed = key
		result.Success = true

	case "xor_hex":
		if key == "" {
			key = "A"
		}
		out := make([]byte, len(input))
		for i := 0; i < len(input); i++ {
			out[i] = input[i] ^ key[i%len(key)]
		}
		result.Output = hex.EncodeToString(out)
		result.KeyUsed = key
		result.Success = true

	case "aes", "aes_encrypt":
		if key == "" {
			key = "AndroXploitKey16!"
		}
		for len(key) < 16 {
			key += "X"
		}
		key = key[:16]

		block, err := aes.NewCipher([]byte(key))
		if err != nil {
			result.Error = fmt.Sprintf("aes cipher failed: %v", err)
			return result
		}

		plaintext := padPKCS7([]byte(input), aes.BlockSize)
		ciphertext := make([]byte, aes.BlockSize+len(plaintext))
		iv := ciphertext[:aes.BlockSize]
		if _, err := io.ReadFull(rand.Reader, iv); err != nil {
			result.Error = fmt.Sprintf("iv generation failed: %v", err)
			return result
		}

		mode := cipher.NewCBCEncrypter(block, iv)
		mode.CryptBlocks(ciphertext[aes.BlockSize:], plaintext)

		result.Output = base64.StdEncoding.EncodeToString(ciphertext)
		result.KeyUsed = key
		result.Success = true

	case "aes_decrypt":
		if key == "" {
			key = "AndroXploitKey16!"
		}
		for len(key) < 16 {
			key += "X"
		}
		key = key[:16]

		ciphertext, err := base64.StdEncoding.DecodeString(input)
		if err != nil {
			result.Error = fmt.Sprintf("base64 decode failed: %v", err)
			return result
		}

		block, err := aes.NewCipher([]byte(key))
		if err != nil {
			result.Error = fmt.Sprintf("aes cipher failed: %v", err)
			return result
		}

		if len(ciphertext) < aes.BlockSize {
			result.Error = "ciphertext too short"
			return result
		}

		iv := ciphertext[:aes.BlockSize]
		ciphertext = ciphertext[aes.BlockSize:]

		mode := cipher.NewCBCDecrypter(block, iv)
		mode.CryptBlocks(ciphertext, ciphertext)

		plaintext := unpadPKCS7(ciphertext)
		result.Output = string(plaintext)
		result.KeyUsed = key
		result.Success = true

	case "reverse":
		runes := []rune(input)
		for i, j := 0, len(runes)-1; i < j; i, j = i+1, j-1 {
			runes[i], runes[j] = runes[j], runes[i]
		}
		result.Output = string(runes)
		result.Success = true

	case "rot13":
		out := make([]byte, len(input))
		for i := 0; i < len(input); i++ {
			c := input[i]
			switch {
			case c >= 'a' && c <= 'z':
				out[i] = 'a' + (c-'a'+13)%26
			case c >= 'A' && c <= 'Z':
				out[i] = 'A' + (c-'A'+13)%26
			default:
				out[i] = c
			}
		}
		result.Output = string(out)
		result.Success = true

	case "rot47":
		out := make([]byte, len(input))
		for i := 0; i < len(input); i++ {
			c := input[i]
			if c >= 33 && c <= 126 {
				out[i] = 33 + (c-33+47)%94
			} else {
				out[i] = c
			}
		}
		result.Output = string(out)
		result.Success = true

	case "unicode":
		out := ""
		for _, r := range input {
			out += fmt.Sprintf("\\u%04x", r)
		}
		result.Output = out
		result.Success = true

	case "decimal":
		out := ""
		for _, b := range []byte(input) {
			if out != "" {
				out += " "
			}
			out += fmt.Sprintf("%d", b)
		}
		result.Output = out
		result.Success = true

	case "html_entity":
		out := ""
		for _, r := range input {
			out += fmt.Sprintf("&#%d;", r)
		}
		result.Output = out
		result.Success = true

	case "escape":
		out := strings.ReplaceAll(input, "\\", "\\\\")
		out = strings.ReplaceAll(out, "'", "\\'")
		out = strings.ReplaceAll(out, "\"", "\\\"")
		out = strings.ReplaceAll(out, "\n", "\\n")
		out = strings.ReplaceAll(out, "\r", "\\r")
		out = strings.ReplaceAll(out, "\t", "\\t")
		result.Output = out
		result.Success = true

	case "octal":
		out := ""
		for _, b := range []byte(input) {
			out += fmt.Sprintf("\\%03o", b)
		}
		result.Output = out
		result.Success = true

	case "binary":
		out := ""
		for _, b := range []byte(input) {
			if out != "" {
				out += " "
			}
			out += fmt.Sprintf("%08b", b)
		}
		result.Output = out
		result.Success = true

	case "url":
		hex := hex.EncodeToString([]byte(input))
		out := ""
		for i := 0; i < len(hex); i += 2 {
			if i+2 <= len(hex) {
				out += "%" + strings.ToUpper(hex[i:i+2])
			}
		}
		result.Output = out
		result.Success = true

	case "custom":
		if key == "" {
			key = "secret"
		}
		out := make([]byte, len(input))
		for i := 0; i < len(input); i++ {
			out[i] = input[i] ^ key[i%len(key)] ^ byte(i)
			out[i] = ^out[i]
		}
		result.Output = base64.StdEncoding.EncodeToString(out)
		result.KeyUsed = key
		result.Success = true

	case "detect":
		result.Output = detectEncoding(input)
		result.Success = true

	default:
		result.Error = fmt.Sprintf("unknown method: %s. Use 'list' for available methods.", method)
	}

	result.LengthOut = len(result.Output)
	return result
}

func usage() {
	fmt.Fprintf(os.Stderr, "Usage: %s <method> <input> [key]\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "Encoding methods: b64, b64_decode, b64_multi, hex, hex_encode, hex_decode\n")
	fmt.Fprintf(os.Stderr, "Crypto methods: xor, xor_hex, aes, aes_encrypt, aes_decrypt\n")
	fmt.Fprintf(os.Stderr, "Transform methods: reverse, rot13, rot47\n")
	fmt.Fprintf(os.Stderr, "Format methods: unicode, decimal, html_entity, escape, octal, binary, url\n")
	fmt.Fprintf(os.Stderr, "Other: custom, detect, all (run all encodings)\n")
	fmt.Fprintf(os.Stderr, "Example: %s b64 \"hello world\"\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "Example: %s xor \"secret\" mykey\n", os.Args[0])
}

func detectEncoding(s string) string {
	if len(s) == 0 {
		return "empty"
	}
	if strings.HasPrefix(s, "\\u") || strings.Contains(s, "\\u00") {
		return "unicode_escape"
	}
	clean := strings.NewReplacer(" ", "", "\n", "", "\r", "").Replace(s)
	if _, err := hex.DecodeString(clean); err == nil && len(clean)%2 == 0 && len(clean) > 4 {
		return "hex"
	}
	if decoded, err := base64.StdEncoding.DecodeString(s); err == nil && len(decoded) > 0 {
		return fmt.Sprintf("base64 (decoded: %q)", string(decoded))
	}
	if decoded, err := base64.URLEncoding.DecodeString(s); err == nil && len(decoded) > 0 {
		return "base64url"
	}
	if strings.HasPrefix(s, "%") && strings.Count(s, "%") > 2 {
		return "url_encoded"
	}
	return "unknown"
}

func padPKCS7(src []byte, blockSize int) []byte {
	padding := blockSize - len(src)%blockSize
	padtext := make([]byte, len(src)+padding)
	copy(padtext, src)
	for i := len(src); i < len(padtext); i++ {
		padtext[i] = byte(padding)
	}
	return padtext
}

func unpadPKCS7(src []byte) []byte {
	if len(src) == 0 {
		return src
	}
	padding := int(src[len(src)-1])
	if padding > len(src) || padding == 0 {
		return src
	}
	for i := len(src) - padding; i < len(src); i++ {
		if int(src[i]) != padding {
			return src
		}
	}
	return src[:len(src)-padding]
}

func emitJSON(v interface{}) {
	data, _ := json.MarshalIndent(v, "", "  ")
	fmt.Println(string(data))
}
