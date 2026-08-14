#!/usr/bin/env python3
"""Scrapes several job sources for software dev / engineering / internship /
graduate roles and writes a normalized jobs.json for the JobHunt widget to read.

Sources:
  - RemoteOK          public JSON API
  - WeWorkRemotely    public RSS feed
  - LinkedIn (guest)  public, unauthenticated job-search HTML fragments
  - Greenhouse        public job-board API for a curated list of companies
  - Adzuna            optional, requires a free API key (see config.json)
  - SJS               Student Job Search NZ — robots.txt allows general
                       crawlers on job pages, but listings are client-side
                       rendered, so this one uses a headless browser
                       (Playwright) instead of plain requests.

Sites that actively block automated requests (Indeed, Prosple, Seek NZ,
GradConnection) are NOT scraped — see config.json "quick_links" instead.
"""
import hashlib
import json
import re
import subprocess
import sys
import time
import urllib.parse
from datetime import datetime, timezone, timedelta
from pathlib import Path
from xml.etree import ElementTree

import requests
from playwright.sync_api import sync_playwright
from bs4 import BeautifulSoup

SCRAPER_DIR = Path(__file__).resolve().parent
CONFIG_PATH = SCRAPER_DIR / "config.json"
OUTPUT_PATH = Path.home() / "Library/Application Support/JobHuntWidget/jobs.json"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
}
REQUEST_TIMEOUT = 15


def load_config() -> dict:
    with open(CONFIG_PATH) as f:
        return json.load(f)


def job_id(source: str, url: str) -> str:
    return hashlib.sha1(f"{source}:{url}".encode()).hexdigest()[:16]


def _applescript_escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"')


def notify(title: str, message: str) -> None:
    """Best-effort macOS notification (Notification Center) via osascript."""
    script = (
        f'display notification "{_applescript_escape(message)}" '
        f'with title "{_applescript_escape(title)}"'
    )
    try:
        subprocess.run(["osascript", "-e", script], check=False, timeout=5)
    except Exception as e:
        print(f"[notify] failed: {e}", file=sys.stderr)


def _word_in(term: str, text_l: str) -> bool:
    return re.search(r"\b" + re.escape(term) + r"\b", text_l) is not None


def matches_keywords(text: str, cfg: dict) -> bool:
    text_l = text.lower()
    if any(_word_in(bad, text_l) for bad in cfg["exclude_keywords"]):
        return False
    if any(_word_in(phrase, text_l) for phrase in cfg["direct_phrases"]):
        return True
    tech_hit = any(_word_in(term, text_l) for term in cfg["tech_terms"])
    role_hit = any(_word_in(term, text_l) for term in cfg["role_terms"])
    return tech_hit and role_hit


def make_job(source, title, company, location, url, posted=None, tags=None):
    return {
        "id": job_id(source, url),
        "title": title.strip(),
        "company": (company or "").strip(),
        "location": (location or "").strip() or "Not specified",
        "url": url,
        "source": source,
        "posted": posted,
        "tags": tags or [],
    }


# ---------------------------------------------------------------------------
# RemoteOK
# ---------------------------------------------------------------------------
def fetch_remoteok(cfg: dict) -> list[dict]:
    jobs = []
    try:
        r = requests.get("https://remoteok.com/api", headers=HEADERS, timeout=REQUEST_TIMEOUT)
        r.raise_for_status()
        data = r.json()
    except Exception as e:
        print(f"[remoteok] fetch failed: {e}", file=sys.stderr)
        return jobs

    for item in data:
        if not isinstance(item, dict) or "position" not in item:
            continue  # skip legal-notice header entry
        title = item.get("position", "")
        tags = item.get("tags", []) or []
        haystack = " ".join([title] + tags)
        if not matches_keywords(haystack, cfg):
            continue
        url = item.get("url") or f"https://remoteok.com/remote-jobs/{item.get('id', '')}"
        posted = item.get("date")
        jobs.append(
            make_job(
                "RemoteOK",
                title,
                item.get("company"),
                item.get("location") or "Remote",
                url,
                posted=posted,
                tags=tags,
            )
        )
        if len(jobs) >= cfg["max_jobs_per_source"]:
            break
    return jobs


# ---------------------------------------------------------------------------
# WeWorkRemotely
# ---------------------------------------------------------------------------
def fetch_weworkremotely(cfg: dict) -> list[dict]:
    jobs = []
    feed_url = "https://weworkremotely.com/categories/remote-programming-jobs.rss"
    try:
        r = requests.get(feed_url, headers=HEADERS, timeout=REQUEST_TIMEOUT)
        r.raise_for_status()
        root = ElementTree.fromstring(r.content)
    except Exception as e:
        print(f"[weworkremotely] fetch failed: {e}", file=sys.stderr)
        return jobs

    for item in root.iter("item"):
        title_el = item.find("title")
        link_el = item.find("link")
        pubdate_el = item.find("pubDate")
        if title_el is None or link_el is None:
            continue
        title = title_el.text or ""
        if not matches_keywords(title, cfg):
            continue
        # WWR titles are usually "Company: Job Title"
        company, _, role = title.partition(":")
        role = role.strip() or title
        jobs.append(
            make_job(
                "WeWorkRemotely",
                role,
                company.strip(),
                "Remote",
                (link_el.text or "").strip(),
                posted=pubdate_el.text if pubdate_el is not None else None,
            )
        )
        if len(jobs) >= cfg["max_jobs_per_source"]:
            break
    return jobs


# ---------------------------------------------------------------------------
# LinkedIn guest job search (public, unauthenticated)
# ---------------------------------------------------------------------------
def fetch_linkedin(cfg: dict) -> list[dict]:
    jobs = []
    seen_urls = set()
    base = "https://www.linkedin.com/jobs-guest/jobs/api/seeMoreJobPostings/search"
    search_terms = ["software engineer OR software developer", "graduate software", "software internship"]
    locations = cfg["locations"]["linkedin_query_locations"]

    for location in locations:
        for term in search_terms:
            params = {"keywords": term, "location": location, "start": 0}
            try:
                r = requests.get(base, params=params, headers=HEADERS, timeout=REQUEST_TIMEOUT)
                if r.status_code != 200:
                    print(f"[linkedin] {r.status_code} for {term!r} @ {location!r}", file=sys.stderr)
                    continue
                soup = BeautifulSoup(r.text, "lxml")
            except Exception as e:
                print(f"[linkedin] fetch failed for {term!r} @ {location!r}: {e}", file=sys.stderr)
                continue

            for card in soup.select("div.base-search-card"):
                title_el = card.select_one("h3.base-search-card__title")
                company_el = card.select_one("h4.base-search-card__subtitle")
                location_el = card.select_one("span.job-search-card__location")
                link_el = card.select_one("a.base-card__full-link") or card.find_parent("a")
                if not title_el or not link_el or not link_el.get("href"):
                    continue
                url = link_el["href"].split("?")[0]
                if url in seen_urls:
                    continue
                title = title_el.get_text(strip=True)
                if not matches_keywords(title, cfg):
                    continue
                seen_urls.add(url)
                time_el = card.select_one("time")
                jobs.append(
                    make_job(
                        "LinkedIn",
                        title,
                        company_el.get_text(strip=True) if company_el else None,
                        location_el.get_text(strip=True) if location_el else location,
                        url,
                        posted=time_el.get("datetime") if time_el else None,
                    )
                )
            time.sleep(1.5)  # be polite / avoid rate-limit flags

            if len(jobs) >= cfg["max_jobs_per_source"]:
                return jobs[: cfg["max_jobs_per_source"]]
    return jobs


# ---------------------------------------------------------------------------
# Greenhouse job boards (official public API, curated company list)
# ---------------------------------------------------------------------------
def fetch_greenhouse(cfg: dict) -> list[dict]:
    jobs = []
    for company in cfg.get("greenhouse_companies", []):
        url = f"https://boards-api.greenhouse.io/v1/boards/{company}/jobs?content=true"
        try:
            r = requests.get(url, headers=HEADERS, timeout=REQUEST_TIMEOUT)
            if r.status_code != 200:
                continue
            data = r.json()
        except Exception as e:
            print(f"[greenhouse:{company}] fetch failed: {e}", file=sys.stderr)
            continue

        for posting in data.get("jobs", []):
            title = posting.get("title", "")
            if not matches_keywords(title, cfg):
                continue
            location = (posting.get("location") or {}).get("name")
            jobs.append(
                make_job(
                    "Greenhouse",
                    title,
                    company.capitalize(),
                    location,
                    posting.get("absolute_url"),
                    posted=posting.get("updated_at"),
                )
            )
    return jobs[: cfg["max_jobs_per_source"]]


# ---------------------------------------------------------------------------
# Student Job Search NZ (headless-browser scrape; client-rendered listings)
# ---------------------------------------------------------------------------
def fetch_sjs(cfg: dict) -> list[dict]:
    jobs = []
    seen_urls = set()
    base = "https://www.sjs.co.nz"
    search_terms = cfg.get("sjs_search_terms", ["software", "graduate", "internship IT"])

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page(user_agent=HEADERS["User-Agent"])
            for term in search_terms:
                url = f"{base}/job-seeker/jobs?keywords={urllib.parse.quote(term)}"
                try:
                    page.goto(url, wait_until="networkidle", timeout=30000)
                    page.wait_for_timeout(1500)
                except Exception as e:
                    print(f"[sjs] navigation failed for {term!r}: {e}", file=sys.stderr)
                    continue

                soup = BeautifulSoup(page.content(), "lxml")
                for card in soup.select("[class*=JobCard_jobCard]"):
                    title_el = card.select_one("h4 a")
                    if not title_el or not title_el.get("href"):
                        continue
                    href = title_el["href"]
                    job_url = href if href.startswith("http") else f"{base}{href}"
                    if job_url in seen_urls:
                        continue
                    title = title_el.get_text(strip=True)
                    if not matches_keywords(title, cfg):
                        continue
                    seen_urls.add(job_url)

                    company_el = card.select_one("[class*=JobCard_company]")
                    location_el = card.select_one("[class*=JobCard_location]")
                    posted_el = card.select_one("[class*=JobCard_postedDate]")

                    posted = None
                    if posted_el:
                        posted_text = posted_el.get_text(strip=True).replace("Created on:", "").strip()
                        try:
                            posted = datetime.strptime(posted_text, "%b %d, %Y").isoformat()
                        except ValueError:
                            posted = None

                    jobs.append(
                        make_job(
                            "SJS",
                            title,
                            company_el.get_text(strip=True) if company_el else None,
                            location_el.get_text(strip=True) if location_el else None,
                            job_url,
                            posted=posted,
                        )
                    )
                    if len(jobs) >= cfg["max_jobs_per_source"]:
                        break
                if len(jobs) >= cfg["max_jobs_per_source"]:
                    break
            browser.close()
    except Exception as e:
        print(f"[sjs] browser session failed: {e}", file=sys.stderr)

    return jobs


# ---------------------------------------------------------------------------
# Adzuna (optional, needs free API key in config.json)
# ---------------------------------------------------------------------------
def fetch_adzuna(cfg: dict) -> list[dict]:
    jobs = []
    az = cfg.get("adzuna", {})
    if not az.get("enabled") or not az.get("app_id") or not az.get("app_key"):
        return jobs

    country = az.get("country", "nz")
    url = f"https://api.adzuna.com/v1/api/jobs/{country}/search/1"
    for what in ["software engineer", "software developer", "graduate software", "software internship"]:
        params = {
            "app_id": az["app_id"],
            "app_key": az["app_key"],
            "what": what,
            "results_per_page": 20,
            "content-type": "application/json",
        }
        try:
            r = requests.get(url, params=params, timeout=REQUEST_TIMEOUT)
            r.raise_for_status()
            data = r.json()
        except Exception as e:
            print(f"[adzuna] fetch failed for {what!r}: {e}", file=sys.stderr)
            continue

        for posting in data.get("results", []):
            title = posting.get("title", "")
            if not matches_keywords(title, cfg):
                continue
            jobs.append(
                make_job(
                    "Adzuna",
                    title,
                    (posting.get("company") or {}).get("display_name"),
                    (posting.get("location") or {}).get("display_name"),
                    posting.get("redirect_url"),
                    posted=posting.get("created"),
                )
            )
    return jobs[: cfg["max_jobs_per_source"]]


# ---------------------------------------------------------------------------
def is_nz_job(job: dict, cfg: dict) -> bool:
    location_l = job["location"].lower()
    return any(_word_in(signal, location_l) for signal in cfg["nz_location_signals"])


def load_previous_job_ids() -> set[str]:
    try:
        with open(OUTPUT_PATH) as f:
            previous = json.load(f)
        return {job["id"] for job in previous.get("jobs", [])}
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        return set()


def dedupe(jobs: list[dict]) -> list[dict]:
    seen = {}
    for job in jobs:
        key = (job["title"].lower(), job["company"].lower())
        if key not in seen:
            seen[key] = job
    return list(seen.values())


def main():
    cfg = load_config()
    all_jobs = []
    errors = []

    sources = [
        ("RemoteOK", fetch_remoteok),
        ("WeWorkRemotely", fetch_weworkremotely),
        ("Greenhouse", fetch_greenhouse),
        ("LinkedIn", fetch_linkedin),
        ("SJS", fetch_sjs),
        ("Adzuna", fetch_adzuna),
    ]

    for name, fn in sources:
        try:
            found = fn(cfg)
            print(f"[{name}] {len(found)} matching jobs")
            all_jobs.extend(found)
        except Exception as e:
            print(f"[{name}] unexpected error: {e}", file=sys.stderr)
            errors.append({"source": name, "error": str(e)})

    all_jobs = dedupe(all_jobs)
    if cfg.get("nz_only"):
        all_jobs = [j for j in all_jobs if is_nz_job(j, cfg)]
    all_jobs.sort(key=lambda j: j.get("posted") or "", reverse=True)

    previous_ids = load_previous_job_ids()
    new_job_count = 0
    for job in all_jobs:
        job["is_new"] = job["id"] not in previous_ids
        if job["is_new"]:
            new_job_count += 1
            if job["source"] == "SJS":
                notify(f"New SJS job: {job['title']}", job.get("company") or "")

    output = {
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "job_count": len(all_jobs),
        "new_job_count": new_job_count,
        "jobs": all_jobs,
        "quick_links": cfg.get("quick_links", []),
        "errors": errors,
    }

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w") as f:
        json.dump(output, f, indent=2)

    print(f"Wrote {len(all_jobs)} jobs ({new_job_count} new) to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
