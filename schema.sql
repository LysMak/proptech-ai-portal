-- ============================================================
-- PropTech Real Estate AI Analytics Portal (Praha)
-- Database schema for Supabase (PostgreSQL)
--
-- HOW TO USE:
-- 1. Open your Supabase project -> SQL Editor -> New query
-- 2. Paste this entire file and click "Run"
-- ============================================================

-- --------------------------------------------------------------
-- 1. Extensions
-- --------------------------------------------------------------
create extension if not exists postgis;

-- --------------------------------------------------------------
-- 2. Clean slate (safe to re-run during development)
-- --------------------------------------------------------------
drop table if exists public.properties;

-- --------------------------------------------------------------
-- 3. Table definition
-- --------------------------------------------------------------
create table public.properties (
    id              bigint generated always as identity primary key,
    title           text not null,
    district        text not null,
    price           numeric(12, 0) not null check (price > 0),
    area_sqm        numeric(6, 1) not null check (area_sqm > 0),
    -- price_per_sqm is derived automatically from price / area_sqm,
    -- so it can never drift out of sync with the two source columns.
    price_per_sqm   numeric(10, 0) generated always as (round(price / area_sqm)) stored,
    lat             double precision not null,
    lng             double precision not null,
    -- geog is derived automatically from lat/lng and powers the
    -- PostGIS bounding-box query used by the map (see properties_in_bbox
    -- below), so it can never drift out of sync with lat/lng either.
    geog            geography(Point, 4326) generated always as
                        (ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography) stored,
    deal_rating     text not null,
    ai_summary      text not null,
    created_at      timestamptz not null default now()
);

comment on table public.properties is
    'Prague residential listings enriched with pre-generated AI market analysis.';
comment on column public.properties.price is
    'Asking price in CZK.';
comment on column public.properties.price_per_sqm is
    'Generated column: price / area_sqm, rounded to the nearest CZK.';
comment on column public.properties.geog is
    'Generated column: geography point derived from lat/lng, used for the PostGIS bounding-box index/query.';
comment on column public.properties.deal_rating is
    'Human-readable AI verdict vs. district average, e.g. "Pod tržní cenou (-8 %)".';
comment on column public.properties.ai_summary is
    'Czech-language summary written from the perspective of the AI valuation model.';

-- Helpful index for the district filter used by the frontend
create index properties_district_idx on public.properties (district);

-- Spatial index powering the bounding-box query below
create index properties_geog_idx on public.properties using gist (geog);

-- --------------------------------------------------------------
-- 4. Row Level Security
--
-- The frontend talks to Supabase using the public "anon" key, so we
-- must explicitly allow read-only access. No INSERT/UPDATE/DELETE
-- policy is created, which means the anon key can never modify data.
-- --------------------------------------------------------------
alter table public.properties enable row level security;

create policy "Allow public read" on public.properties
    for select
    using (true);

-- --------------------------------------------------------------
-- 5. Bounding-box query (RPC)
--
-- The frontend calls this instead of "select *" every time the map
-- viewport changes (Leaflet's "moveend" event), so only listings
-- actually visible on screen are ever fetched. The "&&" operator uses
-- the GIST index above for a fast, index-only bounding-box filter
-- rather than scanning every row.
-- --------------------------------------------------------------
create or replace function public.properties_in_bbox(
    min_lng double precision,
    min_lat double precision,
    max_lng double precision,
    max_lat double precision
)
returns setof public.properties
language sql
stable
as $$
    select *
    from public.properties
    where geog && ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326)::geography
$$;

grant execute on function public.properties_in_bbox(double precision, double precision, double precision, double precision)
    to anon, authenticated;

comment on function public.properties_in_bbox is
    'Returns listings whose location falls within the given lng/lat bounding box, using the GIST spatial index.';

-- --------------------------------------------------------------
-- 6. Seed data — 10 realistic Prague listings
--    (Karlín, Vinohrady, Žižkov, Smíchov)
--
-- Coordinates point at real streets in each district.
-- Prices are modelled on 2024/2025 Prague market averages:
--   Karlín    ~155 000 Kč/m²
--   Vinohrady ~158 000 Kč/m²
--   Žižkov    ~118 000 Kč/m²
--   Smíchov   ~132 000 Kč/m²
-- --------------------------------------------------------------
insert into public.properties
    (title, district, price, area_sqm, lat, lng, deal_rating, ai_summary)
values
(
    'Zrekonstruovaný byt 2+kk, Křižíkova',
    'Karlín',
    9260000,
    65.0,
    50.0958, 14.4467,
    'Pod tržní cenou (-8 %)',
    'AI analýza porovnala 52 srovnatelných nabídek v Karlíně za posledních 90 dní a vyhodnotila tuto nemovitost jako podhodnocenou o 8 % oproti průměru lokality (155 000 Kč/m²). Byt těží z pěší dostupnosti stanice metra B Křižíkova (4 min) a rostoucí poptávky po rezidencích s výhledem na Vltavu. Doporučení: velmi zajímavá investiční příležitost s potenciálem růstu ceny.'
),
(
    'Moderní loft 1+kk, Pernerova',
    'Karlín',
    7440000,
    48.0,
    50.0930, 14.4450,
    'Tržní cena',
    'Cena odpovídá aktuálnímu tržnímu průměru čtvrti Karlín (155 000 Kč/m²). Lokalita s vysokou koncentrací kancelářských budov a rozvíjející se infrastrukturou nabízí stabilní výnos z pronájmu. Model predikuje meziroční růst ceny o 3-4 %.'
),
(
    'Luxusní studio, Sokolovská',
    'Karlín',
    5750000,
    35.0,
    50.0940, 14.4520,
    'Nadprůměrná cena (+6 %)',
    'Nemovitost je oceněna 6 % nad průměrem lokality, což model přisuzuje kompletní rekonstrukci a prémiovým povrchovým úpravám. I přes vyšší cenu zůstává poptávka v této části Karlína nadprůměrná díky blízkosti Rohanského ostrova a parku.'
),
(
    'Prostorný byt 3+kk, Náměstí Míru',
    'Vinohrady',
    11010000,
    82.0,
    50.0752, 14.4376,
    'Skvělá nabídka (-15 %)',
    'Na základě 68 srovnatelných transakcí v okolí Náměstí Míru model identifikoval tuto nabídku jako výrazně podhodnocenou (-15 %) vůči tržnímu průměru 158 000 Kč/m². Vysoce žádaná lokalita s výbornou občanskou vybaveností a historickou architekturou činí z tohoto bytu prioritní investiční tip týdne.'
),
(
    'Byt 2+1 po rekonstrukci, Korunní',
    'Vinohrady',
    8255000,
    55.0,
    50.0765, 14.4460,
    'Pod tržní cenou (-5 %)',
    'Byt po kompletní rekonstrukci je nabízen 5 % pod tržním průměrem ulice Korunní. Model zohlednil vysokou likviditu vinohradských bytů (průměrná doba prodeje 34 dní) a doporučuje rychlé jednání ze strany kupujícího.'
),
(
    'Rodinný byt 4+kk, Chorvatská',
    'Vinohrady',
    15800000,
    100.0,
    50.0740, 14.4410,
    'Tržní cena',
    'Cena odpovídá průměru lokality pro byty této dispozice a plochy. Rodinná dispozice 4+kk je na Vinohradech vzácná, což dlouhodobě podporuje stabilitu ceny i v případě mírné korekce trhu.'
),
(
    'Byt 1+kk se zahrádkou, Seifertova',
    'Žižkov',
    4955000,
    40.0,
    50.0838, 14.4460,
    'Nadprůměrná cena (+5 %)',
    'Nabídka je o 5 % nad průměrnou cenou v Žižkově (118 000 Kč/m²), pravděpodobně kvůli soukromé zahrádce, která je pro tuto lokalitu neobvyklým benefitem. Model doporučuje zvážit cenu vzhledem k celkovému technickému stavu domu.'
),
(
    'Cihlový byt 3+1, Husitská',
    'Žižkov',
    7435000,
    70.0,
    50.0850, 14.4500,
    'Pod tržní cenou (-10 %)',
    'Cihlový byt je podhodnocen o 10 % oproti srovnatelným nabídkám v okolí Husitské. Žižkov aktuálně zaznamenává jeden z nejrychlejších meziročních růstů cen v Praze (+9,2 % r/r), což z bytu činí atraktivní investici s potenciálem zhodnocení.'
),
(
    'Byt 2+kk po celkové rekonstrukci, Nádražní',
    'Smíchov',
    7920000,
    60.0,
    50.0705, 14.4040,
    'Tržní cena',
    'Cena odpovídá tržnímu průměru čtvrti Smíchov (132 000 Kč/m²). Lokalita profituje z blízkosti stanice metra B Anděl a rozvíjející se občanské vybavenosti podél nábřeží řeky.'
),
(
    'Prostorný byt 3+kk s balkonem, Plzeňská',
    'Smíchov',
    11050000,
    90.0,
    50.0680, 14.3980,
    'Pod tržní cenou (-7 %)',
    'Model identifikoval nabídku jako podhodnocenou o 7 % vůči srovnatelným bytům v okolí Plzeňské. Prostorná dispozice s balkonem a dobrá dostupnost MHD řadí byt mezi TOP tipy týdne pro rodiny s dětmi.'
);

-- --------------------------------------------------------------
-- 7. Quick sanity checks (optional — run separately if you like)
-- --------------------------------------------------------------
-- select title, district, price, area_sqm, price_per_sqm, deal_rating
-- from public.properties
-- order by district, price;

-- Example bounding-box query covering roughly all of central Prague:
-- select title, district from public.properties_in_bbox(14.35, 50.03, 14.55, 50.13);
