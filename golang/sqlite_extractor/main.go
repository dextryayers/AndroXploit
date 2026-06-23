package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	_ "github.com/mattn/go-sqlite3"
)

type DatabaseInfo struct {
	Path       string      `json:"path"`
	Size       int64       `json:"size"`
	SizeHuman  string      `json:"size_human"`
	PageSize   int         `json:"page_size,omitempty"`
	PageCount  int         `json:"page_count,omitempty"`
	Encoding   string      `json:"encoding,omitempty"`
	Tables     []TableInfo `json:"tables"`
	Views      []string    `json:"views,omitempty"`
	Indexes    []string    `json:"indexes,omitempty"`
	Triggers   []string    `json:"triggers,omitempty"`
	HasWALMode bool        `json:"has_wal_mode"`
	Error      string      `json:"error,omitempty"`
}

type TableInfo struct {
	Name        string                   `json:"name"`
	Columns     []ColumnInfo             `json:"columns"`
	RowCount    int                      `json:"row_count"`
	DDL         string                   `json:"ddl,omitempty"`
	Sample      []map[string]interface{} `json:"sample_rows,omitempty"`
	BlobColumns []string                 `json:"blob_columns,omitempty"`
	BlobCount   int                      `json:"blob_count,omitempty"`
	Size        int64                    `json:"size_bytes,omitempty"`
}

type ColumnInfo struct {
	Name     string `json:"name"`
	Type     string `json:"type"`
	NotNull  bool   `json:"not_null"`
	PK       bool   `json:"primary_key"`
	Default  string `json:"default_value,omitempty"`
}

type ExtractResult struct {
	Databases []DatabaseInfo `json:"databases"`
	Total     int            `json:"total"`
	TotalSize int64          `json:"total_size_bytes"`
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	path := os.Args[1]
	deep := false
	walExtract := false
	blobExtract := false

	for _, arg := range os.Args[2:] {
		switch arg {
		case "--deep", "-d":
			deep = true
		case "--wal", "-w":
			walExtract = true
		case "--blobs", "-b":
			blobExtract = true
		}
	}

	result := &ExtractResult{}

	info, err := os.Stat(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	if info.IsDir() {
		filepath.Walk(path, func(p string, fi os.FileInfo, err error) error {
			if err != nil {
				return nil
			}
			if !fi.IsDir() {
				ext := strings.ToLower(filepath.Ext(p))
				if ext == ".db" || ext == ".sqlite" || ext == ".sqlite3" || isSQLiteDB(p) {
					db := analyzeDatabase(p, deep, blobExtract)
					result.Databases = append(result.Databases, db)
					result.TotalSize += db.Size
				}
			}
			return nil
		})
	} else {
		db := analyzeDatabase(path, deep, blobExtract)
		result.Databases = append(result.Databases, db)
		result.TotalSize += db.Size
	}

	result.Total = len(result.Databases)

	if walExtract {
		result = extractWALFiles(result)
	}

	emitJSON(result)
}

func usage() {
	fmt.Fprintf(os.Stderr, "Usage: %s <db_file|directory> [options]\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "Options:\n")
	fmt.Fprintf(os.Stderr, "  --deep, -d   Deep analysis with full table scanning\n")
	fmt.Fprintf(os.Stderr, "  --wal, -w    Extract WAL file content\n")
	fmt.Fprintf(os.Stderr, "  --blobs, -b  Extract blob column data\n")
	fmt.Fprintf(os.Stderr, "Examples:\n")
	fmt.Fprintf(os.Stderr, "  %s database.db\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "  %s /data/data/com.app/databases/ --deep\n", os.Args[0])
}

func isSQLiteDB(path string) bool {
	file, err := os.Open(path)
	if err != nil {
		return false
	}
	defer file.Close()

	header := make([]byte, 16)
	n, err := file.Read(header)
	if err != nil || n < 16 {
		return false
	}
	return string(header[:16]) == "SQLite format 3\x00"
}

func analyzeDatabase(path string, deep, extractBlobs bool) DatabaseInfo {
	dbInfo := DatabaseInfo{Path: path}

	stat, err := os.Stat(path)
	if err != nil {
		dbInfo.Error = err.Error()
		return dbInfo
	}
	dbInfo.Size = stat.Size()
	dbInfo.SizeHuman = formatBytes(stat.Size())

	db, err := sql.Open("sqlite3", fmt.Sprintf("file:%s?mode=ro", path))
	if err != nil {
		dbInfo.Error = fmt.Sprintf("cannot open: %v", err)
		return dbInfo
	}
	defer db.Close()

	db.QueryRow("PRAGMA page_size").Scan(&dbInfo.PageSize)
	db.QueryRow("PRAGMA page_count").Scan(&dbInfo.PageCount)
	db.QueryRow("PRAGMA encoding").Scan(&dbInfo.Encoding)

	var journalMode string
	db.QueryRow("PRAGMA journal_mode").Scan(&journalMode)
	dbInfo.HasWALMode = strings.EqualFold(journalMode, "wal")

	rows, err := db.Query("SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
	if err != nil {
		dbInfo.Error = err.Error()
		return dbInfo
	}
	defer rows.Close()

	for rows.Next() {
		var tableName, ddl string
		rows.Scan(&tableName, &ddl)
		table := analyzeTable(db, tableName, ddl, deep, extractBlobs)
		dbInfo.Tables = append(dbInfo.Tables, table)
	}
	rows.Close()

	viewRows, _ := db.Query("SELECT name FROM sqlite_master WHERE type='view' ORDER BY name")
	if viewRows != nil {
		defer viewRows.Close()
		for viewRows.Next() {
			var name string
			viewRows.Scan(&name)
			dbInfo.Views = append(dbInfo.Views, name)
		}
	}

	idxRows, _ := db.Query("SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%' ORDER BY name")
	if idxRows != nil {
		defer idxRows.Close()
		for idxRows.Next() {
			var name string
			idxRows.Scan(&name)
			dbInfo.Indexes = append(dbInfo.Indexes, name)
		}
	}

	triggerRows, _ := db.Query("SELECT name FROM sqlite_master WHERE type='trigger' ORDER BY name")
	if triggerRows != nil {
		defer triggerRows.Close()
		for triggerRows.Next() {
			var name string
			triggerRows.Scan(&name)
			dbInfo.Triggers = append(dbInfo.Triggers, name)
		}
	}

	return dbInfo
}

func analyzeTable(db *sql.DB, name, ddl string, deep, extractBlobs bool) TableInfo {
	table := TableInfo{Name: name, DDL: ddl}

	colRows, err := db.Query(fmt.Sprintf("PRAGMA table_info('%s')", name))
	if err != nil {
		return table
	}
	defer colRows.Close()

	for colRows.Next() {
		var cid int
		var colName, colType string
		var notNull, pk int
		var defaultVal, nullable interface{}
		colRows.Scan(&cid, &colName, &colType, &notNull, &defaultVal, &pk)

		col := ColumnInfo{
			Name:    colName,
			Type:    colType,
			NotNull: notNull == 1,
			PK:      pk == 1,
		}
		if defaultVal != nil {
			col.Default = fmt.Sprintf("%v", defaultVal)
		}
		table.Columns = append(table.Columns, col)

		if strings.Contains(strings.ToUpper(colType), "BLOB") {
			table.BlobColumns = append(table.BlobColumns, colName)
		}
	}
	colRows.Close()

	db.QueryRow(fmt.Sprintf("SELECT COUNT(*) FROM \"%s\"", name)).Scan(&table.RowCount)

	if deep && table.RowCount > 0 {
		var tblSize int64
		db.QueryRow(fmt.Sprintf("SELECT SUM(pgsize) FROM dbstat WHERE name='%s'", name)).Scan(&tblSize)
		table.Size = tblSize
	}

	if extractBlobs && len(table.BlobColumns) > 0 {
		for _, col := range table.BlobColumns {
			var cnt int
			db.QueryRow(fmt.Sprintf("SELECT COUNT(*) FROM \"%s\" WHERE \"%s\" IS NOT NULL AND length(\"%s\") > 0", name, col, col)).Scan(&cnt)
			table.BlobCount += cnt
		}
	}

	if table.RowCount > 0 && table.RowCount <= 200 {
		sampleRows, err := db.Query(fmt.Sprintf("SELECT * FROM \"%s\" LIMIT 5", name))
		if err == nil {
			defer sampleRows.Close()
			columns, err := sampleRows.Columns()
			if err == nil {
				for sampleRows.Next() {
					values := make([]interface{}, len(columns))
					valuePtrs := make([]interface{}, len(columns))
					for i := range columns {
						valuePtrs[i] = &values[i]
					}
					sampleRows.Scan(valuePtrs...)
					row := make(map[string]interface{})
					for i, col := range columns {
						val := values[i]
						if b, ok := val.([]byte); ok {
							if isPrintable(b) && len(b) < 1000 {
								row[col] = string(b)
							} else {
								row[col] = fmt.Sprintf("[blob:%d bytes]", len(b))
							}
						} else {
							row[col] = val
						}
					}
					table.Sample = append(table.Sample, row)
				}
			}
		}
	}

	return table
}

func extractWALFiles(result *ExtractResult) *ExtractResult {
	for i, db := range result.Databases {
		walPath := db.Path + "-wal"
		if _, err := os.Stat(walPath); err == nil {
			walInfo, _ := os.Stat(walPath)
			dbEntry := DatabaseInfo{
				Path:      walPath,
				Size:      walInfo.Size(),
				SizeHuman: formatBytes(walInfo.Size()),
				Error:     "WAL journal file (Write-Ahead Log)",
			}
			result.Databases = append(result.Databases, dbEntry)
			result.TotalSize += walInfo.Size()
		}
		result.Databases[i] = db
	}
	result.Total = len(result.Databases)
	return result
}

func isPrintable(b []byte) bool {
	if len(b) == 0 {
		return false
	}
	printable := 0
	for _, c := range b {
		if c >= 32 && c <= 126 || c == '\n' || c == '\r' || c == '\t' {
			printable++
		}
	}
	return float64(printable)/float64(len(b)) > 0.7
}

func formatBytes(size int64) string {
	units := []string{"B", "KB", "MB", "GB"}
	val := float64(size)
	for _, unit := range units {
		if val < 1024 {
			return fmt.Sprintf("%.2f %s", val, unit)
		}
		val /= 1024
	}
	return fmt.Sprintf("%.2f TB", val)
}

func emitJSON(v interface{}) {
	data, _ := json.MarshalIndent(v, "", "  ")
	fmt.Println(string(data))
}
