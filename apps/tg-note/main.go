package main

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

const maxFileBytes = 256 * 1024

func newHandler(dir, token string) (http.Handler, error) {
	if len(token) < 32 || strings.TrimSpace(token) != token {
		return nil, errors.New("TG_NOTE_TOKEN must contain at least 32 characters and no surrounding whitespace")
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	wanted := sha256.Sum256([]byte("Bearer " + token))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		actual := sha256.Sum256([]byte(r.Header.Get("Authorization")))
		if subtle.ConstantTimeCompare(actual[:], wanted[:]) != 1 {
			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		if r.URL.Path == "/api/notes" {
			if r.Method != http.MethodGet {
				w.Header().Set("Allow", "GET")
				http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
				return
			}
			titles, err := listNotes(dir)
			if err != nil {
				http.Error(w, "list failed", 500)
				return
			}
			w.Header().Set("Content-Type", "application/json; charset=utf-8")
			_ = json.NewEncoder(w).Encode(struct {
				Titles []string `json:"titles"`
			}{titles})
			return
		}
		if r.URL.Path != "/api/note" {
			http.NotFound(w, r)
			return
		}
		titles := r.URL.Query()["title"]
		if len(titles) != 1 {
			http.Error(w, "exactly one title is required", http.StatusBadRequest)
			return
		}
		name, err := noteFilename(titles[0])
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		filename := filepath.Join(dir, name)
		switch r.Method {
		case http.MethodGet:
			data, err := readNote(filename)
			if errors.Is(err, os.ErrNotExist) {
				http.NotFound(w, r)
				return
			}
			if err != nil {
				http.Error(w, "read failed", 500)
				return
			}
			w.Header().Set("Content-Type", "text/plain; charset=utf-8")
			_, _ = w.Write(data)
		case http.MethodPut:
			data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxFileBytes))
			if err != nil {
				var tooLarge *http.MaxBytesError
				if errors.As(err, &tooLarge) {
					http.Error(w, "note too large", 413)
				} else {
					http.Error(w, "invalid body", 400)
				}
				return
			}
			if !utf8.Valid(data) {
				http.Error(w, "note must be UTF-8", 400)
				return
			}
			if err := writeAtomic(dir, filename, data); err != nil {
				http.Error(w, "save failed", 500)
				return
			}
			w.WriteHeader(http.StatusNoContent)
		default:
			w.Header().Set("Allow", "GET, PUT")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	}), nil
}

func listNotes(dir string) ([]string, error) {
	files, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	titles := make([]string, 0, len(files))
	for _, file := range files {
		if !file.Type().IsRegular() || !strings.HasSuffix(file.Name(), ".txt") {
			continue
		}
		title, err := url.PathUnescape(strings.TrimSuffix(file.Name(), ".txt"))
		if err != nil {
			continue
		}
		name, err := noteFilename(title)
		if err != nil || name != file.Name() {
			continue
		}
		titles = append(titles, title)
	}
	sort.Strings(titles)
	return titles, nil
}

// Preserve readable group names, escaping path separators, percent and controls.
// Escaping percent makes titles containing a literal "%2F" distinct from "/".
func noteFilename(title string) (string, error) {
	if !utf8.ValidString(title) || strings.TrimSpace(title) == "" {
		return "", errors.New("title is required")
	}
	var name strings.Builder
	for _, ch := range title {
		if ch == '/' || ch == '\\' || ch == '%' || ch < 32 || ch == 127 {
			fmt.Fprintf(&name, "%%%02X", ch)
		} else {
			name.WriteRune(ch)
		}
	}
	if name.Len() > 240 {
		return "", errors.New("title filename exceeds 240 UTF-8 bytes")
	}
	return name.String() + ".txt", nil
}

func readNote(filename string) ([]byte, error) {
	f, err := os.Open(filename)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, maxFileBytes+1))
	if err != nil {
		return nil, err
	}
	if len(data) > maxFileBytes || !utf8.Valid(data) {
		return nil, errors.New("invalid note file")
	}
	return data, nil
}

func writeAtomic(dir, filename string, data []byte) error {
	f, err := os.CreateTemp(dir, ".note-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	defer f.Close()
	if _, err := f.Write(data); err != nil {
		return err
	}
	if err := f.Sync(); err != nil {
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	if err := os.Rename(f.Name(), filename); err != nil {
		return err
	}
	directory, err := os.Open(dir)
	if err != nil {
		return err
	}
	defer directory.Close()
	return directory.Sync()
}

func env(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

func main() {
	handler, err := newHandler(env("TG_NOTE_DIR", "data"), os.Getenv("TG_NOTE_TOKEN"))
	if err != nil {
		log.Fatal(err)
	}
	server := &http.Server{
		Addr: env("TG_NOTE_ADDR", "127.0.0.1:8790"), Handler: handler,
		ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second,
		WriteTimeout: 15 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16 * 1024,
	}
	cert, key := os.Getenv("TG_NOTE_TLS_CERT"), os.Getenv("TG_NOTE_TLS_KEY")
	if (cert == "") != (key == "") {
		log.Fatal("configure both TG_NOTE_TLS_CERT and TG_NOTE_TLS_KEY")
	}
	log.Printf("tg-note listening on %s", server.Addr)
	if cert != "" {
		err = server.ListenAndServeTLS(cert, key)
	} else {
		err = server.ListenAndServe()
	}
	if err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}
