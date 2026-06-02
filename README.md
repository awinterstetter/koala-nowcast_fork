# koala-nowcast

Automated nowcast pipeline and interactive frontend for **KOALA**
(*KOALitions-Analyse*) — German election polls turned into Monte-Carlo–based
probabilities for seat distributions, threshold crossings and coalition
majorities.

This repo holds the **new serverless stack** (scrape → compute → publish). The
statistical engine lives separately in
[`adibender/coalitions`](https://github.com/adibender/coalitions) and is consumed
here as a dependency.

> **Status: scaffold + working seed.** The end-to-end pipeline is not yet wired up.
> `rlp-dashboard/` is a complete working example (Rheinland-Pfalz Landtagswahl 2026)
> that proves the architecture; the GitHub Actions workflows are stubs to be filled.

## Architecture

Decouple computation from presentation — pre-compute everything, serve static files.

```
Scrape polls ──▶ Compute (coalitions: pool + 100k MC + seat alloc) ──▶ JSON
                                                                         │
                                                          Quarto + OJS site ◀┘
                                                          (static, GitHub Pages)
```

## Layout

```
koala-nowcast/
├── .github/workflows/     # scrape.yml, compute.yml, deploy.yml  (STUBS)
├── scripts/               # scrape + compute R scripts           (TODO)
├── data/
│   ├── surveys/           # raw scraped polls                    (TODO)
│   └── results/           # computed JSON, per election          (TODO)
├── website/               # generalized Quarto + OJS site        (TODO)
└── rlp-dashboard/         # working RLP 2026 example — the seed   ✅
```

### The seed: `rlp-dashboard/`

A self-contained, working slice of the whole pipeline for one election:

- `compute_rlp.R` — `get_surveys_rp()` → `pool_surveys()` (14-day window) →
  `draw_from_posterior()` (Monte-Carlo) → `get_seats()` (Sainte-Laguë) → writes
  6 JSON files to `data/`.
- `index.qmd` — Quarto dashboard (Observable JS / D3) reading those JSON files;
  tabs: Überblick · Sitzverteilung · Umfragen nach Institut · Methodik.

To view locally, render and **serve over HTTP** — opening the built `index.html`
directly via `file://` shows a blank page (browsers block the OJS ES-module
scripts under `file://`):

```sh
cd rlp-dashboard
quarto render
python3 -m http.server 8765   # then open http://localhost:8765
```

## Roadmap

1. Generalize `compute_rlp.R` into config-driven `scripts/compute_probabilities.R`
   (any election: BTW + Landtage) and `scripts/scrape_polls.R`.
2. Promote `index.qmd` into a parameterized `website/` covering all elections.
3. Wire up the workflow stubs: scheduled scrape → triggered compute → deploy to Pages.
4. Expose results as a REST API; ship R + Python client helpers.

See `../KOALA-modernization-plan.md` in the project hub for the full plan.

## License

MIT — see [LICENSE](LICENSE).
