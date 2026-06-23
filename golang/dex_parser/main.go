package main

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

type DexHeader struct {
	Magic         string `json:"magic"`
	Checksum      uint32 `json:"checksum"`
	Signature     string `json:"signature"`
	FileSize      uint32 `json:"file_size"`
	HeaderSize    uint32 `json:"header_size"`
	EndianTag     uint32 `json:"endian_tag"`
	LinkSize      uint32 `json:"link_size"`
	LinkOffset    uint32 `json:"link_offset"`
	MapOffset     uint32 `json:"map_offset"`
	StringIdsSize uint32 `json:"string_ids_size"`
	StringIdsOff  uint32 `json:"string_ids_off"`
	TypeIdsSize   uint32 `json:"type_ids_size"`
	TypeIdsOff    uint32 `json:"type_ids_off"`
	ProtoIdsSize  uint32 `json:"proto_ids_size"`
	ProtoIdsOff   uint32 `json:"proto_ids_off"`
	FieldIdsSize  uint32 `json:"field_ids_size"`
	FieldIdsOff   uint32 `json:"field_ids_off"`
	MethodIdsSize uint32 `json:"method_ids_size"`
	MethodIdsOff  uint32 `json:"method_ids_off"`
	ClassDefsSize uint32 `json:"class_defs_size"`
	ClassDefsOff  uint32 `json:"class_defs_off"`
	DataSize      uint32 `json:"data_size"`
	DataOffset    uint32 `json:"data_offset"`
	DexVersion    string `json:"dex_version"`
}

type DexInfo struct {
	Header         DexHeader       `json:"header"`
	Classes        []ClassDef      `json:"classes"`
	Methods        []MethodInfo    `json:"methods"`
	Fields         []FieldInfo     `json:"fields"`
	Protos         []ProtoInfo     `json:"protos"`
	Strings        []string        `json:"strings"`
	StringCount    int             `json:"string_count"`
	MethodCount    int             `json:"method_count"`
	ClassCount     int             `json:"class_count"`
	FieldCount     int             `json:"field_count"`
	FileSize       int64           `json:"file_size"`
	EncodedMethods []EncodedMethod `json:"encoded_methods,omitempty"`
	MapItems       []MapItem       `json:"map_items,omitempty"`
}

type ClassDef struct {
	ClassType      string `json:"class_type"`
	AccessFlags    int    `json:"access_flags"`
	SuperClass     string `json:"super_class,omitempty"`
	InterfaceCount int    `json:"interface_count"`
}

type MethodInfo struct {
	Name       string `json:"name"`
	ClassIdx   int    `json:"class_idx"`
	ProtoIdx   int    `json:"proto_idx"`
	Descriptor string `json:"descriptor,omitempty"`
}

type FieldInfo struct {
	Name     string `json:"name"`
	ClassIdx int    `json:"class_idx"`
	TypeIdx  int    `json:"type_idx"`
}

type ProtoInfo struct {
	Shorty         string   `json:"shorty"`
	ReturnType     string   `json:"return_type,omitempty"`
	ParameterTypes []string `json:"parameter_types,omitempty"`
}

type EncodedMethod struct {
	MethodIdx   uint32 `json:"method_idx"`
	AccessFlags uint32 `json:"access_flags"`
	CodeOffset  uint32 `json:"code_offset"`
	CodeSize    uint32 `json:"code_size,omitempty"`
	Name        string `json:"name,omitempty"`
}

type MapItem struct {
	Type     uint16 `json:"type"`
	TypeName string `json:"type_name"`
	Size     uint32 `json:"size"`
	Offset   uint32 `json:"offset"`
}

var mapTypeNames = map[uint16]string{
	0x0000: "kDexTypeHeaderItem",
	0x0001: "kDexTypeStringIdItem",
	0x0002: "kDexTypeTypeIdItem",
	0x0003: "kDexTypeProtoIdItem",
	0x0004: "kDexTypeFieldIdItem",
	0x0005: "kDexTypeMethodIdItem",
	0x0006: "kDexTypeClassDefItem",
	0x1000: "kDexTypeMapList",
	0x1001: "kDexTypeTypeList",
	0x1002: "kDexTypeAnnotationSetRefList",
	0x1003: "kDexTypeAnnotationSetItem",
	0x1004: "kDexTypeClassDataItem",
	0x1005: "kDexTypeCodeItem",
	0x1006: "kDexTypeStringDataItem",
	0x1007: "kDexTypeDebugInfoItem",
	0x1008: "kDexTypeAnnotationItem",
	0x1009: "kDexTypeEncodedArrayItem",
	0x100A: "kDexTypeAnnotationsDirectoryItem",
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: %s <dex_file|apk_file>\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "  Parses DEX files (or extracts from APK) and outputs JSON.\n")
		fmt.Fprintf(os.Stderr, "Examples:\n")
		fmt.Fprintf(os.Stderr, "  %s classes.dex\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "  %s target.apk\n", os.Args[0])
		os.Exit(1)
	}

	path := os.Args[1]
	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	var dexData []byte
	if len(data) > 4 && string(data[:4]) == "PK\x03\x04" {
		fmt.Fprintf(os.Stderr, "APK detected, extracting DEX...\n")
		dexData = extractDexFromZip(data)
		if dexData == nil {
			fmt.Fprintf(os.Stderr, "No DEX data found in APK\n")
			os.Exit(1)
		}
		fmt.Fprintf(os.Stderr, "DEX extracted: %d bytes\n", len(dexData))
	} else {
		dexData = data
	}

	if len(dexData) < 8 || !isValidDex(dexData[:8]) {
		fmt.Fprintf(os.Stderr, "Not a valid DEX file (magic: %x)\n", dexData[:8])
		os.Exit(1)
	}

	info := parseDex(dexData)
	info.FileSize = int64(len(dexData))

	emitJSON(info)
}

func isValidDex(magic []byte) bool {
	valid := []string{"dex\n035\x00", "dex\n037\x00", "dex\n038\x00", "dex\n039\x00"}
	for _, v := range valid {
		if string(magic) == v {
			return true
		}
	}
	return false
}

func extractDexFromZip(data []byte) []byte {
	for i := 0; i < len(data)-10; i++ {
		magic := string(data[i : i+8])
		if isValidDex([]byte(magic)) {
			end := i + int(binary.LittleEndian.Uint32(data[i+0x20:i+0x24]))
			if end > len(data) {
				end = len(data)
			}
			return data[i:end]
		}
	}
	return nil
}

func parseDex(data []byte) *DexInfo {
	info := &DexInfo{}

	info.Header.Magic = string(data[:8])
	info.Header.Checksum = binary.LittleEndian.Uint32(data[8:12])
	info.Header.Signature = fmt.Sprintf("%x", data[12:32])
	info.Header.FileSize = binary.LittleEndian.Uint32(data[0x20:0x24])
	info.Header.HeaderSize = binary.LittleEndian.Uint32(data[0x24:0x28])
	info.Header.EndianTag = binary.LittleEndian.Uint32(data[0x28:0x2C])
	info.Header.LinkSize = binary.LittleEndian.Uint32(data[0x2C:0x30])
	info.Header.LinkOffset = binary.LittleEndian.Uint32(data[0x30:0x34])
	info.Header.MapOffset = binary.LittleEndian.Uint32(data[0x34:0x38])
	info.Header.StringIdsSize = binary.LittleEndian.Uint32(data[0x38:0x3C])
	info.Header.StringIdsOff = binary.LittleEndian.Uint32(data[0x3C:0x40])
	info.Header.TypeIdsSize = binary.LittleEndian.Uint32(data[0x40:0x44])
	info.Header.TypeIdsOff = binary.LittleEndian.Uint32(data[0x44:0x48])
	info.Header.ProtoIdsSize = binary.LittleEndian.Uint32(data[0x48:0x4C])
	info.Header.ProtoIdsOff = binary.LittleEndian.Uint32(data[0x4C:0x50])
	info.Header.FieldIdsSize = binary.LittleEndian.Uint32(data[0x50:0x54])
	info.Header.FieldIdsOff = binary.LittleEndian.Uint32(data[0x54:0x58])
	info.Header.MethodIdsSize = binary.LittleEndian.Uint32(data[0x58:0x5C])
	info.Header.MethodIdsOff = binary.LittleEndian.Uint32(data[0x5C:0x60])
	info.Header.ClassDefsSize = binary.LittleEndian.Uint32(data[0x60:0x64])
	info.Header.ClassDefsOff = binary.LittleEndian.Uint32(data[0x64:0x68])
	info.Header.DataSize = binary.LittleEndian.Uint32(data[0x68:0x6C])
	info.Header.DataOffset = binary.LittleEndian.Uint32(data[0x6C:0x70])

	magic := string(data[:8])
	switch {
	case strings.HasPrefix(magic, "dex\n035"):
		info.Header.DexVersion = "035"
	case strings.HasPrefix(magic, "dex\n037"):
		info.Header.DexVersion = "037"
	case strings.HasPrefix(magic, "dex\n038"):
		info.Header.DexVersion = "038"
	case strings.HasPrefix(magic, "dex\n039"):
		info.Header.DexVersion = "039"
	}

	typeOff := info.Header.TypeIdsOff
	protoOff := info.Header.ProtoIdsOff
	fieldOff := info.Header.FieldIdsOff
	methodOff := info.Header.MethodIdsOff
	classOff := info.Header.ClassDefsOff

	typeNames := make([]string, info.Header.TypeIdsSize)
	for i := uint32(0); i < info.Header.TypeIdsSize && typeOff+4*(i+1) <= uint32(len(data)); i++ {
		descriptorOff := binary.LittleEndian.Uint32(data[typeOff+4*i:])
		typeNames[i] = readDexString(data, descriptorOff)
	}

	for i := uint32(0); i < info.Header.ProtoIdsSize && protoOff+12*(i+1) <= uint32(len(data)); i++ {
		shortyOff := binary.LittleEndian.Uint32(data[protoOff+12*i:])
		returnTypeOff := binary.LittleEndian.Uint32(data[protoOff+12*i+4:])
		paramOff := binary.LittleEndian.Uint32(data[protoOff+12*i+8:])

		shorty := readDexString(data, shortyOff)
		returnType := ""
		if returnTypeOff < uint32(len(typeNames)) {
			returnType = typeNames[returnTypeOff]
		}

		var paramTypes []string
		if paramOff > 0 && paramOff < uint32(len(data)) {
			paramCount := binary.LittleEndian.Uint32(data[paramOff:])
			for j := uint32(0); j < paramCount && paramOff+4+4*j+4 <= uint32(len(data)); j++ {
				typeIdx := binary.LittleEndian.Uint16(data[paramOff+4+4*j:])
				if int(typeIdx) < len(typeNames) {
					paramTypes = append(paramTypes, typeNames[typeIdx])
				}
			}
		}

		info.Protos = append(info.Protos, ProtoInfo{
			Shorty:         shorty,
			ReturnType:     returnType,
			ParameterTypes: paramTypes,
		})
	}

	for i := uint32(0); i < info.Header.FieldIdsSize && fieldOff+8*(i+1) <= uint32(len(data)); i++ {
		classIdx := binary.LittleEndian.Uint16(data[fieldOff+8*i:])
		typeIdx := binary.LittleEndian.Uint16(data[fieldOff+8*i+2:])
		nameOff := binary.LittleEndian.Uint32(data[fieldOff+8*i+4:])

		info.Fields = append(info.Fields, FieldInfo{
			Name:     readDexString(data, nameOff),
			ClassIdx: int(classIdx),
			TypeIdx:  int(typeIdx),
		})
	}
	info.FieldCount = len(info.Fields)

	var stringSet = make(map[string]bool)
	for i := uint32(0); i < info.Header.MethodIdsSize && methodOff+8*(i+1) <= uint32(len(data)); i++ {
		classIdx := binary.LittleEndian.Uint16(data[methodOff+8*i:])
		protoIdx := binary.LittleEndian.Uint16(data[methodOff+8*i+2:])
		nameOff := binary.LittleEndian.Uint32(data[methodOff+8*i+4:])
		name := readDexString(data, nameOff)

		if name != "" && !stringSet[name] {
			info.Strings = append(info.Strings, name)
			stringSet[name] = true
		}

		desc := ""
		if int(protoIdx) < len(info.Protos) {
			desc = info.Protos[protoIdx].Shorty
		}

		info.Methods = append(info.Methods, MethodInfo{
			Name:       name,
			ClassIdx:   int(classIdx),
			ProtoIdx:   int(protoIdx),
			Descriptor: desc,
		})
	}
	info.MethodCount = len(info.Methods)
	info.StringCount = len(info.Strings)

	for i := uint32(0); i < info.Header.ClassDefsSize && classOff+32*(i+1) <= uint32(len(data)); i++ {
		classIdx := binary.LittleEndian.Uint32(data[classOff+32*i:])
		accessFlags := int(binary.LittleEndian.Uint32(data[classOff+32*i+4:]))
		superIdx := binary.LittleEndian.Uint32(data[classOff+32*i+8:])
		ifaceOff := binary.LittleEndian.Uint32(data[classOff+32*i+12:])

		className := ""
		if classIdx < uint32(len(typeNames)) {
			className = typeNames[classIdx]
		}
		superClass := ""
		if superIdx < uint32(len(typeNames)) {
			superClass = typeNames[superIdx]
		}

		ifaceCount := 0
		if ifaceOff > 0 && ifaceOff < uint32(len(data)) {
			ifaceCount = int(binary.LittleEndian.Uint32(data[ifaceOff:]))
		}

		info.Classes = append(info.Classes, ClassDef{
			ClassType:      className,
			AccessFlags:    accessFlags,
			SuperClass:     superClass,
			InterfaceCount: ifaceCount,
		})
	}
	info.ClassCount = len(info.Classes)

	if info.Header.MapOffset > 0 && info.Header.MapOffset < uint32(len(data)) {
		info.MapItems = parseMapItems(data, info.Header.MapOffset)
	}

	parseEncodedMethods(data, info)

	return info
}

func parseMapItems(data []byte, offset uint32) []MapItem {
	if offset+4 > uint32(len(data)) {
		return nil
	}
	count := binary.LittleEndian.Uint32(data[offset:])
	var items []MapItem
	for i := uint32(0); i < count && offset+4+12*i+12 <= uint32(len(data)); i++ {
		itemOffset := offset + 4 + 12*i
		typ := binary.LittleEndian.Uint16(data[itemOffset:])
		_ = binary.LittleEndian.Uint16(data[itemOffset+2:])
		size := binary.LittleEndian.Uint32(data[itemOffset+4:])
		itemOff := binary.LittleEndian.Uint32(data[itemOffset+8:])
		typeName := mapTypeNames[typ]
		if typeName == "" {
			typeName = fmt.Sprintf("0x%04x", typ)
		}
		items = append(items, MapItem{
			Type:     typ,
			TypeName: typeName,
			Size:     size,
			Offset:   itemOff,
		})
	}
	return items
}

func parseEncodedMethods(data []byte, info *DexInfo) {
	classOff := info.Header.ClassDefsOff
	for i := uint32(0); i < info.Header.ClassDefsSize; i++ {
		base := classOff + 32*i
		if base+28 > uint32(len(data)) {
			continue
		}
		classDataOff := binary.LittleEndian.Uint32(data[base+28:])
		if classDataOff == 0 || classDataOff >= uint32(len(data)) {
			continue
		}

		_ = readULEB128(data, &classDataOff)
		_ = readULEB128(data, &classDataOff)
		directMethods := readULEB128(data, &classDataOff)
		virtualMethods := readULEB128(data, &classDataOff)

		totalMethods := directMethods + virtualMethods
		for j := uint32(0); j < totalMethods && classDataOff < uint32(len(data)); j++ {
			methodIdxDiff := readULEB128(data, &classDataOff)
			accessFlags := readULEB128(data, &classDataOff)
			codeOff := readULEB128(data, &classDataOff)

			methodName := ""
			if methodIdxDiff < uint32(len(info.Methods)) {
				methodName = info.Methods[methodIdxDiff].Name
			}

			codeSize := uint32(0)
			if codeOff > 0 && codeOff+12 <= uint32(len(data)) {
				codeSize = binary.LittleEndian.Uint32(data[codeOff+4:])
			}

			info.EncodedMethods = append(info.EncodedMethods, EncodedMethod{
				MethodIdx:   methodIdxDiff,
				AccessFlags: accessFlags,
				CodeOffset:  codeOff,
				CodeSize:    codeSize,
				Name:        methodName,
			})
		}
	}
}

func readULEB128(data []byte, offset *uint32) uint32 {
	var result uint32
	var shift uint32
	for {
		if *offset >= uint32(len(data)) {
			break
		}
		b := uint32(data[*offset])
		*offset++
		result |= (b & 0x7f) << shift
		if (b & 0x80) == 0 {
			break
		}
		shift += 7
	}
	return result
}

func readDexString(data []byte, offset uint32) string {
	if offset >= uint32(len(data)) {
		return ""
	}
	ptr := offset
	for data[ptr]&0x80 != 0 {
		ptr++
		if ptr >= uint32(len(data)) {
			return ""
		}
	}
	ptr++

	var strLen uint32
	end := uint32(len(data))
	for i := ptr; i < end; i++ {
		if data[i] == 0 {
			strLen = i - ptr
			break
		}
	}
	if strLen > 2000 {
		strLen = 2000
	}
	if ptr+strLen > uint32(len(data)) {
		return ""
	}
	result := string(data[ptr : ptr+strLen])
	result = strings.ReplaceAll(result, "\x00", "")
	result = strings.ReplaceAll(result, "\n", "\\n")
	result = strings.ReplaceAll(result, "\r", "\\r")
	result = strings.ReplaceAll(result, "\t", "\\t")
	return result
}

func emitJSON(v interface{}) {
	data, _ := json.MarshalIndent(v, "", "  ")
	fmt.Println(string(data))
}
