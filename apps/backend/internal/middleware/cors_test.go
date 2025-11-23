package middleware

import "testing"

func TestParseWildcardOrigin(t *testing.T) {
	tests := []struct {
		name    string
		pattern string
		wantNil bool
		scheme  string
		suffix  string
	}{
		{
			name:    "valid https wildcard",
			pattern: "https://*.example.com",
			wantNil: false,
			scheme:  "https://",
			suffix:  ".example.com",
		},
		{
			name:    "valid http wildcard",
			pattern: "http://*.localhost.dev",
			wantNil: false,
			scheme:  "http://",
			suffix:  ".localhost.dev",
		},
		{
			name:    "valid cloudflare pages pattern",
			pattern: "https://*.trendy-app.pages.dev",
			wantNil: false,
			scheme:  "https://",
			suffix:  ".trendy-app.pages.dev",
		},
		{
			name:    "invalid - no scheme",
			pattern: "*.example.com",
			wantNil: true,
		},
		{
			name:    "invalid - bare wildcard",
			pattern: "*",
			wantNil: true,
		},
		{
			name:    "invalid - wildcard at end",
			pattern: "https://example.*",
			wantNil: true,
		},
		{
			name:    "invalid - multiple wildcards",
			pattern: "https://*.*.example.com",
			wantNil: true,
		},
		{
			name:    "invalid - no dot after wildcard",
			pattern: "https://*example.com",
			wantNil: true,
		},
		{
			name:    "invalid - single part domain",
			pattern: "https://*.com",
			wantNil: true,
		},
		{
			name:    "exact origin - not a wildcard",
			pattern: "https://example.com",
			wantNil: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseWildcardOrigin(tt.pattern)
			if tt.wantNil {
				if got != nil {
					t.Errorf("parseWildcardOrigin(%q) = %+v, want nil", tt.pattern, got)
				}
				return
			}
			if got == nil {
				t.Fatalf("parseWildcardOrigin(%q) = nil, want non-nil", tt.pattern)
			}
			if got.scheme != tt.scheme {
				t.Errorf("scheme = %q, want %q", got.scheme, tt.scheme)
			}
			if got.suffix != tt.suffix {
				t.Errorf("suffix = %q, want %q", got.suffix, tt.suffix)
			}
		})
	}
}

func TestWildcardOriginMatches(t *testing.T) {
	tests := []struct {
		name    string
		pattern string
		origin  string
		want    bool
	}{
		{
			name:    "simple subdomain match",
			pattern: "https://*.example.com",
			origin:  "https://app.example.com",
			want:    true,
		},
		{
			name:    "cloudflare pages deployment",
			pattern: "https://*.trendy-app.pages.dev",
			origin:  "https://abc123.trendy-app.pages.dev",
			want:    true,
		},
		{
			name:    "cloudflare pages with hash",
			pattern: "https://*.trendy-app.pages.dev",
			origin:  "https://a1b2c3d4.trendy-app.pages.dev",
			want:    true,
		},
		{
			name:    "wrong scheme",
			pattern: "https://*.example.com",
			origin:  "http://app.example.com",
			want:    false,
		},
		{
			name:    "wrong domain",
			pattern: "https://*.example.com",
			origin:  "https://app.other.com",
			want:    false,
		},
		{
			name:    "nested subdomain - should not match",
			pattern: "https://*.example.com",
			origin:  "https://a.b.example.com",
			want:    false,
		},
		{
			name:    "no subdomain - should not match",
			pattern: "https://*.example.com",
			origin:  "https://example.com",
			want:    false,
		},
		{
			name:    "partial match attack - should not match",
			pattern: "https://*.example.com",
			origin:  "https://evil-example.com",
			want:    false,
		},
		{
			name:    "suffix injection attack - should not match",
			pattern: "https://*.example.com",
			origin:  "https://app.example.com.evil.com",
			want:    false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			wildcard := parseWildcardOrigin(tt.pattern)
			if wildcard == nil {
				t.Fatalf("parseWildcardOrigin(%q) = nil", tt.pattern)
			}
			got := wildcard.matches(tt.origin)
			if got != tt.want {
				t.Errorf("wildcard.matches(%q) = %v, want %v", tt.origin, got, tt.want)
			}
		})
	}
}
