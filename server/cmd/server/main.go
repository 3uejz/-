// Command server 是浮生录的模块化单体后端入口。
//
// 当前为 M0 骨架：仅提供健康检查与路由挂载点，具体业务模块按 tasklist 推进。
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/health", healthHandler)

	addr := ":8080"
	if v := os.Getenv("SERVER_ADDR"); v != "" {
		addr = v
	}
	log.Printf("life-text-sandbox server listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("server exited: %v", err)
	}
}

func healthHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"status": "ok",
		"time":   time.Now().UTC().Format(time.RFC3339),
	})
}
