#!/usr/bin/env python3
"""Regenerate sitemap.xml from the .html files actually present in the repo.

Walks the repo for *.html files, maps each to its public URL (an index.html
becomes its directory with a trailing slash), and writes sitemap.xml.

Priorities are hand-tuned per page, not derived from any rule, so this
script never invents one for a page that's already listed: it keeps
whatever <priority> that URL already had. Only genuinely new pages get a
default (1.0 for the homepage, 0.8 for a new section index, 0.6 for
anything else) - reweight those by hand afterward if 0.6 isn't right.
Pages removed from disk are dropped with a warning rather than silently.
"""
import os
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent
SITEMAP_PATH = REPO_ROOT / "sitemap.xml"
BASE_URL = "https://www.prunusdomestic.com"
SITEMAP_NS = "http://www.sitemaps.org/schemas/sitemap/0.9"

EXCLUDE_DIRS = {".git", "node_modules"}

DEFAULT_PRIORITY_HOME = "1.0"
DEFAULT_PRIORITY_SECTION = "0.8"
DEFAULT_PRIORITY_PAGE = "0.6"


def find_html_files():
    for dirpath, dirnames, filenames in os.walk(REPO_ROOT):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS and not d.startswith(".")]
        for name in filenames:
            if name.endswith(".html"):
                yield Path(dirpath, name).relative_to(REPO_ROOT)


def url_path_for(rel_path: Path) -> str:
    posix = rel_path.as_posix()
    if rel_path.name == "index.html":
        parent = rel_path.parent.as_posix()
        return "/" if parent == "." else f"/{parent}/"
    return f"/{posix}"


def load_existing_priorities(path: Path) -> dict:
    if not path.exists():
        return {}
    tree = ET.parse(path)
    root = tree.getroot()
    priorities = {}
    for url_el in root.findall(f"{{{SITEMAP_NS}}}url"):
        loc_el = url_el.find(f"{{{SITEMAP_NS}}}loc")
        prio_el = url_el.find(f"{{{SITEMAP_NS}}}priority")
        if loc_el is not None and loc_el.text and prio_el is not None:
            priorities[loc_el.text.strip()] = prio_el.text.strip()
    return priorities


def default_priority(url_path: str) -> str:
    if url_path == "/":
        return DEFAULT_PRIORITY_HOME
    if url_path.endswith("/"):
        return DEFAULT_PRIORITY_SECTION
    return DEFAULT_PRIORITY_PAGE


def sort_key(url_path: str):
    if url_path == "/":
        return (0, "", 0, "")
    is_index = url_path.endswith("/")
    segments = url_path.strip("/").split("/")
    directory = segments[0]
    if is_index or len(segments) > 1:
        return (1, directory, 0 if is_index else 1, url_path)
    return (2, "", 0, url_path)


def main():
    existing_priorities = load_existing_priorities(SITEMAP_PATH)

    current_entries = {}
    for rel_path in find_html_files():
        url_path = url_path_for(rel_path)
        loc = f"{BASE_URL}/" if url_path == "/" else f"{BASE_URL}{url_path}"
        current_entries[loc] = url_path

    added = sorted(loc for loc in current_entries if loc not in existing_priorities)
    removed = sorted(loc for loc in existing_priorities if loc not in current_entries)

    lines = ['<?xml version="1.0" encoding="UTF-8"?>', f'<urlset xmlns="{SITEMAP_NS}">']
    for loc, url_path in sorted(current_entries.items(), key=lambda kv: sort_key(kv[1])):
        priority = existing_priorities.get(loc) or default_priority(url_path)
        lines.append("  <url>")
        lines.append(f"    <loc>{loc}</loc>")
        lines.append(f"    <priority>{priority}</priority>")
        lines.append("  </url>")
    lines.append("</urlset>")
    lines.append("")

    SITEMAP_PATH.write_text("\n".join(lines))

    print(f"wrote {len(current_entries)} URLs to {SITEMAP_PATH.name}")
    if added:
        print("added (defaulted priority, review if it should be higher/lower):")
        for loc in added:
            print(f"  + {loc}  ({default_priority(current_entries[loc])})")
    if removed:
        print("removed (no longer on disk):", file=sys.stderr)
        for loc in removed:
            print(f"  - {loc}", file=sys.stderr)
    if not added and not removed:
        print("no changes")


if __name__ == "__main__":
    main()
