# PropTech Real Estate AI Analytics Portal (Praha)

> AI-powered market intelligence for Prague residential real estate — an interactive map and analytics portal that flags underpriced listings in real time.
>
> AI-poháněná tržní analytika pro rezidenční nemovitosti v Praze — interaktivní mapa a analytický portál, který v reálném čase označuje podhodnocené nabídky.

**Live demo:** https://proptech-ai-portal.vercel.app
**Repository:** https://github.com/LysMak/proptech-ai-portal

---

## 1. Business Value / Obchodní přínos

Real estate buyers and investors struggle to answer one simple question fast: **is this listing priced fairly for its neighbourhood?** This portal answers that in one glance by combining:

- a **geospatial view** of 50 live listings spread across 20 Prague districts, from the historical center (Staré Město, Malá Strana) to residential and emerging areas (Karlín, Vinohrady, Žižkov, Smíchov, Dejvice, Holešovice, Vysočany, and more),
- a **price-per-m² benchmark** computed directly in the database, and
- an **AI-generated verdict** ("Pod tržní cenou -8 %", "Tržní cena", "Nadprůměrná cena +5 %") that turns a raw price into an actionable signal.

For a PropTech company like VIAGEM a.s., this pattern — structured listing data + geodata + an AI valuation layer — is a direct proof-of-concept for tools that help agents and buyers price and evaluate property faster and more transparently.

Kupující a investoři potřebují rychlou odpověď na otázku: **je tato nabídka cenově adekvátní pro danou lokalitu?** Portál na to odpovídá na první pohled kombinací mapy, cenového benchmarku za m² a AI hodnocení generovaného pro každou nemovitost.

---

## 2. Tech Stack

| Layer | Technology | Why |
|---|---|---|
| Frontend | HTML5, CSS3 (Grid & Flexbox), Vanilla JavaScript (ES6+) | No framework overhead, fast to load, easy to audit — appropriate for a focused portfolio project |
| Map | [Leaflet.js](https://leafletjs.com/) + CARTO dark tiles | Free, open-source, no API key required |
| Backend & DB | [Supabase](https://supabase.com/) (managed PostgreSQL + auto-generated REST API) | Zero backend code to maintain; Postgres gives real relational guarantees (constraints, generated columns) |
| Data access | `@supabase/supabase-js` v2 via CDN | Official client, no build step needed |
| Security | PostgreSQL Row Level Security (RLS) | Public `anon` key can only `SELECT` — enforced at the database layer, not in application code |
| AI layer | Pre-generated valuation summaries (Claude 3.5 Sonnet) | Simulates an AI pricing-assistant feature without needing a live inference endpoint / budget |
| Hosting / CI-CD | GitHub + Vercel | Push-to-deploy static hosting, zero configuration for a static site |
| Budget | **0 CZK** | Every service used is on a free tier |

---

## 3. Local Setup

This is a static site with no build step — you only need a local HTTP server (opening `index.html` directly via `file://` will work for the UI, but some browsers restrict CDN scripts on `file://`, so a local server is recommended).

```bash
# 1. Clone the repository
git clone https://github.com/<your-username>/proptech-ai-portal.git
cd proptech-ai-portal

# 2. Configure Supabase credentials
# Edit config.js and set SUPABASE_URL / SUPABASE_ANON_KEY
# (see INSTRUCTIONS.md for exactly where to find them)

# 3. Serve the folder locally, e.g. with Python:
python -m http.server 5500
# or with Node:
npx serve .

# 4. Open in your browser
# http://localhost:5500
```

For the full click-by-click setup (creating the Supabase project, running the schema, deploying to Vercel), see [`INSTRUCTIONS.md`](./INSTRUCTIONS.md).

---

## 4. Project Structure

```
.
├── schema.sql       # PostgreSQL schema + RLS policy + seed data (run in Supabase SQL Editor)
├── config.js        # Supabase URL + anon key (the only file you edit)
├── index.html        # Full application: markup, styles, and client-side logic
└── README.md
```

---

## 5. Architecture & Engineering Approaches

**Row Level Security (RLS) in Supabase.**
The `properties` table has RLS enabled with a single `SELECT`-only policy (`Allow public read`). The public `anon` key shipped in `config.js` can therefore never insert, update, or delete data — write access would require a `service_role` key that is never exposed to the browser. This mirrors how a real production PropTech backend would separate a public read API from an authenticated write path (e.g. an internal CMS or ingestion pipeline).

**Derived data at the database layer.**
`price_per_sqm` is a PostgreSQL **generated column** (`generated always as (round(price / area_sqm)) stored`), not something computed and duplicated in application code. This guarantees the value can never drift out of sync with `price` and `area_sqm`, and keeps the benchmarking logic in one place.

**Geospatial data handling — PostGIS bounding-box queries.**
Each listing stores `lat`/`lng` as `double precision`, plus a `geog geography(Point, 4326)` **generated column** derived from them and indexed with GIST (`properties_geog_idx`). Rather than fetching the whole table, the frontend calls a Postgres RPC function, `properties_in_bbox(min_lng, min_lat, max_lng, max_lat)`, every time the Leaflet map's viewport changes (`moveend`), which filters rows server-side using the `&&` bounding-box operator against the spatial index. This means the amount of data transferred scales with what's actually visible on screen, not with the size of the dataset — the same pattern a production listings map would use once the table holds thousands of rows instead of ten. The frontend renders results as custom Leaflet `divIcon` markers whose color encodes the AI deal rating (green = under market, amber = at market, red = above market), so the map itself communicates the analytics — not just location. Clicking a card flies the map to the corresponding marker (triggering a fresh bounding-box fetch around it) and opens its popup; clicking a marker highlights and scrolls to its card.

**AI-assisted valuation, pre-computed by design.**
Rather than calling a paid LLM API on every page load (which would break the 0 CZK budget and add latency), each listing's `deal_rating` and `ai_summary` were generated once, offline, with Claude 3.5 Sonnet acting as a market analyst over comparable listings, then stored as plain columns. This is a realistic pattern for production: expensive AI inference runs in a batch/offline pipeline, and the frontend only ever reads cheap, pre-computed results.

**One genuinely live data source: official ČSÚ/ČÚZK statistics.**
There is no free public API for real-time individual listings from Czech portals (Sreality, Bezrealitky, …) — and scraping them would violate their terms of service, so the 50 listings above stay clearly-labeled demo data. What *is* free, legal, and genuinely live is the Czech Statistical Office's open dataset `CEN0402` (average real-estate purchase prices, sourced from the ČÚZK land registry's actual recorded transactions, CORS-open, no API key). The banner above the map fetches it directly from `data.csu.gov.cz` on every page load and shows the latest official average price per m² for Prague apartments plus year-on-year change — real official numbers, not a demo. It only resolves to kraj/okres level (Prague as a whole), so it complements the per-district demo listings rather than replacing their granularity.

**CI/CD via Vercel.**
The project has zero build step, so Vercel's static deployment is used as-is: every push to the connected GitHub branch triggers an automatic redeploy, giving instant preview URLs for pull requests and a stable production URL for `main` — a minimal but real CI/CD loop appropriate for a project this size.

**Two-layer filtering: server-side by geography, client-side by text/price.**
The listing set loaded into memory is already scoped to the map viewport by `properties_in_bbox` (see above); search, district, price-range, and sort filters then run client-side against that smaller in-memory array. This keeps typing in the search box instant while still avoiding a full-table fetch, and remains a straightforward place to push district/price filtering server-side too (`.eq()`, `.gte()` on the Supabase query builder) if the dataset grows much larger.

**Bilingual UI without a translation service.**
The interface switches between Czech and English via a small in-browser dictionary (`I18N` in `index.html`) applied through `data-i18n` attributes — no i18n library or server round-trip needed for a UI this size. Listing content is trickier: `title`/`ai_summary` and their `title_en`/`ai_summary_en` counterparts are both stored as plain columns, generated together (and kept numerically consistent) rather than translated live, matching the same "pre-computed AI output" philosophy used for the deal ratings. `deal_rating` itself is the one exception — it's stored only in Czech, and its English label is derived client-side from the same leading +/- percentage, so the two languages can never drift out of sync on the underlying number. District names are intentionally left untranslated in both languages, the way a real Prague listings site would keep "Vinohrady" or "Malá Strana" as proper nouns.

---

## 6. Possible Extensions

- Replace static seed data with a scraper/ingestion job writing into the same schema.
- Add authentication (Supabase Auth) and a saved-favourites feature per user.
- Add a `properties_history` table + a price-trend sparkline per listing.
- Move from client-side to PostgREST-level filtering (`?district=eq.Karlín`) for larger datasets.
- Swap pre-generated AI summaries for a live Claude API call behind a serverless function, with response caching.

---

## License

MIT — feel free to fork and adapt for your own portfolio.
