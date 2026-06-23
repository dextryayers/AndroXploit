package main

import (
	"archive/zip"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

type APKInfo struct {
	FileName      string          `json:"file_name"`
	FilePath      string          `json:"file_path"`
	FileSize      int64           `json:"file_size"`
	FileSizeHuman string          `json:"file_size_human"`
	Entries       []ZipEntry      `json:"entries"`
	EntryCount    int             `json:"entry_count"`
	ManifestInfo  *ManifestInfo   `json:"manifest_info,omitempty"`
	Secrets       []SecretFinding `json:"secrets,omitempty"`
	Certificates  []CertInfo      `json:"certificates,omitempty"`
	HasDex        bool            `json:"has_dex"`
	HasNative     bool            `json:"has_native_code"`
	HasRes        bool            `json:"has_resources"`
	IsFramework   bool            `json:"is_framework"`
}

type ZipEntry struct {
	Name        string `json:"name"`
	Size        int64  `json:"size"`
	Compressed  int64  `json:"compressed"`
	CompressPct int    `json:"compression_pct"`
	CRC32       uint32 `json:"crc32"`
}

type ManifestInfo struct {
	PackageName  string   `json:"package_name,omitempty"`
	VersionName  string   `json:"version_name,omitempty"`
	VersionCode  string   `json:"version_code,omitempty"`
	MinSDK       string   `json:"min_sdk,omitempty"`
	TargetSDK    string   `json:"target_sdk,omitempty"`
	Permissions  []string `json:"permissions,omitempty"`
	Activities   []string `json:"activities,omitempty"`
	Services     []string `json:"services,omitempty"`
	Receivers    []string `json:"receivers,omitempty"`
	Providers    []string `json:"providers,omitempty"`
	Intents      []string `json:"intent_filters,omitempty"`
	Features     []string `json:"features,omitempty"`
	Libraries    []string `json:"libraries,omitempty"`
}

type SecretFinding struct {
	Type  string `json:"type"`
	Value string `json:"value"`
	File  string `json:"file"`
	Line  int    `json:"line,omitempty"`
}

type CertInfo struct {
	Subject    string `json:"subject"`
	Issuer     string `json:"issuer"`
	Serial     string `json:"serial_number"`
	Algorithm  string `json:"signature_algorithm"`
	NotBefore  string `json:"not_before"`
	NotAfter   string `json:"not_after"`
	SHA1       string `json:"sha1"`
	SHA256     string `json:"sha256"`
}

var secretPatterns = []struct {
	Name    string
	Pattern *regexp.Regexp
}{
	{"AWS Access Key", regexp.MustCompile(`AKIA[0-9A-Z]{16}`)},
	{"AWS Secret Key", regexp.MustCompile(`(?i)aws[_-]?secret[_-]?access[_-]?key[\s"':=]+[A-Za-z0-9\/+]{40}`)},
	{"Google API Key", regexp.MustCompile(`AIza[0-9A-Za-z\-_]{35}`)},
	{"Google OAuth", regexp.MustCompile(`[0-9]+-[0-9a-zA-Z_]{32}\.apps\.googleusercontent\.com`)},
	{"GitHub Token", regexp.MustCompile(`gh[pousr]_[A-Za-z0-9_]{36,}`)},
	{"GitHub Classic", regexp.MustCompile(`[0-9a-f]{40}`)},
	{"JWT Token", regexp.MustCompile(`eyJ[a-zA-Z0-9_-]+\.eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+`)},
	{"Slack Token", regexp.MustCompile(`xox[baprs]-[0-9a-zA-Z\-]{10,}`)},
	{"Slack Webhook", regexp.MustCompile(`https://hooks\.slack\.com/services/[A-Za-z0-9/]+`)},
	{"OpenAI Key", regexp.MustCompile(`sk-[0-9a-zA-Z]{32,}`)},
	{"Private Key", regexp.MustCompile(`-----BEGIN (RSA|EC|DSA|OPENSSH|PRIVATE) KEY-----`)},
	{"Facebook Token", regexp.MustCompile(`EAACEdEose0cBA[0-9A-Za-z]+`)},
	{"Firebase URL", regexp.MustCompile(`https://[a-zA-Z0-9-]+\.firebaseio\.com`)},
	{"Heroku API", regexp.MustCompile(`[hH][eE][rR][oO][kK][uU].*[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}`)},
	{"Twilio Key", regexp.MustCompile(`SK[0-9a-fA-F]{32}`)},
	{"MariaDB/MySQL Connection", regexp.MustCompile(`mysql://[a-zA-Z0-9]+:[^@\s]+@`)},
	{"MongoDB Connection", regexp.MustCompile(`mongodb(?:\+srv)?://[a-zA-Z0-9]+:[^@\s]+@`)},
	{"PostgreSQL Connection", regexp.MustCompile(`postgres(?:ql)?://[a-zA-Z0-9]+:[^@\s]+@`)},
	{"Redis Connection", regexp.MustCompile(`redis://[^@\s]+@`)},
	{"Password in String", regexp.MustCompile(`(?i)(\"password\"|\"passwd\"|\"pwd\")\s*:\s*\"[^\"]{4,}\"`)},
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: %s <apk_file>\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "Parses APK files and extracts manifest, secrets, and certificate info.\n")
		fmt.Fprintf(os.Stderr, "Example: %s target.apk\n", os.Args[0])
		os.Exit(1)
	}
	apkPath := os.Args[1]
	info, err := analyzeAPK(apkPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	emitJSON(info)
}

func analyzeAPK(path string) (*APKInfo, error) {
	info := &APKInfo{
		FileName: filepath.Base(path),
		FilePath: path,
	}
	stat, err := os.Stat(path)
	if err != nil {
		return nil, fmt.Errorf("cannot stat file %s: %w", path, err)
	}
	info.FileSize = stat.Size()
	info.FileSizeHuman = formatBytes(stat.Size())

	reader, err := zip.OpenReader(path)
	if err != nil {
		return nil, fmt.Errorf("cannot open APK as zip: %w", err)
	}
	defer reader.Close()

	info.EntryCount = len(reader.File)

	for _, f := range reader.File {
		compressPct := 0
		if f.UncompressedSize64 > 0 {
			compressPct = 100 - int((f.CompressedSize64*100)/f.UncompressedSize64)
		}
		entry := ZipEntry{
			Name:        f.Name,
			Size:        int64(f.UncompressedSize64),
			Compressed:  int64(f.CompressedSize64),
			CompressPct: compressPct,
			CRC32:       f.CRC32,
		}
		info.Entries = append(info.Entries, entry)

		if f.Name == "AndroidManifest.xml" {
			mInfo := parseManifest(f)
			info.ManifestInfo = mInfo
		}

		ext := strings.ToLower(filepath.Ext(f.Name))
		if ext == ".dex" {
			info.HasDex = true
		}
		if ext == ".so" {
			info.HasNative = true
		}
		if ext == ".png" || ext == ".jpg" || ext == ".xml" || ext == ".arsc" {
			info.HasRes = true
		}

		if ext != ".dex" && ext != ".so" && ext != ".png" && ext != ".jpg" && ext != ".jpeg" && ext != ".mp3" && ext != ".mp4" {
			secrets := scanFileForSecrets(f)
			info.Secrets = append(info.Secrets, secrets...)
		}

		if f.Name == "META-INF/CERT.RSA" || f.Name == "META-INF/CERT.DSA" || strings.HasSuffix(f.Name, ".SF") {
			if strings.HasSuffix(f.Name, ".RSA") || strings.HasSuffix(f.Name, ".DSA") {
				certs := parseCertFromEntry(f)
				info.Certificates = append(info.Certificates, certs...)
			}
		}
	}

	return info, nil
}

func parseManifest(f *zip.File) *ManifestInfo {
	m := &ManifestInfo{}
	rc, err := f.Open()
	if err != nil {
		return m
	}
	defer rc.Close()

	data, err := io.ReadAll(rc)
	if err != nil {
		return m
	}
	text := string(data)
	text = strings.ReplaceAll(text, "\x00", "")

	rePkg := regexp.MustCompile(`package\s*=\s*"([^"]+)"`)
	if match := rePkg.FindStringSubmatch(text); len(match) > 1 {
		m.PackageName = match[1]
	}

	reVerName := regexp.MustCompile(`versionName\s*=\s*"([^"]+)"`)
	if match := reVerName.FindStringSubmatch(text); len(match) > 1 {
		m.VersionName = match[1]
	}

	reVerCode := regexp.MustCompile(`versionCode\s*=\s*"([^"]+)"`)
	if match := reVerCode.FindStringSubmatch(text); len(match) > 1 {
		m.VersionCode = match[1]
	}

	reMinSDK := regexp.MustCompile(`minSdkVersion\s*=\s*"([^"]+)"`)
	if match := reMinSDK.FindStringSubmatch(text); len(match) > 1 {
		m.MinSDK = match[1]
	}

	reTargetSDK := regexp.MustCompile(`targetSdkVersion\s*=\s*"([^"]+)"`)
	if match := reTargetSDK.FindStringSubmatch(text); len(match) > 1 {
		m.TargetSDK = match[1]
	}

	rePerm := regexp.MustCompile(`uses-permission[^>]*name\s*=\s*"([^"]+)"`)
	for _, match := range rePerm.FindAllStringSubmatch(text, -1) {
		if len(match) > 1 {
			m.Permissions = append(m.Permissions, match[1])
		}
	}

	reAct := regexp.MustCompile(`<activity[^>]*name\s*=\s*"([^"]+)"`)
	for _, match := range reAct.FindAllStringSubmatch(text, -1) {
		if len(match) > 1 {
			m.Activities = append(m.Activities, match[1])
		}
	}

	reSvc := regexp.MustCompile(`<service[^>]*name\s*=\s*"([^"]+)"`)
	for _, match := range reSvc.FindAllStringSubmatch(text, -1) {
		if len(match) > 1 {
			m.Services = append(m.Services, match[1])
		}
	}

	reRcv := regexp.MustCompile(`<receiver[^>]*name\s*=\s*"([^"]+)"`)
	for _, match := range reRcv.FindAllStringSubmatch(text, -1) {
		if len(match) > 1 {
			m.Receivers = append(m.Receivers, match[1])
		}
	}

	rePrv := regexp.MustCompile(`<provider[^>]*name\s*=\s*"([^"]+)"`)
	for _, match := range rePrv.FindAllStringSubmatch(text, -1) {
		if len(match) > 1 {
			m.Providers = append(m.Providers, match[1])
		}
	}

	reIntent := regexp.MustCompile(`<action[^>]*name\s*=\s*"([^"]+)"`)
	for _, match := range reIntent.FindAllStringSubmatch(text, -1) {
		if len(match) > 1 {
			m.Intents = append(m.Intents, match[1])
		}
	}

	reFeature := regexp.MustCompile(`uses-feature[^>]*name\s*=\s*"([^"]+)"`)
	for _, match := range reFeature.FindAllStringSubmatch(text, -1) {
		if len(match) > 1 {
			m.Features = append(m.Features, match[1])
		}
	}

	reLib := regexp.MustCompile(`uses-library[^>]*name\s*=\s*"([^"]+)"`)
	for _, match := range reLib.FindAllStringSubmatch(text, -1) {
		if len(match) > 1 {
			m.Libraries = append(m.Libraries, match[1])
		}
	}

	return m
}

func scanFileForSecrets(f *zip.File) []SecretFinding {
	var findings []SecretFinding
	rc, err := f.Open()
	if err != nil {
		return findings
	}
	defer rc.Close()

	data, err := io.ReadAll(rc)
	if err != nil {
		return findings
	}

	if len(data) > 0 && data[0] == 0 {
		return findings
	}

	textContent := string(data)

	if !isPrintable(textContent) {
		return findings
	}

	for _, sp := range secretPatterns {
		matches := sp.Pattern.FindAllString(textContent, 5)
		for _, match := range matches {
			clean := match
			if len(clean) > 40 {
				clean = clean[:40] + "..."
			}
			lineNo := findLineNumber(textContent, match)
			findings = append(findings, SecretFinding{
				Type:  sp.Name,
				Value: clean,
				File:  f.Name,
				Line:  lineNo,
			})
		}
	}
	return findings
}

func isPrintable(s string) bool {
	printable := 0
	total := len(s)
	if total == 0 {
		return false
	}
	for _, r := range s {
		if r >= 32 && r <= 126 || r == '\n' || r == '\r' || r == '\t' {
			printable++
		}
	}
	return float64(printable)/float64(total) > 0.6
}

func findLineNumber(content, substr string) int {
	idx := strings.Index(content, substr)
	if idx < 0 {
		return 0
	}
	return strings.Count(content[:idx], "\n") + 1
}

func parseCertFromEntry(f *zip.File) []CertInfo {
	var certs []CertInfo
	rc, err := f.Open()
	if err != nil {
		return certs
	}
	defer rc.Close()

	data, err := io.ReadAll(rc)
	if err != nil {
		return certs
	}

	for block, rest := pem.Decode(data); block != nil; block, rest = pem.Decode(rest) {
		if block.Type == "CERTIFICATE" || block.Type == "TRUSTED CERTIFICATE" || block.Type == "X509 CERTIFICATE" {
			cert, err := x509.ParseCertificate(block.Bytes)
			if err == nil {
				certs = append(certs, extractCertInfo(cert))
			}
		}
	}

	if len(certs) == 0 {
		cert, err := x509.ParseCertificate(data)
		if err == nil {
			certs = append(certs, extractCertInfo(cert))
		}
	}

	return certs
}

func extractCertInfo(cert *x509.Certificate) CertInfo {
	c := CertInfo{
		Subject:   cert.Subject.CommonName,
		Issuer:    cert.Issuer.CommonName,
		Serial:    cert.SerialNumber.String(),
		Algorithm: cert.SignatureAlgorithm.String(),
		NotBefore: cert.NotBefore.Format("2006-01-02 15:04:05"),
		NotAfter:  cert.NotAfter.Format("2006-01-02 15:04:05"),
		SHA1:      fmt.Sprintf("%x", sha1.Sum(cert.Raw)),
		SHA256:    fmt.Sprintf("%x", sha256.Sum256(cert.Raw)),
	}
	if c.Subject == "" && len(cert.Subject.Organization) > 0 {
		c.Subject = cert.Subject.Organization[0]
	}
	if c.Issuer == "" && len(cert.Issuer.Organization) > 0 {
		c.Issuer = cert.Issuer.Organization[0]
	}
	return c
}

func formatBytes(size int64) string {
	units := []string{"B", "KB", "MB", "GB", "TB"}
	val := float64(size)
	for _, unit := range units {
		if val < 1024 {
			return fmt.Sprintf("%.2f %s", val, unit)
		}
		val /= 1024
	}
	return fmt.Sprintf("%.2f PB", val)
}

func emitJSON(v interface{}) {
	data, _ := json.MarshalIndent(v, "", "  ")
	fmt.Println(string(data))
}
