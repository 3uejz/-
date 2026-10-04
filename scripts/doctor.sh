#!/usr/bin/env bash
# 工具链自检：打印关键组件版本与路径
set -u
GODOT_BIN="${GODOT_BIN:-/workspace/.toolchain/godot}"
line() { printf "%-14s %s\n" "$1" "$2"; }

line "os" "$( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}" )"
line "arch" "$(uname -m)"
line "cpus" "$(nproc)"
line "go" "$(go version 2>/dev/null || echo MISSING)"
line "node" "$(node --version 2>/dev/null || echo MISSING)"
line "npm" "$(npm --version 2>/dev/null || echo MISSING)"
line "python3" "$(python3 --version 2>/dev/null || echo MISSING)"
line "gcc" "$(gcc --version 2>/dev/null | head -1 || echo MISSING)"
line "cmake" "$(cmake --version 2>/dev/null | head -1 || echo MISSING)"
line "protoc" "$(protoc --version 2>/dev/null || echo MISSING)"
line "psql" "$(psql --version 2>/dev/null || echo MISSING)"
line "redis" "$(redis-server --version 2>/dev/null | head -1 || echo MISSING)"
line "godot" "$("$GODOT_BIN" --headless --version 2>/dev/null || echo MISSING)"
