package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

type Permission struct {
	Name        string `json:"name"`
	RiskLevel   string `json:"risk_level"`
	Description string `json:"description"`
	Score       int    `json:"score"`
	Category    string `json:"category,omitempty"`
}

type PermissionResult struct {
	Package     string       `json:"package"`
	Permissions []Permission `json:"permissions"`
	TotalScore  int          `json:"total_score"`
	MaxScore    int          `json:"max_score"`
	RiskLevel   string       `json:"risk_level"`
	Counts      Counts       `json:"counts"`
}

type Counts struct {
	Critical int `json:"critical"`
	High     int `json:"high"`
	Medium   int `json:"medium"`
	Low      int `json:"low"`
	Normal   int `json:"normal"`
	Unknown  int `json:"unknown"`
	Total    int `json:"total"`
}

type PermissionDBEntry struct {
	Risk     string
	Desc     string
	Score    int
	Category string
}

var permissionDB = map[string]PermissionDBEntry{
	"android.permission.READ_CONTACTS":                 {"high", "Read user contacts", 8, "personal"},
	"android.permission.WRITE_CONTACTS":                {"high", "Modify user contacts", 8, "personal"},
	"android.permission.READ_CALL_LOG":                 {"high", "Read call log", 8, "personal"},
	"android.permission.WRITE_CALL_LOG":                {"high", "Write call log", 7, "personal"},
	"android.permission.ACCESS_FINE_LOCATION":          {"critical", "Precise GPS location", 10, "location"},
	"android.permission.ACCESS_COARSE_LOCATION":        {"high", "Approximate location", 7, "location"},
	"android.permission.ACCESS_BACKGROUND_LOCATION":    {"critical", "Background location access", 10, "location"},
	"android.permission.CAMERA":                        {"critical", "Access camera", 9, "media"},
	"android.permission.RECORD_AUDIO":                  {"critical", "Record audio", 9, "media"},
	"android.permission.READ_SMS":                      {"critical", "Read SMS messages", 9, "sms"},
	"android.permission.SEND_SMS":                      {"high", "Send SMS messages", 8, "sms"},
	"android.permission.RECEIVE_SMS":                   {"high", "Receive SMS", 8, "sms"},
	"android.permission.RECEIVE_MMS":                   {"medium", "Receive MMS", 5, "sms"},
	"android.permission.READ_EXTERNAL_STORAGE":          {"medium", "Read external storage", 6, "storage"},
	"android.permission.READ_MEDIA_IMAGES":              {"medium", "Read media images", 6, "storage"},
	"android.permission.READ_MEDIA_VIDEO":               {"medium", "Read media video", 6, "storage"},
	"android.permission.READ_MEDIA_AUDIO":               {"medium", "Read media audio", 6, "storage"},
	"android.permission.WRITE_EXTERNAL_STORAGE":         {"high", "Write to external storage", 7, "storage"},
	"android.permission.INTERNET":                      {"medium", "Full internet access", 4, "network"},
	"android.permission.ACCESS_NETWORK_STATE":           {"low", "View network state", 1, "network"},
	"android.permission.ACCESS_WIFI_STATE":              {"low", "View WiFi state", 1, "network"},
	"android.permission.CHANGE_WIFI_STATE":              {"medium", "Change WiFi state", 4, "network"},
	"android.permission.CHANGE_NETWORK_STATE":           {"medium", "Change network state", 4, "network"},
	"android.permission.ACCESS_WIMAX_STATE":             {"low", "View WiMAX state", 1, "network"},
	"android.permission.CHANGE_WIMAX_STATE":             {"medium", "Change WiMAX state", 3, "network"},
	"android.permission.BLUETOOTH":                      {"low", "Bluetooth", 2, "connectivity"},
	"android.permission.BLUETOOTH_ADMIN":                {"medium", "Bluetooth admin", 3, "connectivity"},
	"android.permission.BLUETOOTH_CONNECT":              {"medium", "Bluetooth connect", 3, "connectivity"},
	"android.permission.BLUETOOTH_SCAN":                 {"medium", "Bluetooth scan", 4, "connectivity"},
	"android.permission.BLUETOOTH_ADVERTISE":            {"medium", "Bluetooth advertise", 3, "connectivity"},
	"android.permission.NFC":                            {"low", "NFC", 2, "connectivity"},
	"android.permission.NFC_TRANSACTION_EVENT":          {"medium", "NFC transaction events", 4, "connectivity"},
	"android.permission.READ_PHONE_STATE":               {"high", "Read phone state and identifiers", 8, "phone"},
	"android.permission.READ_PHONE_NUMBERS":             {"high", "Read phone numbers", 8, "phone"},
	"android.permission.READ_PRECISE_PHONE_STATE":       {"high", "Read precise phone state", 8, "phone"},
	"android.permission.CALL_PHONE":                     {"high", "Directly call phone numbers", 7, "phone"},
	"android.permission.PROCESS_OUTGOING_CALLS":         {"high", "Process outgoing calls", 8, "phone"},
	"android.permission.ANSWER_PHONE_CALLS":             {"high", "Answer phone calls", 7, "phone"},
	"android.permission.GET_ACCOUNTS":                   {"high", "Discover known accounts", 7, "accounts"},
	"android.permission.USE_CREDENTIALS":                {"high", "Use authentication credentials", 8, "accounts"},
	"android.permission.MANAGE_ACCOUNTS":                {"high", "Manage accounts", 8, "accounts"},
	"android.permission.AUTHENTICATE_ACCOUNTS":          {"medium", "Authenticate accounts", 6, "accounts"},
	"android.permission.USE_SIP":                        {"medium", "Use SIP/VoIP", 5, "phone"},
	"android.permission.BIND_ACCESSIBILITY_SERVICE":     {"critical", "Bind accessibility service", 10, "system"},
	"android.permission.SYSTEM_ALERT_WINDOW":            {"high", "Display system alerts", 8, "system"},
	"android.permission.REQUEST_INSTALL_PACKAGES":       {"medium", "Request package installs", 6, "system"},
	"android.permission.INSTALL_PACKAGES":               {"critical", "Install packages", 10, "system"},
	"android.permission.DELETE_PACKAGES":                {"critical", "Delete packages", 9, "system"},
	"android.permission.SET_ALARM":                      {"low", "Set alarm", 1, "normal"},
	"android.permission.VIBRATE":                        {"low", "Vibrate", 0, "normal"},
	"android.permission.WAKE_LOCK":                      {"low", "Wake lock", 1, "normal"},
	"android.permission.RECEIVE_BOOT_COMPLETED":         {"medium", "Run at boot", 5, "system"},
	"android.permission.USE_FINGERPRINT":                {"medium", "Use fingerprint", 5, "biometric"},
	"android.permission.USE_BIOMETRIC":                  {"medium", "Use biometric", 5, "biometric"},
	"android.permission.BODY_SENSORS":                   {"medium", "Access body sensors", 5, "sensors"},
	"android.permission.ACTIVITY_RECOGNITION":           {"medium", "Activity recognition", 5, "sensors"},
	"android.permission.FOREGROUND_SERVICE":             {"low", "Foreground service", 2, "system"},
	"android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK": {"low", "Foreground media", 2, "system"},
	"android.permission.FOREGROUND_SERVICE_LOCATION":    {"medium", "Foreground location", 5, "system"},
	"android.permission.POST_NOTIFICATIONS":             {"low", "Post notifications", 2, "normal"},
	"android.permission.MANAGE_EXTERNAL_STORAGE":        {"high", "Manage all files", 8, "storage"},
	"android.permission.QUERY_ALL_PACKAGES":             {"medium", "Query all packages", 5, "system"},
	"android.permission.SCHEDULE_EXACT_ALARM":           {"low", "Schedule exact alarm", 2, "normal"},
	"android.permission.ACCESS_MEDIA_LOCATION":          {"medium", "Access media location", 5, "media"},
	"android.permission.INTERACT_ACROSS_USERS_FULL":     {"critical", "Interact across users", 9, "system"},
	"android.permission.READ_SOCIAL_STREAM":             {"high", "Read social stream", 7, "personal"},
	"android.permission.WRITE_SOCIAL_STREAM":            {"high", "Write social stream", 7, "personal"},
	"android.permission.READ_PROFILE":                   {"high", "Read user profile", 7, "personal"},
	"android.permission.WRITE_PROFILE":                  {"high", "Write user profile", 7, "personal"},
	"android.permission.READ_HISTORY_BOOKMARKS":         {"medium", "Read browser history", 6, "personal"},
	"android.permission.WRITE_HISTORY_BOOKMARKS":        {"medium", "Write browser history", 5, "personal"},
	"android.permission.GET_TASKS":                      {"high", "Get running tasks", 7, "system"},
	"android.permission.REAL_GET_TASKS":                 {"high", "Get real tasks", 8, "system"},
	"android.permission.ACCESS_DOWNLOAD_MANAGER":        {"low", "Access download manager", 2, "system"},
	"android.permission.DOWNLOAD_WITHOUT_NOTIFICATION":  {"medium", "Download without notification", 4, "system"},
	"android.permission.EXPAND_STATUS_BAR":              {"low", "Expand status bar", 1, "normal"},
	"android.permission.DISABLE_KEYGUARD":               {"medium", "Disable keyguard", 5, "system"},
	"android.permission.KILL_BACKGROUND_PROCESSES":      {"high", "Kill background processes", 7, "system"},
	"android.permission.SUBSCRIBED_FEEDS_READ":          {"low", "Read subscribed feeds", 3, "personal"},
	"android.permission.SUBSCRIBED_FEEDS_WRITE":         {"low", "Write subscribed feeds", 3, "personal"},
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	input := os.Args[1]
	var perms []string

	if _, err := os.Stat(input); err == nil {
		data, err := os.ReadFile(input)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading file: %v\n", err)
			os.Exit(1)
		}
		for _, line := range strings.Split(string(data), "\n") {
			line = strings.TrimSpace(line)
			if line != "" && !strings.HasPrefix(line, "#") {
				perms = append(perms, line)
			}
		}
	} else {
		perms = strings.Split(input, ",")
	}

	for i, p := range perms {
		perms[i] = strings.TrimSpace(p)
	}

	pkg := ""
	if len(os.Args) > 2 {
		pkg = os.Args[2]
	}

	result := analyzePermissions(pkg, perms)
	emitJSON(result)
}

func usage() {
	fmt.Fprintf(os.Stderr, "Usage: %s <permissions.txt|comma,separated,list> [package_name]\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "  Analyze Android app permissions and calculate risk score.\n")
	fmt.Fprintf(os.Stderr, "  Input: file with one permission per line, or comma-separated string.\n")
	fmt.Fprintf(os.Stderr, "  Database: %d known permissions with risk scoring.\n", len(permissionDB))
	fmt.Fprintf(os.Stderr, "Example:\n")
	fmt.Fprintf(os.Stderr, "  %s android.permission.CAMERA,android.permission.INTERNET\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "  %s permissions.txt com.example.app\n", os.Args[0])
}

func analyzePermissions(pkg string, perms []string) *PermissionResult {
	result := &PermissionResult{}
	if pkg != "" {
		result.Package = pkg
	}
	counts := Counts{}
	knownCount := 0

	for _, p := range perms {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}

		if info, ok := permissionDB[p]; ok {
			perm := Permission{
				Name:        p,
				RiskLevel:   info.Risk,
				Description: info.Desc,
				Score:       info.Score,
				Category:    info.Category,
			}
			result.Permissions = append(result.Permissions, perm)
			result.TotalScore += info.Score
			result.MaxScore += info.Score
			knownCount++
			switch info.Risk {
			case "critical":
				counts.Critical++
			case "high":
				counts.High++
			case "medium":
				counts.Medium++
			case "low":
				counts.Low++
			default:
				counts.Normal++
			}
		} else {
			perm := Permission{
				Name:        p,
				RiskLevel:   "unknown",
				Description: "Unknown permission - check manually",
				Score:       3,
				Category:    "unknown",
			}
			parts := strings.Split(p, ".")
			if len(parts) >= 3 {
				prefix := strings.Join(parts[:3], ".")
				if strings.HasPrefix(p, "android.permission.") {
					perm.RiskLevel = "unknown"
					perm.Description = "Unknown Android permission"
				} else if strings.HasPrefix(p, "com.") || strings.HasPrefix(p, "org.") {
					perm.RiskLevel = "medium"
					perm.Description = fmt.Sprintf("Custom permission by %s", parts[1])
				}
				perm.Category = prefix
			}
			result.Permissions = append(result.Permissions, perm)
			result.TotalScore += perm.Score
			counts.Unknown++
		}
		counts.Total++
	}

	result.Counts = counts

	avgScore := 0
	if counts.Total > 0 {
		avgScore = result.TotalScore / counts.Total
	}

	switch {
	case counts.Critical >= 1 || avgScore >= 8:
		result.RiskLevel = "CRITICAL"
	case counts.High >= 2 || avgScore >= 6:
		result.RiskLevel = "HIGH"
	case counts.Medium >= 3 || avgScore >= 4:
		result.RiskLevel = "MEDIUM"
	case counts.Total == 0:
		result.RiskLevel = "NONE"
	default:
		result.RiskLevel = "LOW"
	}

	return result
}

func emitJSON(v interface{}) {
	data, _ := json.MarshalIndent(v, "", "  ")
	fmt.Println(string(data))
}
