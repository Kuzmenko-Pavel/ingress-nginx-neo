// SPDX-License-Identifier: Apache-2.0

package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

const html = "text/html"

func TestErrorHandler(t *testing.T) {
	handler := errorHandler("www", html)

	tests := []struct {
		name   string
		code   string
		format string
		status int
		file   string
	}{
		{name: "default format and code", status: http.StatusNotFound, file: "www/404.html"},
		{name: "html page of the code", code: "404", format: html, status: http.StatusNotFound, file: "www/404.html"},
		{name: "html page of the code class", code: "503", format: html, status: http.StatusServiceUnavailable, file: "www/5xx.html"},
		{name: "html page of another class", code: "418", format: html, status: http.StatusTeapot, file: "www/4xx.html"},
		{name: "json page", code: "404", format: "application/json", status: http.StatusNotFound, file: "www/404.json"},
		{name: "first of several formats", code: "503", format: "application/json,text/html", status: http.StatusServiceUnavailable, file: "www/5xx.json"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
			if tt.code != "" {
				req.Header.Set(CodeHeader, tt.code)
			}
			if tt.format != "" {
				req.Header.Set(FormatHeader, tt.format)
			}
			rec := httptest.NewRecorder()

			handler(rec, req)

			if rec.Code != tt.status {
				t.Errorf("status %d, want %d", rec.Code, tt.status)
			}
			want, err := os.ReadFile(tt.file)
			if err != nil {
				t.Fatal(err)
			}
			if got := rec.Body.String(); got != string(want) {
				t.Errorf("body %q, want the content of %s %q", got, tt.file, want)
			}
		})
	}
}
