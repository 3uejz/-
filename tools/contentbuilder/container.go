package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
)

const packMagic = "LTPK"
const packVersion uint16 = 1

// ReservedRemovedKey 是差量包内承载删除列表的保留条目键（自包含，无需额外 sidecar）。
const ReservedRemovedKey = "__removed__"

// EncodePack 生成轻量二进制容器：magic|version|kind|category|entryCount|(id,payload)*。
func EncodePack(category, kind string, entries []entry) ([]byte, error) {
	var buf bytes.Buffer
	buf.WriteString(packMagic)
	_ = binary.Write(&buf, binary.LittleEndian, packVersion)
	writeShortString(&buf, kind)
	writeShortString(&buf, category)
	_ = binary.Write(&buf, binary.LittleEndian, uint32(len(entries)))
	sorted := make([]entry, len(entries))
	copy(sorted, entries)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].Key < sorted[j].Key })
	for _, e := range sorted {
		payload, err := json.Marshal(e.Fields)
		if err != nil {
			return nil, err
		}
		writeShortString(&buf, e.Key)
		_ = binary.Write(&buf, binary.LittleEndian, uint32(len(payload)))
		buf.Write(payload)
	}
	return buf.Bytes(), nil
}

// DecodePack 解析二进制容器。
func DecodePack(data []byte) (category string, kind string, entries map[string]map[string]any, err error) {
	if len(data) < 4 || string(data[:4]) != packMagic {
		return "", "", nil, fmt.Errorf("非法的内容包 magic")
	}
	r := bytes.NewReader(data[4:])
	var version uint16
	if err = binary.Read(r, binary.LittleEndian, &version); err != nil {
		return "", "", nil, err
	}
	if version != packVersion {
		return "", "", nil, fmt.Errorf("不支持的内容包版本 %d", version)
	}
	if kind, err = readShortString(r); err != nil {
		return "", "", nil, err
	}
	if category, err = readShortString(r); err != nil {
		return "", "", nil, err
	}
	var count uint32
	if err = binary.Read(r, binary.LittleEndian, &count); err != nil {
		return "", "", nil, err
	}
	entries = map[string]map[string]any{}
	for i := uint32(0); i < count; i++ {
		key, e := readShortString(r)
		if e != nil {
			return "", "", nil, e
		}
		var plen uint32
		if e := binary.Read(r, binary.LittleEndian, &plen); e != nil {
			return "", "", nil, e
		}
		payload := make([]byte, plen)
		if _, e := r.Read(payload); e != nil {
			return "", "", nil, e
		}
		var fields map[string]any
		if e := json.Unmarshal(payload, &fields); e != nil {
			return "", "", nil, e
		}
		entries[key] = normalizeJSON(fields)
	}
	return category, kind, entries, nil
}

func writeShortString(buf *bytes.Buffer, s string) {
	_ = binary.Write(buf, binary.LittleEndian, uint16(len(s)))
	buf.WriteString(s)
}

func readShortString(r *bytes.Reader) (string, error) {
	var n uint16
	if err := binary.Read(r, binary.LittleEndian, &n); err != nil {
		return "", err
	}
	b := make([]byte, n)
	if _, err := r.Read(b); err != nil {
		return "", err
	}
	return string(b), nil
}

// sha256Hex 返回 sha256:<hex>。
func sha256Hex(data []byte) string {
	sum := sha256.Sum256(data)
	return "sha256:" + hex.EncodeToString(sum[:])
}

// writeFile 原子写入并返回字节数。
func writeFile(path string, data []byte) (int, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return 0, err
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		return 0, err
	}
	return len(data), nil
}
