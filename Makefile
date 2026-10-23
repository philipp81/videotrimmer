# VideoTrimmer – Build ohne Xcode-Projekt: `make` erzeugt build/VideoTrimmer.app
APP       := VideoTrimmer
BUILD     := build
BUNDLE    := $(BUILD)/$(APP).app
CONTENTS  := $(BUNDLE)/Contents
BIN       := $(CONTENTS)/MacOS/$(APP)

SRCS      := $(wildcard src/*.mm)
OBJS      := $(patsubst src/%.mm,$(BUILD)/obj/%.o,$(SRCS))
HDRS      := $(wildcard src/*.h src/*.hpp)

CXX       := clang++
CXXFLAGS  := -std=c++17 -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations \
             -mmacosx-version-min=12.0 -Isrc
LDFLAGS   := -framework Cocoa -framework AVFoundation -framework CoreMedia -framework QuartzCore \
             -framework UniformTypeIdentifiers

.PHONY: all run test clean

all: $(BIN) $(CONTENTS)/Info.plist $(CONTENTS)/PkgInfo $(CONTENTS)/Resources/$(APP).icns
	@codesign --force --sign - $(BUNDLE) 2>/dev/null || true
	@echo "→ $(BUNDLE)"

$(BUILD)/obj/%.o: src/%.mm $(HDRS)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(BIN): $(OBJS)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $(OBJS) $(LDFLAGS) -o $@

$(CONTENTS)/Info.plist: Info.plist
	@mkdir -p $(dir $@)
	cp $< $@

$(CONTENTS)/PkgInfo:
	@mkdir -p $(dir $@)
	printf 'APPL????' > $@

run: all
	open $(BUNDLE)

test: $(BUILD)/time_test
	$(BUILD)/time_test

$(BUILD)/time_test: tests/time_test.cpp src/TimeUtil.hpp
	@mkdir -p $(BUILD)
	$(CXX) -std=c++17 -Wall -Wextra -Isrc $< -o $@

clean:
	rm -rf $(BUILD)

install: all
	rm -rf /Applications/$(APP).app
	cp -R $(BUNDLE) /Applications/
	@echo "→ /Applications/$(APP).app"

# --- App-Icon: wird vektoriell von tools/mkicon.mm gezeichnet (make icon erneuert resources/VideoTrimmer.icns)
ICON_TOOL := $(BUILD)/mkicon
ICNS      := resources/$(APP).icns

.PHONY: icon
icon: $(ICNS)

$(ICON_TOOL): tools/mkicon.mm
	@mkdir -p $(BUILD)
	$(CXX) $(CXXFLAGS) $< -framework Cocoa -o $@

$(ICNS): $(ICON_TOOL)
	@rm -rf $(BUILD)/icon.iconset && mkdir -p resources
	$(ICON_TOOL) $(BUILD)/icon.iconset $(BUILD)/icon_preview.png
	iconutil -c icns $(BUILD)/icon.iconset -o $@

$(CONTENTS)/Resources/$(APP).icns: $(ICNS)
	@mkdir -p $(dir $@)
	cp $< $@
