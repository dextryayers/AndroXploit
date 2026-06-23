package main

import (
	"crypto/rsa"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type CertInfo struct {
	Subject      string   `json:"subject"`
	Issuer       string   `json:"issuer"`
	SerialNumber string   `json:"serial_number"`
	NotBefore    string   `json:"not_before"`
	NotAfter     string   `json:"not_after"`
	Expired      bool     `json:"expired"`
	DaysLeft     int      `json:"days_left"`
	DaysSince    int      `json:"days_since_issued"`
	SHA1         string   `json:"sha1_fingerprint"`
	SHA256       string   `json:"sha256_fingerprint"`
	KeyAlgo      string   `json:"key_algorithm"`
	KeySize      int      `json:"key_size"`
	KeyUsage     []string `json:"key_usage,omitempty"`
	SelfSigned   bool     `json:"self_signed"`
	IsCA         bool     `json:"is_ca"`
	DNSNames     []string `json:"dns_names,omitempty"`
	IPAddresses  []string `json:"ip_addresses,omitempty"`
	EmailAddress []string `json:"email_addresses,omitempty"`
	OCSPServer   []string `json:"ocsp_servers,omitempty"`
	IssuerURL    []string `json:"issuer_urls,omitempty"`
	Errors       []string `json:"errors,omitempty"`
	Warnings     []string `json:"warnings,omitempty"`
	FilePath     string   `json:"file_path"`
	FileFormat   string   `json:"file_format"`
}

type CertReport struct {
	Certificates []CertInfo `json:"certificates"`
	Count        int        `json:"count"`
	Valid        bool       `json:"valid"`
	ExpiredCount int        `json:"expired_count"`
	Warnings     []string   `json:"warnings,omitempty"`
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	path := os.Args[1]
	report := &CertReport{}

	info, err := os.Stat(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	if info.IsDir() {
		entries, err := os.ReadDir(path)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading directory: %v\n", err)
			os.Exit(1)
		}

		var mu sync.Mutex
		var wg sync.WaitGroup

		for _, entry := range entries {
			if !entry.IsDir() {
				ext := strings.ToLower(filepath.Ext(entry.Name()))
				if isCertExt(ext) {
					wg.Add(1)
					go func(name string) {
						defer wg.Done()
						certs := parseCertFile(filepath.Join(path, name))
						mu.Lock()
						report.Certificates = append(report.Certificates, certs...)
						mu.Unlock()
					}(entry.Name())
				}
			}
		}
		wg.Wait()
	} else {
		report.Certificates = parseCertFile(path)
	}

	report.Count = len(report.Certificates)
	report.Valid = true

	for _, c := range report.Certificates {
		if c.Expired {
			report.Valid = false
			report.ExpiredCount++
			report.Warnings = append(report.Warnings,
				fmt.Sprintf("Certificate expired: %s (expired %s)", c.Subject, c.NotAfter))
		}
		if c.SelfSigned {
			report.Warnings = append(report.Warnings,
				fmt.Sprintf("Self-signed certificate: %s", c.Subject))
		}
		if c.KeySize < 2048 && c.KeyAlgo == "RSA" {
			report.Warnings = append(report.Warnings,
				fmt.Sprintf("Weak key size (%d bits) for %s", c.KeySize, c.Subject))
		}
		if c.DaysLeft >= 0 && c.DaysLeft < 30 {
			report.Warnings = append(report.Warnings,
				fmt.Sprintf("Certificate expiring soon (%d days): %s", c.DaysLeft, c.Subject))
		}
	}

	emitJSON(report)
}

func usage() {
	fmt.Fprintf(os.Stderr, "Usage: %s <cert_file|directory>\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "  Supports: .pem, .crt, .cer, .der, .p12, .pfx files\n")
	fmt.Fprintf(os.Stderr, "  Scans single file or all cert files in a directory concurrently.\n")
	fmt.Fprintf(os.Stderr, "Examples:\n")
	fmt.Fprintf(os.Stderr, "  %s certificate.pem\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "  %s /path/to/certs/\n", os.Args[0])
}

func isCertExt(ext string) bool {
	switch ext {
	case ".pem", ".crt", ".cer", ".der", ".p12", ".pfx":
		return true
	}
	return false
}

func parseCertFile(path string) []CertInfo {
	var certs []CertInfo
	data, err := os.ReadFile(path)
	if err != nil {
		return certs
	}

	ext := strings.ToLower(filepath.Ext(path))
	format := ext
	isPEM := ext == ".pem" || ext == ".crt" || ext == ".cer"
	isDER := ext == ".der"
	isPKCS := ext == ".p12" || ext == ".pfx"

	switch {
	case isPEM:
		certs = parsePEMCerts(data, path, format)
	case isDER:
		if cert, err := x509.ParseCertificate(data); err == nil {
			ci := extractCertInfo(cert)
			ci.FilePath = path
			ci.FileFormat = "DER"
			certs = append(certs, ci)
		}
	case isPKCS:
		certs = append(certs, CertInfo{
			FilePath:   path,
			FileFormat: "PKCS12/PFX",
			Warnings:   []string{"PKCS12 format detected - use openssl to extract: openssl pkcs12 -in file.p12 -nodes"},
		})
	default:
		certs = parsePEMCerts(data, path, "raw")
	}

	return certs
}

func parsePEMCerts(data []byte, path, format string) []CertInfo {
	var certs []CertInfo
	for block, rest := pem.Decode(data); block != nil; block, rest = pem.Decode(rest) {
		if block.Type == "CERTIFICATE" || block.Type == "TRUSTED CERTIFICATE" || block.Type == "X509 CERTIFICATE" {
			cert, err := x509.ParseCertificate(block.Bytes)
			if err == nil {
				ci := extractCertInfo(cert)
				ci.FilePath = path
				ci.FileFormat = format
				certs = append(certs, ci)
			}
		}
	}

	if len(certs) == 0 {
		if cert, err := x509.ParseCertificate(data); err == nil {
			ci := extractCertInfo(cert)
			ci.FilePath = path
			ci.FileFormat = format
			certs = append(certs, ci)
		}
	}

	return certs
}

func extractCertInfo(cert *x509.Certificate) CertInfo {
	now := time.Now()
	info := CertInfo{
		Subject:      cert.Subject.CommonName,
		Issuer:       cert.Issuer.CommonName,
		SerialNumber: cert.SerialNumber.String(),
		NotBefore:    cert.NotBefore.Format(time.RFC3339),
		NotAfter:     cert.NotAfter.Format(time.RFC3339),
		Expired:      now.After(cert.NotAfter),
		DaysLeft:     int(cert.NotAfter.Sub(now).Hours() / 24),
		DaysSince:    int(now.Sub(cert.NotBefore).Hours() / 24),
		KeyAlgo:      cert.PublicKeyAlgorithm.String(),
		SelfSigned:   cert.Subject.CommonName == cert.Issuer.CommonName,
		IsCA:         cert.IsCA,
		DNSNames:     cert.DNSNames,
		OCSPServer:   cert.OCSPServer,
		IssuerURL:    cert.IssuingCertificateURL,
	}

	switch key := cert.PublicKey.(type) {
	case *rsa.PublicKey:
		info.KeySize = key.N.BitLen()
	}

	for _, usage := range cert.ExtKeyUsage {
		info.KeyUsage = append(info.KeyUsage, extKeyUsageString(usage))
	}
	ku := cert.KeyUsage
	if ku&x509.KeyUsageDigitalSignature != 0 {
		info.KeyUsage = append(info.KeyUsage, "DigitalSignature")
	}
	if ku&x509.KeyUsageContentCommitment != 0 {
		info.KeyUsage = append(info.KeyUsage, "ContentCommitment")
	}
	if ku&x509.KeyUsageKeyEncipherment != 0 {
		info.KeyUsage = append(info.KeyUsage, "KeyEncipherment")
	}
	if ku&x509.KeyUsageDataEncipherment != 0 {
		info.KeyUsage = append(info.KeyUsage, "DataEncipherment")
	}
	if ku&x509.KeyUsageKeyAgreement != 0 {
		info.KeyUsage = append(info.KeyUsage, "KeyAgreement")
	}
	if ku&x509.KeyUsageCertSign != 0 {
		info.KeyUsage = append(info.KeyUsage, "CertSign")
	}
	if ku&x509.KeyUsageCRLSign != 0 {
		info.KeyUsage = append(info.KeyUsage, "CRLSign")
	}
	if ku&x509.KeyUsageEncipherOnly != 0 {
		info.KeyUsage = append(info.KeyUsage, "EncipherOnly")
	}
	if ku&x509.KeyUsageDecipherOnly != 0 {
		info.KeyUsage = append(info.KeyUsage, "DecipherOnly")
	}

	for _, ip := range cert.IPAddresses {
		info.IPAddresses = append(info.IPAddresses, ip.String())
	}

	info.EmailAddress = cert.EmailAddresses

	info.SHA1 = fmt.Sprintf("%x", sha1.Sum(cert.Raw))
	info.SHA256 = fmt.Sprintf("%x", sha256.Sum256(cert.Raw))

	if info.Subject == "" && len(cert.Subject.Organization) > 0 {
		info.Subject = cert.Subject.Organization[0]
	}
	if info.Issuer == "" && len(cert.Issuer.Organization) > 0 {
		info.Issuer = cert.Issuer.Organization[0]
	}
	if info.Subject == "" {
		info.Subject = fmt.Sprintf("%x", cert.RawSubject)
	}

	return info
}

func extKeyUsageString(usage x509.ExtKeyUsage) string {
	switch usage {
	case x509.ExtKeyUsageAny:
		return "Any"
	case x509.ExtKeyUsageServerAuth:
		return "ServerAuth"
	case x509.ExtKeyUsageClientAuth:
		return "ClientAuth"
	case x509.ExtKeyUsageCodeSigning:
		return "CodeSigning"
	case x509.ExtKeyUsageEmailProtection:
		return "EmailProtection"
	case x509.ExtKeyUsageIPSECEndSystem:
		return "IPSEndSystem"
	case x509.ExtKeyUsageIPSECTunnel:
		return "IPSECTunnel"
	case x509.ExtKeyUsageIPSECUser:
		return "IPSECUser"
	case x509.ExtKeyUsageTimeStamping:
		return "TimeStamping"
	case x509.ExtKeyUsageOCSPSigning:
		return "OCSPSigning"
	default:
		return fmt.Sprintf("Unknown(%d)", usage)
	}
}

func keyUsageString(usage x509.KeyUsage) string {
	switch usage {
	case x509.KeyUsageDigitalSignature:
		return "DigitalSignature"
	case x509.KeyUsageContentCommitment:
		return "ContentCommitment"
	case x509.KeyUsageKeyEncipherment:
		return "KeyEncipherment"
	case x509.KeyUsageDataEncipherment:
		return "DataEncipherment"
	case x509.KeyUsageKeyAgreement:
		return "KeyAgreement"
	case x509.KeyUsageCertSign:
		return "CertSign"
	case x509.KeyUsageCRLSign:
		return "CRLSign"
	case x509.KeyUsageEncipherOnly:
		return "EncipherOnly"
	case x509.KeyUsageDecipherOnly:
		return "DecipherOnly"
	default:
		return fmt.Sprintf("Unknown(%d)", usage)
	}
}

func emitJSON(v interface{}) {
	data, _ := json.MarshalIndent(v, "", "  ")
	fmt.Println(string(data))
}
