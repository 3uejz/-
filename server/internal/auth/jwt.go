package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"time"
)

var (
	// ErrInvalidToken 表示令牌不可解析或签名不匹配。
	ErrInvalidToken = errors.New("invalid token")
	// ErrTokenExpired 表示访问令牌已过期。
	ErrTokenExpired = errors.New("token expired")
)

type accessClaims struct {
	Sub  string `json:"sub"`
	Role string `json:"role"`
	Typ  string `json:"typ"`
	Iat  int64  `json:"iat"`
	Exp  int64  `json:"exp"`
}

var jwtHeader = base64.RawURLEncoding.EncodeToString([]byte(`{"alg":"HS256","typ":"JWT"}`))

// SignAccess 以 HS256 签发访问令牌。
func SignAccess(secret string, accountID, role string, now time.Time, ttl time.Duration) (string, error) {
	claims := accessClaims{
		Sub:  accountID,
		Role: role,
		Typ:  "access",
		Iat:  now.Unix(),
		Exp:  now.Add(ttl).Unix(),
	}
	payload, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}
	signingInput := jwtHeader + "." + base64.RawURLEncoding.EncodeToString(payload)
	sig := signHS256(secret, signingInput)
	return signingInput + "." + sig, nil
}

// ParseAccess 校验签名与过期时间并返回声明。
func ParseAccess(secret, token string, now time.Time) (accessClaims, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return accessClaims{}, ErrInvalidToken
	}
	signingInput := parts[0] + "." + parts[1]
	want := signHS256(secret, signingInput)
	if !hmac.Equal([]byte(want), []byte(parts[2])) {
		return accessClaims{}, ErrInvalidToken
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return accessClaims{}, ErrInvalidToken
	}
	var claims accessClaims
	if err := json.Unmarshal(payload, &claims); err != nil {
		return accessClaims{}, ErrInvalidToken
	}
	if claims.Typ != "access" || claims.Sub == "" {
		return accessClaims{}, ErrInvalidToken
	}
	if now.Unix() >= claims.Exp {
		return accessClaims{}, ErrTokenExpired
	}
	return claims, nil
}

func signHS256(secret, input string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(input))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}
