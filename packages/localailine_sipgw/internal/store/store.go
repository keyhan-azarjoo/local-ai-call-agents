// Package store keeps the lines in one encrypted file, so a desktop restart keeps them.
//
// The file is AES-256-GCM: "LLGW1" | 12-byte nonce | sealed JSON. The key (32 bytes, given as
// base64 or hex) comes from the environment, never from the file next to it. The file is
// written to a temporary name and renamed, so a crash never leaves half a file.
package store

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/keyhan-azarjoo/local-ai-call-agents/packages/localailine_sipgw/internal/account"
)

var magic = []byte("LLGW1")

// ErrWrongKey means the file exists but this key can't open it (or it was tampered with).
var ErrWrongKey = errors.New("store: the file can't be opened with this key (wrong key, or the file was changed)")

// record is an account as stored: unlike the API form it keeps the token.
type record struct {
	account.Account
	Token string `json:"token"`
}

// Store reads and writes one file.
type Store struct {
	path string
	aead cipher.AEAD
	mu   sync.Mutex
}

// ParseKey reads a 32-byte key written as base64 (std or URL) or hex.
func ParseKey(s string) ([]byte, error) {
	s = strings.TrimSpace(s)
	for _, dec := range []func(string) ([]byte, error){
		hex.DecodeString,
		base64.StdEncoding.DecodeString,
		base64.RawStdEncoding.DecodeString,
		base64.URLEncoding.DecodeString,
		base64.RawURLEncoding.DecodeString,
	} {
		if k, err := dec(s); err == nil && len(k) == 32 {
			return k, nil
		}
	}
	return nil, errors.New("store key must be 32 bytes, written as 64 hex characters or base64 (e.g. `openssl rand -base64 32`)")
}

// New opens a store at path with a 32-byte key.
func New(path string, key []byte) (*Store, error) {
	if len(key) != 32 {
		return nil, errors.New("store key must be 32 bytes")
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	return &Store{path: path, aead: aead}, nil
}

// Load returns the saved lines; none (and no error) if the file doesn't exist yet.
func (s *Store) Load() ([]account.Account, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	data, err := os.ReadFile(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	ns := s.aead.NonceSize()
	if len(data) < len(magic)+ns || !bytes.Equal(data[:len(magic)], magic) {
		return nil, errors.New("store: not a sipgw accounts file")
	}
	plain, err := s.aead.Open(nil, data[len(magic):len(magic)+ns], data[len(magic)+ns:], magic)
	if err != nil {
		return nil, ErrWrongKey
	}
	var recs []record
	if err := json.Unmarshal(plain, &recs); err != nil {
		return nil, fmt.Errorf("store: %w", err)
	}
	out := make([]account.Account, 0, len(recs))
	for _, r := range recs {
		a := r.Account
		a.Token = r.Token
		out = append(out, a)
	}
	return out, nil
}

// Save replaces the file with these lines.
func (s *Store) Save(accts []account.Account) error {
	recs := make([]record, 0, len(accts))
	for _, a := range accts {
		recs = append(recs, record{Account: a, Token: a.Token})
	}
	plain, err := json.Marshal(recs)
	if err != nil {
		return err
	}
	nonce := make([]byte, s.aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return err
	}
	out := append(append(append([]byte{}, magic...), nonce...), s.aead.Seal(nil, nonce, plain, magic)...)

	s.mu.Lock()
	defer s.mu.Unlock()
	dir := filepath.Dir(s.path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, ".sipgw-accounts-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name()) // no-op after a successful rename
	if err := tmp.Chmod(0o600); err != nil {
		tmp.Close()
		return err
	}
	if _, err := tmp.Write(out); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), s.path)
}
