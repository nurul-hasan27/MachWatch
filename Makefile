# Paths
ENGINE_SRC := engine/src/system_monitor.cpp
ENGINE_BIN := engine/bin/system_monitor

APP_DIR    := app
SWIFT_BIN  := app/.build/debug/app

# Tools
CXX := clang++
CXXFLAGS := -std=c++17 -O2
LDFLAGS := -framework CoreFoundation -framework IOKit

# Default target
all: run

# Build C++ engine (only if missing)
$(ENGINE_BIN): $(ENGINE_SRC)
	@echo
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "▶ Building C++ engine"
	@mkdir -p engine/bin
	$(CXX) $(CXXFLAGS) $(ENGINE_SRC) $(LDFLAGS) -o $(ENGINE_BIN)
	@echo "✔︎ C++ engine built"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo


engine: $(ENGINE_BIN)

# Build Swift app (only if missing)
$(SWIFT_BIN):
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "▶ Building Swift app"
	cd $(APP_DIR) && swift build
	@echo "✔︎ Swift app built"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo

swift: $(SWIFT_BIN)

# Run app
run: engine swift
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "▶ Running Swift app"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	$(SWIFT_BIN)
	@echo

# Clean everything
clean:
	@echo
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "▶ Cleaning build artifacts"
	rm -f $(ENGINE_BIN)
	rm -rf app/.build/debug/app
	@echo "✔︎ Clean complete"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo

.PHONY: all engine swift run clean