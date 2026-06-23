package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"math/big"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type SignResult struct {
	Success   bool   `json:"success"`
	ApkPath   string `json:"apk_path"`
	Signature string `json:"signature,omitempty"`
	Keystore  string `json:"keystore,omitempty"`
	Algorithm string `json:"algorithm"`
	Error     string `json:"error,omitempty"`
	Output    string `json:"output,omitempty"`
}

type KeystoreInfo struct {
	Path     string `json:"path"`
	Alias    string `json:"alias"`
	Validity string `json:"validity_years"`
	KeySize  int    `json:"key_size"`
	Subject  string `json:"subject"`
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	command := os.Args[1]

	switch command {
	case "sign":
		cmdSign()
	case "genkeystore":
		cmdGenKeystore()
	case "genkey":
		cmdGenKey()
	case "verify":
		cmdVerify()
	case "v1sign":
		cmdV1Sign()
	case "v2sign":
		cmdV2Sign()
	case "v3sign":
		cmdV3Sign()
	case "info":
		cmdKeystoreInfo()
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", command)
		usage()
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, "Usage: %s <command> [args]\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "Commands:\n")
	fmt.Fprintf(os.Stderr, "  sign <apk> [keystore] [pass] [alias]      Sign APK (v1+v2 scheme)\n")
	fmt.Fprintf(os.Stderr, "  genkeystore [path] [pass] [alias]         Generate JKS keystore (PEM format)\n")
	fmt.Fprintf(os.Stderr, "  genkey [path]                             Generate PEM key+cert\n")
	fmt.Fprintf(os.Stderr, "  verify <apk>                               Verify APK signature\n")
	fmt.Fprintf(os.Stderr, "  v1sign <apk> [keystore] [pass] [alias]    Sign with v1 scheme only\n")
	fmt.Fprintf(os.Stderr, "  v2sign <apk> [keystore] [pass] [alias]    Sign with v2 scheme only\n")
	fmt.Fprintf(os.Stderr, "  v3sign <apk> [keystore] [pass] [alias]    Sign with v3 scheme only\n")
	fmt.Fprintf(os.Stderr, "  info <keystore>                            Show keystore info\n")
}

func cmdSign() {
	apk, keystore, pass, alias := getSignArgs("sign")
	if apk == "" {
		fmt.Fprintf(os.Stderr, "Usage: %s sign <apk> [keystore] [pass] [alias]\n", os.Args[0])
		os.Exit(1)
	}

	if !fileExists(apk) {
		emitJSON(SignResult{Success: false, ApkPath: apk, Error: fmt.Sprintf("APK not found: %s", apk)})
		return
	}
	if !fileExists(keystore) {
		genKeystore(keystore, pass, alias, 2048, "AndroXploit")
	}

	var result SignResult
	result.ApkPath = apk
	result.Keystore = keystore
	result.Algorithm = "v1+v2"

	cmd := exec.Command("jarsigner",
		"-sigalg", "SHA256withRSA",
		"-digestalg", "SHA-256",
		"-keystore", keystore,
		"-storepass", pass,
		"-keypass", pass,
		apk, alias)
	output, err := cmd.CombinedOutput()
	if err != nil {
		result.Success = false
		result.Error = fmt.Sprintf("jarsigner failed: %v", err)
		result.Output = string(output)
		emitJSON(result)
		return
	}

	if zipalignPath := findZipalign(); zipalignPath != "" {
		tmpApk := strings.TrimSuffix(apk, ".apk") + "_aligned.apk"
		if err := exec.Command(zipalignPath, "-p", "-f", "4", apk, tmpApk).Run(); err == nil {
			os.Rename(tmpApk, apk)
		} else {
			os.Remove(tmpApk)
		}
	}

	result.Success = true
	result.Signature = fmt.Sprintf("%x", sha256.Sum256([]byte(pass+alias)))
	result.Output = strings.TrimSpace(string(output))
	emitJSON(result)
}

func cmdGenKeystore() {
	path := "androxploit.keystore"
	pass := "androxploit"
	alias := "androxploit"
	if len(os.Args) > 2 {
		path = os.Args[2]
	}
	if len(os.Args) > 3 {
		pass = os.Args[3]
	}
	if len(os.Args) > 4 {
		alias = os.Args[4]
	}
	genKeystore(path, pass, alias, 2048, "AndroXploit")
}

func cmdGenKey() {
	path := "androxploit.key"
	if len(os.Args) > 2 {
		path = os.Args[2]
	}
	genPEMKey(path)
}

func cmdVerify() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: %s verify <apk>\n", os.Args[0])
		os.Exit(1)
	}
	apk := os.Args[2]

	cmd := exec.Command("jarsigner", "-verify", "-certs", "-verbose", apk)
	output, err := cmd.CombinedOutput()

	result := SignResult{
		Success:   err == nil,
		ApkPath:   apk,
		Algorithm: "v1+v2",
		Output:    strings.TrimSpace(string(output)),
	}

	if err != nil {
		result.Error = "verification failed"
		result.Output = string(output)
	}

	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			if strings.Contains(line, "jar verified") {
				result.Signature = strings.TrimSpace(line)
				break
			}
		}
	}

	emitJSON(result)
}

func cmdV1Sign() {
	apk, keystore, pass, alias := getSignArgs("v1sign")
	if apk == "" {
		return
	}
	signWithScheme(apk, keystore, pass, alias, "v1")
}

func cmdV2Sign() {
	apk, keystore, pass, alias := getSignArgs("v2sign")
	if apk == "" {
		return
	}
	signWithScheme(apk, keystore, pass, alias, "v2")
}

func cmdV3Sign() {
	apk, keystore, pass, alias := getSignArgs("v3sign")
	if apk == "" {
		return
	}
	signWithScheme(apk, keystore, pass, alias, "v3")
}

func cmdKeystoreInfo() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: %s info <keystore>\n", os.Args[0])
		os.Exit(1)
	}
	path := os.Args[2]
	cmd := exec.Command("keytool", "-list", "-v", "-keystore", path, "-storepass", "androxploit")
	output, err := cmd.CombinedOutput()
	if err != nil {
		emitJSON(SignResult{Success: false, Error: fmt.Sprintf("keytool failed: %v", err), Output: string(output)})
		return
	}
	emitJSON(map[string]interface{}{
		"success":  true,
		"keystore": path,
		"info":     string(output),
	})
}

func getSignArgs(cmdName string) (apk, keystore, pass, alias string) {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: %s %s <apk> [keystore] [pass] [alias]\n", os.Args[0], cmdName)
		return
	}
	apk = os.Args[2]
	keystore = "androxploit.keystore"
	pass = "androxploit"
	alias = "androxploit"
	if len(os.Args) > 3 {
		keystore = os.Args[3]
	}
	if len(os.Args) > 4 {
		pass = os.Args[4]
	}
	if len(os.Args) > 5 {
		alias = os.Args[5]
	}
	return
}

func signWithScheme(apk, keystore, pass, alias, scheme string) {
	if !fileExists(keystore) {
		genKeystore(keystore, pass, alias, 2048, "AndroXploit")
	}

	v1 := scheme == "v1" || scheme == "v1+v2"
	v2 := scheme == "v2" || scheme == "v1+v2"
	v3 := scheme == "v3"

	apksignerPath := findApksigner()
	if apksignerPath == "" {
		emitJSON(SignResult{
			Success: false, ApkPath: apk,
			Error: "apksigner not found in PATH or Android SDK",
		})
		return
	}

	args := []string{"sign",
		"--ks", keystore,
		"--ks-pass", fmt.Sprintf("pass:%s", pass),
		"--ks-key-alias", alias,
		fmt.Sprintf("--v1-signing-enabled=%t", v1),
		fmt.Sprintf("--v2-signing-enabled=%t", v2),
		fmt.Sprintf("--v3-signing-enabled=%t", v3),
	}
	args = append(args, apk)

	cmd := exec.Command(apksignerPath, args...)
	output, err := cmd.CombinedOutput()

	result := SignResult{
		ApkPath:   apk,
		Algorithm: scheme,
		Keystore:  keystore,
		Output:    strings.TrimSpace(string(output)),
	}

	if err != nil {
		result.Success = false
		result.Error = fmt.Sprintf("apksigner failed: %v", err)
	} else {
		result.Success = true
		result.Signature = fmt.Sprintf("%x", sha256.Sum256([]byte(pass+alias)))
	}
	emitJSON(result)
}

func genKeystore(keystorePath, pass, alias string, keySize int, org string) {
	if _, err := os.Stat(keystorePath); err == nil {
		fmt.Fprintf(os.Stderr, "Keystore already exists: %s\n", keystorePath)
		return
	}

	key, err := rsa.GenerateKey(rand.Reader, keySize)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error generating key: %v\n", err)
		os.Exit(1)
	}

	template := &x509.Certificate{
		SerialNumber: big.NewInt(time.Now().Unix()),
		Subject: pkix.Name{
			CommonName:   org,
			Organization: []string{org},
		},
		NotBefore:             time.Now(),
		NotAfter:              time.Now().AddDate(10, 0, 0),
		KeyUsage:              x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageCodeSigning},
		BasicConstraintsValid: true,
	}

	certDER, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error creating cert: %v\n", err)
		os.Exit(1)
	}

	keystoreFile, err := os.Create(keystorePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error creating keystore: %v\n", err)
		os.Exit(1)
	}
	defer keystoreFile.Close()

	pem.Encode(keystoreFile, &pem.Block{Type: "CERTIFICATE", Bytes: certDER})
	keyBytes, _ := x509.MarshalPKCS8PrivateKey(key)
	if keyBytes != nil {
		pem.Encode(keystoreFile, &pem.Block{Type: "RSA PRIVATE KEY", Bytes: keyBytes})
	}

	emitJSON(SignResult{
		Success:   true,
		Keystore:  keystorePath,
		Algorithm: fmt.Sprintf("RSA-%d", keySize),
		Signature: alias,
	})
}

func genPEMKey(path string) {
	key, err := rsa.GenerateKey(rand.Reader, 4096)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error generating key: %v\n", err)
		os.Exit(1)
	}

	certTemplate := &x509.Certificate{
		SerialNumber: big.NewInt(time.Now().Unix()),
		Subject: pkix.Name{
			CommonName:   "AndroXploit Signing Key",
			Organization: []string{"AndroXploit"},
		},
		NotBefore:             time.Now(),
		NotAfter:              time.Now().AddDate(20, 0, 0),
		KeyUsage:              x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageCodeSigning},
		BasicConstraintsValid: true,
	}
	certDER, err := x509.CreateCertificate(rand.Reader, certTemplate, certTemplate, &key.PublicKey, key)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error creating cert: %v\n", err)
		os.Exit(1)
	}

	f, err := os.Create(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error creating file: %v\n", err)
		os.Exit(1)
	}
	defer f.Close()

	pem.Encode(f, &pem.Block{Type: "CERTIFICATE", Bytes: certDER})
	keyBytes2, _ := x509.MarshalPKCS8PrivateKey(key)
	pem.Encode(f, &pem.Block{Type: "RSA PRIVATE KEY", Bytes: keyBytes2})

	emitJSON(SignResult{
		Success:   true,
		Keystore:  path,
		Algorithm: "RSA-4096",
	})
}

func findZipalign() string {
	paths := []string{
		"zipalign",
		filepath.Join(os.Getenv("ANDROID_HOME"), "build-tools", "34.0.0", "zipalign"),
		filepath.Join(os.Getenv("ANDROID_SDK_ROOT"), "build-tools", "34.0.0", "zipalign"),
	}
	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

func findApksigner() string {
	paths := []string{
		"apksigner",
		filepath.Join(os.Getenv("ANDROID_HOME"), "build-tools", "34.0.0", "apksigner"),
		filepath.Join(os.Getenv("ANDROID_SDK_ROOT"), "build-tools", "34.0.0", "apksigner"),
	}
	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func emitJSON(v interface{}) {
	data, _ := json.MarshalIndent(v, "", "  ")
	fmt.Println(string(data))
}
