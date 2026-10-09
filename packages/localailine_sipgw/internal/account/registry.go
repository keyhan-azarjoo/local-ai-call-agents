package account

import (
	"crypto/sha256"
	"crypto/subtle"
	"slices"
	"sync"
)

// Registry holds every line, by id and by token. It hands out copies, so callers can't change
// an account behind its back.
type Registry struct {
	mu      sync.RWMutex
	byID    map[string]*Account
	byToken map[[32]byte]string // sha256(token) -> id
}

// NewRegistry makes an empty registry.
func NewRegistry() *Registry {
	return &Registry{byID: map[string]*Account{}, byToken: map[[32]byte]string{}}
}

// Put adds or replaces a. An empty Token gets a new one; on replace the old token is kept
// (so the provider's binding stays valid), and an empty Password keeps the old password.
// It returns the stored copy.
func (r *Registry) Put(a Account) Account {
	r.mu.Lock()
	defer r.mu.Unlock()
	if old, ok := r.byID[a.ID]; ok {
		if a.Token == "" {
			a.Token = old.Token
		}
		if a.Password == "" {
			a.Password = old.Password
		}
		if old.Token != a.Token {
			delete(r.byToken, sha256.Sum256([]byte(old.Token)))
		}
	}
	if a.Token == "" {
		a.Token = NewToken()
	}
	a.AllowedSource = slices.Clone(a.AllowedSource)
	r.byID[a.ID] = &a
	r.byToken[sha256.Sum256([]byte(a.Token))] = a.ID
	return a
}

// Delete removes the line; false if there was none.
func (r *Registry) Delete(id string) (Account, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	a, ok := r.byID[id]
	if !ok {
		return Account{}, false
	}
	delete(r.byID, id)
	delete(r.byToken, sha256.Sum256([]byte(a.Token)))
	return *a, true
}

// Get returns a copy of the line with this id.
func (r *Registry) Get(id string) (Account, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	a, ok := r.byID[id]
	if !ok {
		return Account{}, false
	}
	return *a, true
}

// ByToken finds the line whose Contact token is tok. The map is keyed by a hash of the token
// and the final check is constant-time, so response timing says nothing about valid tokens.
func (r *Registry) ByToken(tok string) (Account, bool) {
	if tok == "" || len(tok) > 128 {
		return Account{}, false
	}
	r.mu.RLock()
	defer r.mu.RUnlock()
	id, ok := r.byToken[sha256.Sum256([]byte(tok))]
	if !ok {
		return Account{}, false
	}
	a := r.byID[id]
	if a == nil || subtle.ConstantTimeCompare([]byte(a.Token), []byte(tok)) != 1 {
		return Account{}, false
	}
	return *a, true
}

// ByNumber finds the line whose own number is n (first match).
func (r *Registry) ByNumber(n string) (Account, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	for _, a := range r.byID {
		if a.Number == n {
			return *a, true
		}
	}
	return Account{}, false
}

// All returns copies of every line, sorted by id.
func (r *Registry) All() []Account {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]Account, 0, len(r.byID))
	for _, a := range r.byID {
		out = append(out, *a)
	}
	slices.SortFunc(out, func(x, y Account) int {
		if x.ID < y.ID {
			return -1
		}
		if x.ID > y.ID {
			return 1
		}
		return 0
	})
	return out
}

// Len is the number of lines.
func (r *Registry) Len() int {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return len(r.byID)
}
