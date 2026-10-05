// Package id 生成符合 shared/schemas/common.schema.json 的 UUIDv7（时间有序）。
package id

import (
	"crypto/rand"
	"encoding/hex"
	"time"
)

// NewUUIDv7 生成一个 RFC 9562 UUIDv7：48 位毫秒时间戳 + 版本/变体位 + 随机位。
// 返回 36 字符小写带连字符格式，形如 018f...-....-7...-....-............。
func NewUUIDv7() string {
	return UUIDv7At(time.Now())
}

// UUIDv7At 以指定时间（毫秒精度）为前缀生成 UUIDv7，便于测试与确定性。
func UUIDv7At(t time.Time) string {
	var b [16]byte
	ms := uint64(t.UnixMilli())
	b[0] = byte(ms >> 40)
	b[1] = byte(ms >> 32)
	b[2] = byte(ms >> 24)
	b[3] = byte(ms >> 16)
	b[4] = byte(ms >> 8)
	b[5] = byte(ms)
	if _, err := rand.Read(b[6:]); err != nil {
		// crypto/rand 失败极罕见；用时间纳秒作退化随机源，保证不 panic。
		n := uint64(t.UnixNano())
		for i := 6; i < 16; i++ {
			b[i] = byte(n >> (uint(i-6) * 8))
		}
	}
	b[6] = (b[6] & 0x0f) | 0x70 // version 7
	b[8] = (b[8] & 0x3f) | 0x80 // RFC 4122 variant
	return format(b)
}

func format(b [16]byte) string {
	buf := make([]byte, 36)
	hex.Encode(buf[0:8], b[0:4])
	buf[8] = '-'
	hex.Encode(buf[9:13], b[4:6])
	buf[13] = '-'
	hex.Encode(buf[14:18], b[6:8])
	buf[18] = '-'
	hex.Encode(buf[19:23], b[8:10])
	buf[23] = '-'
	hex.Encode(buf[24:36], b[10:16])
	return string(buf)
}

// IsValid 校验字符串是否为合法的 v7 UUID（按 common.schema.json 的 pattern）。
func IsValid(s string) bool {
	if len(s) != 36 {
		return false
	}
	if s[8] != '-' || s[13] != '-' || s[18] != '-' || s[23] != '-' {
		return false
	}
	if s[14] != '7' {
		return false
	}
	switch s[19] {
	case '8', '9', 'a', 'b':
	default:
		return false
	}
	for i, r := range s {
		if i == 8 || i == 13 || i == 18 || i == 23 {
			continue
		}
		isHex := (r >= '0' && r <= '9') || (r >= 'a' && r <= 'f')
		if !isHex {
			return false
		}
	}
	return true
}
