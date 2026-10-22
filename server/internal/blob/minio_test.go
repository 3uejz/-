package blob

import "testing"

func TestNormalizeEndpoint(t *testing.T) {
	cases := []struct {
		in     string
		ssl    bool
		want   string
		secure bool
	}{
		{"minio:9000", false, "minio:9000", false},
		{"https://account.r2.cloudflarestorage.com/", false, "account.r2.cloudflarestorage.com", true},
		{"http://minio:9000", true, "minio:9000", false},
		{"s3.example.com", true, "s3.example.com", true},
	}
	for _, c := range cases {
		got, secure := normalizeEndpoint(c.in, c.ssl)
		if got != c.want || secure != c.secure {
			t.Errorf("normalizeEndpoint(%q, %v) = (%q, %v), want (%q, %v)", c.in, c.ssl, got, secure, c.want, c.secure)
		}
	}
}
