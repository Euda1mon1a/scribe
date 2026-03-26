.PHONY: install backend app clean

# Install Python backend
install:
	uv pip install -e .

# Run the backend
backend:
	python3 -m backend.main

# Build macOS app (requires Xcode + xcodegen)
app:
	cd app && xcodegen generate && \
	xcodebuild -project Scribe.xcodeproj -scheme Scribe_macOS \
		-destination 'platform=macOS' -configuration Release build

# Build and install app to /Applications
app-install: app
	@rm -rf /Applications/Scribe.app
	@cp -R "$$(xcodebuild -project app/Scribe.xcodeproj -scheme Scribe_macOS \
		-destination 'platform=macOS' -configuration Release \
		-showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | \
		awk '{print $$3}')/Scribe.app" /Applications/
	@echo "Installed to /Applications/Scribe.app"

# Clean build artifacts
clean:
	rm -rf app/.build app/Scribe.xcodeproj/xcuserdata
	cd app && xcodebuild clean 2>/dev/null || true
