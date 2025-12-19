# Paths
ENGINE_SRC := engine/src/system_monitor.cpp
ENGINE_BIN := engine/bin/system_monitor

APP_DIR    := app
SWIFT_BIN  := app/.build/debug/app

# Tools
CXX := clang++
CXXFLAGS := -std=c++17 -O2

# Default target
all: run

# Build C++ engine (only if missing)
$(ENGINE_BIN): $(ENGINE_SRC)
	@echo "Building C++ engine..."
	@mkdir -p engine/bin
	$(CXX) $(CXXFLAGS) $(ENGINE_SRC) -o $(ENGINE_BIN)

engine: $(ENGINE_BIN)

# Build Swift app (only if missing)
$(SWIFT_BIN):
	@echo "Building Swift app..."
	cd $(APP_DIR) && swift build

swift: $(SWIFT_BIN)

# Run app
run: engine swift
	@echo "Running Swift app..."
	$(SWIFT_BIN)

# Clean everything
clean:
	@echo "Cleaning engine and Swift build..."
	rm -f $(ENGINE_BIN)
	rm -rf app/.build/debug/app

.PHONY: all engine swift run clean
