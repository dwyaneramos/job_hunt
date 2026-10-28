# Job Hunt Widget

A macOS desktop widget for listing software roles. This is completely slopped fyi

## Manual run / rebuild

```bash
# One-time setup (already done): install deps + headless Chromium for SJS
cd scraper && ./venv/bin/pip install -r requirements.txt
./venv/bin/playwright install chromium

# Run the scraper once
./venv/bin/python scraper.py

# Rebuild the app after editing Swift files
cd JobHuntWidget && xcodegen generate
xcodebuild -project JobHuntWidget.xcodeproj -scheme JobHuntApp \
  -configuration Debug -derivedDataPath build -allowProvisioningUpdates build
rm -rf /Applications/JobHunt.app
cp -R build/Build/Products/Debug/JobHunt.app /Applications/JobHunt.app
open /Applications/JobHunt.app
```

Or just click **Refresh Now** in the app — it runs the scraper for you and
reloads the widget.

## Uninstall the background scraper

```bash
launchctl bootout gui/$(id -u)/com.dwyaneramos.jobhuntwidget.scraper
rm ~/Library/LaunchAgents/com.dwyaneramos.jobhuntwidget.scraper.plist
```

