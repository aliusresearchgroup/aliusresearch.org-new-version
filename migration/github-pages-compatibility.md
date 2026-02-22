# Weebly Export to GitHub Pages Migration Audit

Generated on 2026-02-22 (UTC) after extracting `897210165153652097-1771703083.zip`.

## What was done

- Extracted the Weebly export into `docs/` (GitHub Pages deploy folder).
- Removed the single hashed wrapper folder (`1054327522699a091f1fb90/`) while preserving all internal site paths beneath it.
- Added `docs/.nojekyll` so GitHub Pages serves the static export without Jekyll processing.
- Wrote a ZIP manifest to `migration/weebly-zip-manifest.csv`.
- Wrote extraction summary to `migration/extraction-summary.txt`.
- Patched `http://` mixed-content blockers for Weebly CDN assets and YouTube embeds to `https://` across all HTML pages.

## Resulting structure (deploy-ready)

The site is now organized for GitHub Pages under:

- `docs/index.html`
- `docs/*.html` (145 exported pages)
- `docs/files/` (theme assets)
- `docs/uploads/` (media, PDFs, images)
- `docs/apps/` (legacy app assets)

## Inventory summary

- HTML pages: 145
- Total extracted files: 1407
- Total extracted directories: 16
- Total extracted file bytes: 1,798,999,230

## GitHub Pages compatibility status

### Works as static hosting

- The exported site is static HTML/CSS/JS/assets, so it can be hosted on GitHub Pages.
- `docs/index.html` is present.
- `.nojekyll` is present.

### Remaining incompatibilities / features needing migration

1. Site size exceeds GitHub Pages published-site limit (critical blocker)
- Current extracted site size: 1,798,999,230 bytes (~1.80 GB).
- GitHub Pages published sites may be no larger than 1 GB.
- This is likely to prevent a successful/acceptable GitHub Pages deployment unless you reduce size.
- Most size is in large media files (especially GIFs and WAVs).
- Consider moving heavy assets to external object storage/CDN (Cloudflare R2, S3, Backblaze B2, etc.) and linking to them.

Largest contributors by file type (approximate):
- `.gif`: 1,235,022,636 bytes (97 files)
- `.wav`: 189,969,868 bytes (4 files)
- `.png`: 176,142,334 bytes (400 files)
- `.pdf`: 87,830,890 bytes (119 files)

2. Weebly forms will need replacement
- 15 pages contain Weebly form submissions.
- 23 form instances submit to `//www.weebly.com/weebly/apps/formSubmit.php`.
- These forms are Weebly-managed and may not work reliably from a GitHub Pages-hosted site (domain ownership/backend dependency/recaptcha integration).
- Replace with a static-friendly form backend (for example: Formspree, Basin, Netlify Forms, custom serverless endpoint).

Affected pages:
- `docs/alpha-waves.html`
- `docs/active-roles.html`
- `docs/application-late.html`
- `docs/journal-club-228113.html`
- `docs/depersonalisation.html`
- `docs/membership-renewal-178580.html`
- `docs/peripersonal.html`
- `docs/mapping-dmt.html`
- `docs/meditation-psychedelics-self.html`
- `docs/psychedelic-pharmacology.html`
- `docs/journal-club.html`
- `docs/journal-club-995321.html`
- `docs/psychedelics-challenging-experiences.html`
- `docs/symposium.html`
- `docs/trauma_under_psychedelics.html`

3. All pages still depend on Weebly/EditMySite-hosted assets/scripts
- 145/145 pages reference `editmysite.com` and/or `weebly.com` resources.
- If Weebly retires or changes those assets, page styling/behavior may break.
- For long-term stability, copy required third-party CSS/JS/font assets locally and update references.

4. Weebly customer-account script is included on all pages
- 145/145 pages load `main-customer-accounts-site.js`.
- Customer account / membership features tied to Weebly will not be functional on GitHub Pages.
- This script can usually be removed after testing if you do not need Weebly account features.

5. Broken social/share URLs in `blog-v1.html`
- `docs/blog-v1.html` contains `http://UNSET/...` share URLs.
- These are legacy Weebly placeholders and will not generate valid sharing links without manual cleanup.

6. Windows path length risk for Git operations (not a GitHub Pages runtime issue)
- Longest relative file path in `docs/`: 224 chars.
- Longest absolute path in this local checkout: 292 chars.
- On Windows, Git may fail to add/checkout these files unless long paths are enabled.
- Recommendation: set `core.longpaths=true` (repo or global) before committing.

## Notes

- A legacy Flash file exists (`docs/apps/audioPlayer2.swf`), but no `.swf` references were found in the exported HTML. It is likely unused.
- Mixed-content blockers for Weebly CDN and YouTube embed URLs were patched to HTTPS across all 145 HTML files.

## Suggested next migration steps

1. Replace Weebly forms on the 15 listed pages.
2. Decide whether to keep or remove Weebly customer-account scripts.
3. Vendor local copies of critical Weebly CSS/JS/font assets to remove external dependency.
4. Clean up `blog-v1.html` share links (`UNSET` URLs).
5. Enable GitHub Pages from the `docs/` folder on the repository's default branch.
