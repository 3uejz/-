package auth

import (
	"context"
	"sort"
	"sync"
)

// MemoryStore 是进程内 Store 实现，用于测试与无数据库的本地模式。
type MemoryStore struct {
	mu        sync.Mutex
	byName    map[string]Account
	byID      map[string]Account
	refreshes map[string]RefreshRecord
}

// NewMemoryStore 创建空的内存账号存储。
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		byName:    map[string]Account{},
		byID:      map[string]Account{},
		refreshes: map[string]RefreshRecord{},
	}
}

func (m *MemoryStore) CreateAccount(_ context.Context, a Account) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.byName[a.Username]; ok {
		return ErrUsernameTaken
	}
	m.byName[a.Username] = a
	m.byID[a.ID] = a
	return nil
}

func (m *MemoryStore) AccountByUsername(_ context.Context, username string) (Account, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	a, ok := m.byName[username]
	return a, ok
}

func (m *MemoryStore) AccountByID(_ context.Context, accountID string) (Account, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	a, ok := m.byID[accountID]
	return a, ok
}

func (m *MemoryStore) SaveRefresh(_ context.Context, r RefreshRecord) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.refreshes[r.Hash] = r
	return nil
}

func (m *MemoryStore) RefreshByHash(_ context.Context, hash string) (RefreshRecord, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	r, ok := m.refreshes[hash]
	return r, ok
}

func (m *MemoryStore) DeleteRefresh(_ context.Context, hash string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.refreshes, hash)
	return nil
}

// ListAccounts 返回按创建时间倒序的账号分页；afterID 为上一页最后一项 ID。
func (m *MemoryStore) ListAccounts(_ context.Context, limit int, afterID string) ([]Account, string) {
	m.mu.Lock()
	list := make([]Account, 0, len(m.byID))
	for _, a := range m.byID {
		list = append(list, a)
	}
	m.mu.Unlock()
	sort.Slice(list, func(i, j int) bool {
		if list[i].CreatedAt.Equal(list[j].CreatedAt) {
			return list[i].ID > list[j].ID
		}
		return list[i].CreatedAt.After(list[j].CreatedAt)
	})
	start := 0
	if afterID != "" {
		for i, a := range list {
			if a.ID == afterID {
				start = i + 1
				break
			}
		}
	}
	end := start + limit
	if limit <= 0 || end > len(list) {
		end = len(list)
	}
	page := list[start:end]
	next := ""
	if end < len(list) && len(page) > 0 {
		next = page[len(page)-1].ID
	}
	return page, next
}
