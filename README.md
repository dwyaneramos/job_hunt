# Job Hunt Widget

A macOS desktop widget + companion app showing NZ software developer /
engineering / internship / graduate roles, with a background scraper that
keeps it updated.

## Pieces

- `scraper/` — Python scraper. Pulls RemoteOK, WeWorkRemotely, Greenhouse
  (curated companies), LinkedIn's public guest job search, and Student Job
  Search NZ (SJS, via headless Chromium since its listings are client-side
  rendered). Filters by keyword and (currently) restricts results to New
  Zealand locations, then writes `jobs.json` to
  `~/Library/Application Support/JobHuntWidget/jobs.json`. The widget
  extension is sandboxed and reads that path via a
  `temporary-exception.files.home-relative-path` entitlement rather than an
  App Group — App Group containers on this macOS version silently deny
  sandboxed reads of files written by a fully unsandboxed process (kernel
  logs it as `deny(1) file-read-data`), so this was the reliable option.
- `JobHuntWidget/` — Xcode project (generated via XcodeGen from
  `project.yml`). Contains the `JobHuntApp` (full job list, search, quick
  links, Refresh Now button) and `JobHuntWidgetExtension` (the actual
  desktop widget).
- `com.dwyaneramos.jobhuntwidget.scraper.plist` (installed to
  `~/Library/LaunchAgents/`) — runs the scraper every 2 hours in the
  background, independent of whether the app is open.

## Sources NOT scraped

Indeed, Prosple, Seek NZ, and GradConnection NZ all return active bot-challenge
responses (Cloudflare/AWS WAF). Rather than attempt to bypass their anti-bot
protection, the app shows one-click search links for these instead (see
`quick_links` in `scraper/config.json`). SJS is scraped, not linked — its
`robots.txt` explicitly allows general crawlers on job pages (it only blocks
Indeed's bot specifically), so it doesn't have the same objection.

## Changing keywords / locations

Edit `scraper/config.json`:
- `direct_phrases` / `tech_terms` / `role_terms` / `exclude_keywords` control
  matching.
- `nz_only: true` restricts results to NZ locations — set to `false` to allow
  jobs from anywhere (e.g. more remote roles).
- `greenhouse_companies` is a curated list of companies whose public job
  board API gets checked — add more company slugs (from
  `boards.greenhouse.io/<slug>`) as you find them.
- `adzuna` — optional. Get a free key at https://developer.adzuna.com/, set
  `enabled: true` and fill in `app_id`/`app_key`.
- `sjs_search_terms` — keyword searches run against Student Job Search NZ.

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

## Notes

- Code-signed with a free personal Apple Developer team (`JR892KH5RJ`) —
  fine for local use, not for distribution.
- LinkedIn scraping uses their public, unauthenticated guest search
  endpoint (no login), rate-limited with a short delay between requests.
  It's still against LinkedIn's User Agreement even for personal use — the
  practical risk is IP/rate-limit blocking, not legal exposure at this
  scale. If it starts getting blocked, disable it in `scraper.py` (remove
  it from the `sources` list in `main()`) and rely on the LinkedIn quick
  link instead.
