package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"reflect"
	"strings"
	"sync"
	"testing"
)

const testToken = "0123456789abcdef0123456789abcdef"

func call(h http.Handler, method, title, token, body string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, "/api/note?title="+url.QueryEscape(title), strings.NewReader(body))
	r.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func handler(t *testing.T) (http.Handler, string) {
	t.Helper()
	dir := t.TempDir()
	h, err := newHandler(dir, testToken)
	if err != nil {
		t.Fatal(err)
	}
	return h, dir
}

func TestPlaintextRoundTrip(t *testing.T) {
	h, dir := handler(t)
	if w := call(h, "GET", "客户A", testToken, ""); w.Code != 404 {
		t.Fatalf("missing: %d", w.Code)
	}
	content := "服务器：1.2.3.4\n域名：example.com\n<script>纯文本</script>\n"
	w := call(h, "PUT", "客户A", testToken, content)
	if w.Code != 204 {
		t.Fatalf("save: %d %s", w.Code, w.Body)
	}
	h, err := newHandler(dir, testToken)
	if err != nil {
		t.Fatal(err)
	}
	w = call(h, "GET", "客户A", testToken, "")
	if w.Code != 200 || w.Body.String() != content {
		t.Fatalf("read: %d %s", w.Code, w.Body)
	}
	if w.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("notes must not be cached")
	}
	files, _ := os.ReadDir(dir)
	if len(files) != 1 || files[0].IsDir() || files[0].Name() != "客户A.txt" {
		t.Fatalf("expected group-named txt file: %v", files)
	}
	info, _ := files[0].Info()
	if info.Mode().Perm() != 0600 {
		t.Fatalf("permissions: %v", info.Mode())
	}
	data, err := os.ReadFile(dir + "/客户A.txt")
	if err != nil || string(data) != content {
		t.Fatal("file must be readable plaintext")
	}
	if err := os.WriteFile(dir+"/客户A.txt", []byte("直接修改文件"), 0600); err != nil {
		t.Fatal(err)
	}
	if w := call(h, "GET", "客户A", testToken, ""); w.Body.String() != "直接修改文件" {
		t.Fatal("external edit not visible")
	}
	if w := call(h, "PUT", "客户A", testToken, ""); w.Code != 204 {
		t.Fatal("empty save failed")
	}
	if w := call(h, "GET", "客户A", testToken, ""); w.Code != 200 || w.Body.Len() != 0 {
		t.Fatal("empty note should exist")
	}
}

func TestRejectInvalidRequests(t *testing.T) {
	h, _ := handler(t)
	for _, tc := range []struct {
		name, method, title, token, body string
		status                           int
	}{
		{"no token", "GET", "A", "", "", 401},
		{"wrong token read", "GET", "A", "wrong", "", 401},
		{"wrong token write", "PUT", "A", "wrong", "oops", 401},
		{"no title", "GET", "", testToken, "", 400},
		{"blank title", "GET", "  ", testToken, "", 400},
		{"long title", "GET", strings.Repeat("x", 241), testToken, "", 400},
		{"invalid text", "PUT", "A", testToken, string([]byte{0xff}), 400},
		{"oversized", "PUT", "A", testToken, strings.Repeat("x", 300000), 413},
		{"delete", "DELETE", "A", testToken, "", 405},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if w := call(h, tc.method, tc.title, tc.token, tc.body); w.Code != tc.status {
				t.Fatalf("got %d want %d: %s", w.Code, tc.status, w.Body)
			}
		})
	}
	if _, err := newHandler(t.TempDir(), ""); err == nil {
		t.Fatal("empty token must disable startup")
	}
}

func TestExactTitlesAndSafeFiles(t *testing.T) {
	h, dir := handler(t)
	for _, title := range []string{"A", "a", " A", "A  B", "A B", "../../outside", "中文/群名", "中文%2F群名"} {
		if w := call(h, "PUT", title, testToken, title); w.Code != 204 {
			t.Fatalf("save %q: %d", title, w.Code)
		}
		if w := call(h, "GET", title, testToken, ""); w.Code != 200 || w.Body.String() != title {
			t.Fatalf("wrong match: %q", title)
		}
	}
	files, _ := os.ReadDir(dir)
	if len(files) != 8 {
		t.Fatalf("files: %v", files)
	}
	for _, file := range files {
		if file.IsDir() {
			t.Fatal("group directory created")
		}
	}
	if _, err := os.Stat(dir + "/中文%2F群名.txt"); err != nil {
		t.Fatal("slash must be escaped")
	}
}

func TestAtomicWrites(t *testing.T) {
	h, dir := handler(t)
	call(h, "PUT", "A", testToken, strings.Repeat("a", 10000))
	var wg sync.WaitGroup
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			content := strings.Repeat(string(rune('a'+i)), 10000)
			if w := call(h, "PUT", "A", testToken, content); w.Code != 204 {
				t.Errorf("save %d", w.Code)
			}
			w := call(h, "GET", "A", testToken, "")
			got := w.Body.String()
			if w.Code != 200 || len(got) != 10000 || strings.Trim(got, got[:1]) != "" {
				t.Errorf("partial read")
			}
		}(i)
	}
	wg.Wait()
	files, _ := os.ReadDir(dir)
	if len(files) != 1 {
		t.Fatalf("temporary files leaked: %v", files)
	}
}

func TestListNotes(t *testing.T) {
	h, dir := handler(t)
	getList := func(method, token string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, "/api/notes", nil)
		r.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	if w := getList("GET", "wrong"); w.Code != 401 {
		t.Fatalf("unauthorized list: %d", w.Code)
	}
	w := getList("GET", testToken)
	if w.Code != 200 || strings.TrimSpace(w.Body.String()) != `{"titles":[]}` {
		t.Fatalf("empty list: %d %s", w.Code, w.Body)
	}
	for _, title := range []string{"客户A", "项目/生产", "项目%2F生产"} {
		if w := call(h, "PUT", title, testToken, "note"); w.Code != 204 {
			t.Fatalf("save: %d", w.Code)
		}
	}
	os.WriteFile(dir+"/手动新增.txt", []byte("text"), 0600)
	os.WriteFile(dir+"/.note-incomplete", []byte("partial"), 0600)
	os.WriteFile(dir+"/backup.bak", []byte("backup"), 0600)
	os.Mkdir(dir+"/directory.txt", 0700)
	os.Symlink(dir+"/客户A.txt", dir+"/symlink.txt")
	w = getList("GET", testToken)
	if w.Code != 200 {
		t.Fatalf("list: %d", w.Code)
	}
	var result struct {
		Titles []string `json:"titles"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	want := []string{"客户A", "手动新增", "项目%2F生产", "项目/生产"}
	if !reflect.DeepEqual(result.Titles, want) {
		t.Fatalf("titles: %v", result.Titles)
	}
	for _, title := range result.Titles {
		if w := call(h, "GET", title, testToken, ""); w.Code != 200 {
			t.Fatalf("listed title unreadable: %q", title)
		}
	}
	if w := getList("PUT", testToken); w.Code != 405 {
		t.Fatalf("list must be read-only: %d", w.Code)
	}
}
