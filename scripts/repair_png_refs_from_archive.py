#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
import zipfile
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(r"c:\Users\cogpsy-vrlab\Documents\GitHub\aliusresearch.org")
DOCS = ROOT / "docs"
ARCHIVE_ZIP = Path(r"C:\Users\cogpsy-vrlab\Documents\897210165153652097-1771703083.zip")

TEXT_EXTS = {".html", ".css", ".js"}
PNG_REF_RE = re.compile(
    r'(?:https?://(?:www\.)?aliusresearch\.org)?(?P<path>/[^"\'()\s>]+?\.png)(?:\?[^"\'()\s>]*)?',
    re.IGNORECASE,
)

VENDOR_PREFIX = "/assets/vendor/editmysite/cdn11.editmysite.com"
THEME_IMAGE_PREFIX = "/assets/vendor/weebly-site/files/theme/files"


# These were moved/renamed in the exported site, but equivalent/canonical copies already exist.
CUSTOM_REWRITES: dict[str, str] = {
    "/uploads/9/1/6/0/91600416/editor/andres_2.png": "/media/images/andres-3.png",
    "/uploads/9/1/6/0/91600416/editor/gfejer_2.png": "/media/images/gfejer-3.png",
    "/uploads/9/1/6/0/91600416/editor/jonas_1.png": "/media/images/jonas-3.png",
    "/uploads/9/1/6/0/91600416/editor/keisuke.png": "/media/images/keisuke-1.png",
    "/uploads/9/1/6/0/91600416/editor/pawel.png": "/media/images/pawel-4.png",
    "/uploads/9/1/6/0/91600416/editor/stratos_2.png": "/media/images/stratos-3.png",
    "/uploads/9/1/6/0/91600416/editor/timo_2.png": "/media/images/timo-2.png",
    "/uploads/9/1/6/0/91600416/published/gfejer.png": "/media/images/gfejer-3.png",
    "/uploads/9/1/6/0/91600416/published/gfejer_2.png": "/media/images/gfejer-3.png",
    "/uploads/9/1/6/0/91600416/published/jonas_1.png": "/media/images/jonas-3.png",
    "/uploads/9/1/6/0/91600416/published/keisuke.png": "/media/images/keisuke-1.png",
    "/uploads/9/1/6/0/91600416/published/pawel.png": "/media/images/pawel-4.png",
    "/uploads/9/1/6/0/91600416/published/picture2_2.png": "/uploads/9/1/6/0/91600416/editor/picture2_2.png",
    "/uploads/9/1/6/0/91600416/235236364n-taru-hirvonen-circle_orig.png": "/uploads/9/1/6/0/91600416/editor/235236364n-taru-hirvonen-circle.png",
    "/uploads/9/1/6/0/91600416/published/235236364n-taru-hirvonen-circle.png": "/uploads/9/1/6/0/91600416/editor/235236364n-taru-hirvonen-circle.png",
    "/uploads/9/1/6/0/91600416/editor/174135311286243396_1.png": "/uploads/9/1/6/0/91600416/174135311286243396-1_orig.png",
    "/uploads/9/1/6/0/91600416/published/174135311286243396_1.png": "/uploads/9/1/6/0/91600416/174135311286243396-1_orig.png",
    "/uploads/9/1/6/0/91600416/kezia-circle_1.png": "/uploads/9/1/6/0/91600416/kezia-circle_orig.png",
    "/uploads/9/1/6/0/91600416/published/headshot-enzo_12.png": "/uploads/9/1/6/0/91600416/headshot-enzo_12.png",
    "/uploads/9/1/6/0/91600416/published/image-3_12.png": "/uploads/9/1/6/0/91600416/image-3_12.png",
    "/uploads/9/1/6/0/91600416/published/mve_12.png": "/uploads/9/1/6/0/91600416/mve_12.png",
    "/uploads/9/1/6/0/91600416/published/screen-shot-2016-12-23-at-17-44-51_15.png": "/uploads/9/1/6/0/91600416/screen-shot-2016-12-23-at-17-44-51_15.png",
    "/uploads/9/1/6/0/91600416/published/screen-shot-2018-07-16-at-10-26-47_11.png": "/uploads/9/1/6/0/91600416/screen-shot-2018-07-16-at-10-26-47_11.png",
    "/uploads/9/1/6/0/91600416/published/stratos_6.png": "/uploads/9/1/6/0/91600416/stratos_6.png",
    "/uploads/9/1/6/0/91600416/published/imageedit-11-4394935007_4.png": "/media/images/imageedit-11-4394935007-5.png",
}


# Canonical targets that may not exist yet but can be restored from the archive.
CANONICAL_ARCHIVE_RESTORE: dict[str, str] = {
    "/uploads/9/1/6/0/91600416/174135311286243396-1_orig.png": "uploads/9/1/6/0/91600416/174135311286243396-1_orig.png",
    "/uploads/9/1/6/0/91600416/kezia-circle_orig.png": "uploads/9/1/6/0/91600416/kezia-circle_orig.png",
    "/uploads/9/1/6/0/91600416/headshot-enzo_12.png": "uploads/9/1/6/0/91600416/headshot-enzo_12.png",
    "/uploads/9/1/6/0/91600416/image-3_12.png": "uploads/9/1/6/0/91600416/image-3_12.png",
    "/uploads/9/1/6/0/91600416/mve_12.png": "uploads/9/1/6/0/91600416/mve_12.png",
    "/uploads/9/1/6/0/91600416/screen-shot-2016-12-23-at-17-44-51_15.png": "uploads/9/1/6/0/91600416/screen-shot-2016-12-23-at-17-44-51_15.png",
    "/uploads/9/1/6/0/91600416/screen-shot-2018-07-16-at-10-26-47_11.png": "uploads/9/1/6/0/91600416/screen-shot-2018-07-16-at-10-26-47_11.png",
    "/uploads/9/1/6/0/91600416/stratos_6.png": "uploads/9/1/6/0/91600416/stratos_6.png",
}


@dataclass
class Audit:
    refs_by_file: dict[Path, list[str]]
    counts: Counter
    missing_local: list[str]


def to_docs_path(site_path: str) -> Path:
    return DOCS.joinpath(*site_path.lstrip("/").split("/"))


def scan_png_refs() -> Audit:
    refs_by_file: dict[Path, list[str]] = {}
    counts: Counter[str] = Counter()

    for p in DOCS.rglob("*"):
        if not p.is_file() or p.suffix.lower() not in TEXT_EXTS:
            continue
        text = p.read_text(encoding="utf-8", errors="ignore")
        hits: list[str] = []
        for m in PNG_REF_RE.finditer(text):
            path = m.group("path")
            # Ignore protocol-relative external URLs and JS-escaped fragments
            if path.startswith("//") or "\\" in path:
                continue
            hits.append(path)
            counts[path] += 1
        if hits:
            refs_by_file[p] = hits

    missing_local = [p for p in counts if p.startswith("/") and not to_docs_path(p).exists()]
    missing_local.sort()
    return Audit(refs_by_file=refs_by_file, counts=counts, missing_local=missing_local)


def detect_zip_root(zf: zipfile.ZipFile) -> str:
    names = zf.namelist()
    if not names:
        raise RuntimeError("Archive is empty")
    return names[0].split("/")[0] + "/"


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def extract_zip_entry(zf: zipfile.ZipFile, zip_name: str, dest: Path) -> bool:
    if dest.exists():
        return False
    ensure_parent(dest)
    with zf.open(zip_name) as src, open(dest, "wb") as out:
        out.write(src.read())
    return True


def apply_path_replacements(replacements: dict[str, str]) -> tuple[int, int]:
    # Bytewise replacement preserves line endings and avoids encoding drift for binary-like JS bundles.
    bmap = [(old.encode("ascii"), new.encode("ascii")) for old, new in sorted(replacements.items(), key=lambda kv: len(kv[0]), reverse=True)]
    files_changed = 0
    total_subs = 0
    for p in DOCS.rglob("*"):
        if not p.is_file() or p.suffix.lower() not in TEXT_EXTS:
            continue
        data = p.read_bytes()
        orig = data
        subs_here = 0
        for old_b, new_b in bmap:
            if old_b in data:
                count = data.count(old_b)
                data = data.replace(old_b, new_b)
                subs_here += count
        if data != orig:
            p.write_bytes(data)
            files_changed += 1
            total_subs += subs_here
    return files_changed, total_subs


def main() -> int:
    if not DOCS.exists():
        print(f"docs directory not found: {DOCS}", file=sys.stderr)
        return 1
    if not ARCHIVE_ZIP.exists():
        print(f"archive not found: {ARCHIVE_ZIP}", file=sys.stderr)
        return 1

    before = scan_png_refs()
    print(f"Before: unique_png_paths={len(before.counts)} missing_local_png_paths={len(before.missing_local)}")

    replacements: dict[str, str] = {}
    extracted = 0
    extracted_paths: list[str] = []

    with zipfile.ZipFile(ARCHIVE_ZIP) as zf:
        zip_names = set(zf.namelist())
        zip_root = detect_zip_root(zf)

        # 1) Safe rewrites to existing vendor/theme assets (minimize redundancy)
        for path in before.missing_local:
            if path.startswith("/images/") or path.startswith("/sprites/"):
                vendor_target = VENDOR_PREFIX + path
                if to_docs_path(vendor_target).exists():
                    replacements.setdefault(path, vendor_target)
                    continue
                if path.startswith("/images/"):
                    theme_target = THEME_IMAGE_PREFIX + path
                    if to_docs_path(theme_target).exists():
                        replacements.setdefault(path, theme_target)
                        continue

        # 2) Custom canonical rewrites for moved/renamed assets
        for old_path, new_path in CUSTOM_REWRITES.items():
            if old_path in before.counts:
                if not to_docs_path(new_path).exists() and new_path not in CANONICAL_ARCHIVE_RESTORE:
                    print(f"warning: custom target missing and no archive restore rule: {old_path} -> {new_path}")
                replacements[old_path] = new_path

        # 3) Restore canonical targets required by custom rewrites
        for site_target, archive_rel in CANONICAL_ARCHIVE_RESTORE.items():
            if site_target not in replacements.values():
                continue
            dest = to_docs_path(site_target)
            if dest.exists():
                continue
            zip_name = zip_root + archive_rel
            if zip_name not in zip_names:
                print(f"warning: archive missing canonical restore source for {site_target}: {zip_name}")
                continue
            if extract_zip_entry(zf, zip_name, dest):
                extracted += 1
                extracted_paths.append(site_target)

        # 4) Restore exact missing archive paths that are still unresolved and referenced
        #    (preserve original references when possible)
        for path in before.missing_local:
            if path in replacements:
                continue
            # Ignore the JS-escaped slideshow artifact if present in raw string form elsewhere.
            if "\\" in path:
                continue
            zip_name = zip_root + path.lstrip("/")
            if zip_name in zip_names:
                if extract_zip_entry(zf, zip_name, to_docs_path(path)):
                    extracted += 1
                    extracted_paths.append(path)

    files_changed, total_subs = apply_path_replacements(replacements)

    after = scan_png_refs()
    print(f"Replacements planned/applied: {len(replacements)} unique paths")
    print(f"Text files changed: {files_changed}")
    print(f"Total literal substitutions: {total_subs}")
    print(f"Archive PNGs restored: {extracted}")
    if extracted_paths:
        for p in extracted_paths[:40]:
            print(f"  restored: {p}")
        if len(extracted_paths) > 40:
            print(f"  ... and {len(extracted_paths)-40} more")

    remaining = after.missing_local
    print(f"After: unique_png_paths={len(after.counts)} missing_local_png_paths={len(remaining)}")
    if remaining:
        # Show only local paths; external protocol-relative URLs were excluded in scan
        for p in remaining[:200]:
            print(f"  missing: {after.counts[p]}x {p}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
