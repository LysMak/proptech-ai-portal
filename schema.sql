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
    title_en        text not null,
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
    -- deal_rating is only ever stored in Czech; the English label is
    -- derived client-side from its leading +/- percentage (language-
    -- neutral), so it never needs a translated counterpart.
    deal_rating     text not null,
    ai_summary      text not null,
    ai_summary_en   text not null,
    created_at      timestamptz not null default now()
);

comment on table public.properties is
    'Prague residential listings enriched with pre-generated AI market analysis.';
comment on column public.properties.price is
    'Asking price in CZK.';
comment on column public.properties.price_per_sqm is
    'Generated column: price / area_sqm, rounded to the nearest CZK.';
comment on column public.properties.title_en is
    'English translation of title, used when the frontend language switch is set to English.';
comment on column public.properties.ai_summary_en is
    'English translation of ai_summary. District names and deal_rating stay in Czech in both languages.';
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
-- 5b. Price history (for the sparkline on each card)
--
-- One row per recorded price point. property_id has a foreign key
-- with ON DELETE CASCADE, so history never outlives its listing.
-- --------------------------------------------------------------
create table public.price_history (
    id            bigint generated always as identity primary key,
    property_id   bigint not null references public.properties(id) on delete cascade,
    price         numeric(12, 0) not null check (price > 0),
    recorded_at   date not null,
    created_at    timestamptz not null default now()
);

comment on table public.price_history is
    'Historical asking-price points per listing, used to render a price-trend sparkline on each card.';

create index price_history_property_id_idx on public.price_history (property_id, recorded_at);

alter table public.price_history enable row level security;

create policy "Allow public read" on public.price_history
    for select
    using (true);

-- --------------------------------------------------------------
-- 6. Seed data — 50 realistic Prague listings across 20 districts
--
-- Coordinates point at real streets in each district.
-- Prices are modelled on 2024/2025 Prague market averages, highest
-- in the historical center and lowest in outer residential districts.
-- --------------------------------------------------------------

-- 6a. Original 10 listings (Karlín, Vinohrady, Žižkov, Smíchov)
--   Karlín    ~155 000 Kč/m²
--   Vinohrady ~158 000 Kč/m²
--   Žižkov    ~118 000 Kč/m²
--   Smíchov   ~132 000 Kč/m²
insert into public.properties
    (title, title_en, district, price, area_sqm, lat, lng, deal_rating, ai_summary, ai_summary_en)
values
(
    'Zrekonstruovaný byt 2+kk, Křižíkova',
    'Renovated apartment 2+kk, Křižíkova',
    'Karlín',
    9260000,
    65.0,
    50.0958, 14.4467,
    'Pod tržní cenou (-8 %)',
    'AI analýza porovnala 52 srovnatelných nabídek v Karlíně za posledních 90 dní a vyhodnotila tuto nemovitost jako podhodnocenou o 8 % oproti průměru lokality (155 000 Kč/m²). Byt těží z pěší dostupnosti stanice metra B Křižíkova (4 min) a rostoucí poptávky po rezidencích s výhledem na Vltavu. Doporučení: velmi zajímavá investiční příležitost s potenciálem růstu ceny.',
    'AI analysis compared 52 similar listings in Karlín over the last 90 days and found this property undervalued by 8% versus the area average (155 000 CZK/m²). The apartment benefits from being a short walk from Křižíkova metro station (Line B, 4 min) and growing demand for residences with views of the Vltava. Recommendation: a very attractive investment opportunity with upside potential.'
),
(
    'Moderní loft 1+kk, Pernerova',
    'Modern loft 1+kk, Pernerova',
    'Karlín',
    7440000,
    48.0,
    50.0930, 14.4450,
    'Tržní cena',
    'Cena odpovídá aktuálnímu tržnímu průměru čtvrti Karlín (155 000 Kč/m²). Lokalita s vysokou koncentrací kancelářských budov a rozvíjející se infrastrukturou nabízí stabilní výnos z pronájmu. Model predikuje meziroční růst ceny o 3-4 %.',
    'The price matches the current market average for Karlín (155 000 CZK/m²). The area has a high concentration of office buildings and growing infrastructure, offering a stable rental yield. The model predicts a year-on-year price increase of 3-4%.'
),
(
    'Luxusní studio, Sokolovská',
    'Luxury studio, Sokolovská',
    'Karlín',
    5750000,
    35.0,
    50.0940, 14.4520,
    'Nadprůměrná cena (+6 %)',
    'Nemovitost je oceněna 6 % nad průměrem lokality, což model přisuzuje kompletní rekonstrukci a prémiovým povrchovým úpravám. I přes vyšší cenu zůstává poptávka v této části Karlína nadprůměrná díky blízkosti Rohanského ostrova a parku.',
    'The property is priced 6% above the area average, which the model attributes to a complete renovation and premium finishes. Despite the higher price, demand in this part of Karlín remains above average thanks to the proximity of Rohanský Island and the park.'
),
(
    'Prostorný byt 3+kk, Náměstí Míru',
    'Spacious apartment 3+kk, Náměstí Míru',
    'Vinohrady',
    11010000,
    82.0,
    50.0752, 14.4376,
    'Skvělá nabídka (-15 %)',
    'Na základě 68 srovnatelných transakcí v okolí Náměstí Míru model identifikoval tuto nabídku jako výrazně podhodnocenou (-15 %) vůči tržnímu průměru 158 000 Kč/m². Vysoce žádaná lokalita s výbornou občanskou vybaveností a historickou architekturou činí z tohoto bytu prioritní investiční tip týdne.',
    'Based on 68 comparable transactions around Náměstí Míru, the model identified this listing as significantly undervalued (-15%) versus the market average of 158 000 CZK/m². A highly sought-after location with excellent amenities and historic architecture makes this apartment a top investment pick of the week.'
),
(
    'Byt 2+1 po rekonstrukci, Korunní',
    'Apartment 2+1 after renovation, Korunní',
    'Vinohrady',
    8255000,
    55.0,
    50.0765, 14.4460,
    'Pod tržní cenou (-5 %)',
    'Byt po kompletní rekonstrukci je nabízen 5 % pod tržním průměrem ulice Korunní. Model zohlednil vysokou likviditu vinohradských bytů (průměrná doba prodeje 34 dní) a doporučuje rychlé jednání ze strany kupujícího.',
    'The fully renovated apartment is listed 5% below the market average for Korunní street. The model factored in the high liquidity of Vinohrady apartments (average time to sell: 34 days) and recommends the buyer act quickly.'
),
(
    'Rodinný byt 4+kk, Chorvatská',
    'Family apartment 4+kk, Chorvatská',
    'Vinohrady',
    15800000,
    100.0,
    50.0740, 14.4410,
    'Tržní cena',
    'Cena odpovídá průměru lokality pro byty této dispozice a plochy. Rodinná dispozice 4+kk je na Vinohradech vzácná, což dlouhodobě podporuje stabilitu ceny i v případě mírné korekce trhu.',
    'The price matches the area average for apartments of this layout and size. A family-sized 4+kk layout is rare in Vinohrady, which supports long-term price stability even in a mild market correction.'
),
(
    'Byt 1+kk se zahrádkou, Seifertova',
    'Apartment 1+kk with a garden, Seifertova',
    'Žižkov',
    4955000,
    40.0,
    50.0838, 14.4460,
    'Nadprůměrná cena (+5 %)',
    'Nabídka je o 5 % nad průměrnou cenou v Žižkově (118 000 Kč/m²), pravděpodobně kvůli soukromé zahrádce, která je pro tuto lokalitu neobvyklým benefitem. Model doporučuje zvážit cenu vzhledem k celkovému technickému stavu domu.',
    'This listing is priced 5% above the average for Žižkov (118 000 CZK/m²), likely due to the private garden, an unusual benefit for this location. The model recommends weighing the price against the building''s overall technical condition.'
),
(
    'Cihlový byt 3+1, Husitská',
    'Brick apartment 3+1, Husitská',
    'Žižkov',
    7435000,
    70.0,
    50.0850, 14.4500,
    'Pod tržní cenou (-10 %)',
    'Cihlový byt je podhodnocen o 10 % oproti srovnatelným nabídkám v okolí Husitské. Žižkov aktuálně zaznamenává jeden z nejrychlejších meziročních růstů cen v Praze (+9,2 % r/r), což z bytu činí atraktivní investici s potenciálem zhodnocení.',
    'This brick apartment is undervalued by 10% versus comparable listings around Husitská. Žižkov is currently seeing one of the fastest year-on-year price increases in Prague (+9.2% YoY), making this apartment an attractive investment with appreciation potential.'
),
(
    'Byt 2+kk po celkové rekonstrukci, Nádražní',
    'Apartment 2+kk after full renovation, Nádražní',
    'Smíchov',
    7920000,
    60.0,
    50.0705, 14.4040,
    'Tržní cena',
    'Cena odpovídá tržnímu průměru čtvrti Smíchov (132 000 Kč/m²). Lokalita profituje z blízkosti stanice metra B Anděl a rozvíjející se občanské vybavenosti podél nábřeží řeky.',
    'The price matches the market average for Smíchov (132 000 CZK/m²). The location benefits from its proximity to Anděl metro station (Line B) and the growing amenities along the riverfront.'
),
(
    'Prostorný byt 3+kk s balkonem, Plzeňská',
    'Spacious apartment 3+kk with balcony, Plzeňská',
    'Smíchov',
    11050000,
    90.0,
    50.0680, 14.3980,
    'Pod tržní cenou (-7 %)',
    'Model identifikoval nabídku jako podhodnocenou o 7 % vůči srovnatelným bytům v okolí Plzeňské. Prostorná dispozice s balkonem a dobrá dostupnost MHD řadí byt mezi TOP tipy týdne pro rodiny s dětmi.',
    'The model identified this listing as undervalued by 7% versus comparable apartments around Plzeňská. The spacious layout with a balcony and good public transport access rank this apartment among this week''s top picks for families with children.'
);

-- 6b. Additional 40 listings spread across the rest of Prague
--     (Staré Město, Nové Město, Malá Strana, Nusle, Vyšehrad, Podolí,
--      Braník, Krč, Košíře, Dejvice, Bubeneč, Břevnov, Holešovice,
--      Letná, Libeň, Vysočany) — 20 districts and 50 listings total.
insert into public.properties
    (title, title_en, district, price, area_sqm, lat, lng, deal_rating, ai_summary, ai_summary_en)
values
(
    'Cihlový byt 5+kk mezonet, Kožná',
    'Brick apartment 5+kk duplex, Kožná',
    'Staré Město',
    32250000,
    142.2,
    50.0848, 14.4201,
    'Nadprůměrná cena (+8 %)',
    'Nabídka je o 8 % nad průměrnou cenou v lokalitě Staré Město (210 000 Kč/m²). Lokalita těží z blízkosti stanice metra A "Staroměstská". I přes vyšší cenu zůstává v lokalitě silná poptávka.',
    'This listing is priced 8% above the average for Staré Město (210 000 CZK/m²). The location benefits from its proximity to Staroměstská metro station (Line A). Despite the higher price, demand in the area remains strong.'
),
(
    'Byt Garsoniéra v klidné lokalitě, Dlouhá',
    'Apartment Studio in a quiet location, Dlouhá',
    'Staré Město',
    5205000,
    24.3,
    50.0867, 14.417,
    'Nadprůměrná cena (+2 %)',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Staré Město (210 000 Kč/m²). Lokalita těží z blízkosti stanice metra A "Staroměstská". Model neočekává výrazný pohyb ceny v následujících měsících.',
    'The price matches the current market average for Staré Město (210 000 CZK/m²). The location benefits from its proximity to Staroměstská metro station (Line A). The model does not expect a significant price move in the coming months.'
),
(
    'Světlý byt 4+kk po rekonstrukci, Kožná',
    'Bright, recently renovated apartment 4+kk, Kožná',
    'Staré Město',
    21265000,
    92.9,
    50.0846, 14.4177,
    'Nadprůměrná cena (+9 %)',
    'Nabídka je o 9 % nad průměrnou cenou v lokalitě Staré Město (210 000 Kč/m²). Lokalita těží z blízkosti stanice metra A "Staroměstská". Prémiová cena je částečně vyvážena kvalitou provedení a vybavením.',
    'This listing is priced 9% above the average for Staré Město (210 000 CZK/m²). The location benefits from its proximity to Staroměstská metro station (Line A). The premium price is partly offset by the quality of finish and fittings.'
),
(
    'Prostorný byt 5+kk mezonet, Ječná',
    'Spacious apartment 5+kk duplex, Ječná',
    'Nové Město',
    23850000,
    134.0,
    50.0809, 14.4224,
    'Tržní cena',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Nové Město (178 000 Kč/m²). Lokalita těží z blízkosti stanic metra "Můstek" a "Národní třída". Model neočekává výrazný pohyb ceny v následujících měsících.',
    'The price matches the current market average for Nové Město (178 000 CZK/m²). The location benefits from its proximity to the Můstek and Národní třída metro stations. The model does not expect a significant price move in the coming months.'
),
(
    'Byt 1+1 s terasou, Štěpánská',
    'Apartment 1+1 with a terrace, Štěpánská',
    'Nové Město',
    6745000,
    37.9,
    50.0773, 14.4253,
    'Tržní cena',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Nové Město (178 000 Kč/m²). Lokalita těží z blízkosti stanic metra "Můstek" a "Národní třída". Cena je adekvátní vzhledem k lokalitě a stavu nemovitosti.',
    'The price matches the current market average for Nové Město (178 000 CZK/m²). The location benefits from its proximity to the Můstek and Národní třída metro stations. The price is fair given the location and condition of the property.'
),
(
    'Novostavba, byt 1+kk, Sokolská',
    'New building, apartment 1+kk, Sokolská',
    'Nové Město',
    6070000,
    32.8,
    50.0829, 14.4249,
    'Nadprůměrná cena (+4 %)',
    'Nabídka je o 4 % nad průměrnou cenou v lokalitě Nové Město (178 000 Kč/m²). Lokalita těží z blízkosti stanic metra "Můstek" a "Národní třída". Cena je vyšší než srovnatelné nabídky, kupující by měl zvážit vyjednávání.',
    'This listing is priced 4% above the average for Nové Město (178 000 CZK/m²). The location benefits from its proximity to the Můstek and Národní třída metro stations. The price is higher than comparable listings; buyers should consider negotiating.'
),
(
    'Novostavba, byt 4+kk, Míšeňská',
    'New building, apartment 4+kk, Míšeňská',
    'Malá Strana',
    18840000,
    85.1,
    50.0903, 14.406,
    'Nadprůměrná cena (+8 %)',
    'Nabídka je o 8 % nad průměrnou cenou v lokalitě Malá Strana (205 000 Kč/m²). Lokalita těží z blízkosti stanice metra A "Malostranská". I přes vyšší cenu zůstává v lokalitě silná poptávka.',
    'This listing is priced 8% above the average for Malá Strana (205 000 CZK/m²). The location benefits from its proximity to Malostranská metro station (Line A). Despite the higher price, demand in the area remains strong.'
),
(
    'Byt 4+1 v klidné lokalitě, Nerudova',
    'Apartment 4+1 in a quiet location, Nerudova',
    'Malá Strana',
    17810000,
    102.2,
    50.0886, 14.4038,
    'Skvělá nabídka (-15 %)',
    'AI model porovnal 61 srovnatelných nabídek v lokalitě Malá Strana za posledních 30 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 15 % oproti průměru 205 000 Kč/m². Lokalita těží z blízkosti stanice metra A "Malostranská". Poměr cena/lokalita je u této nabídky výrazně nadprůměrný.',
    'The AI model compared 61 similar listings in Malá Strana over the last 30 days and found this property undervalued by 15% versus the area average of 205 000 CZK/m². The location benefits from its proximity to Malostranská metro station (Line A). The price-to-location ratio for this listing is well above average.'
),
(
    'Byt 3+kk v klidné lokalitě, Táborská',
    'Apartment 3+kk in a quiet location, Táborská',
    'Nusle',
    8395000,
    68.8,
    50.0667, 14.4403,
    'Tržní cena',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Nusle (122 000 Kč/m²). Lokalita těží z blízkosti stanice metra C "Vyšehrad" a Nuselského mostu. Cena je adekvátní vzhledem k lokalitě a stavu nemovitosti.',
    'The price matches the current market average for Nusle (122 000 CZK/m²). The location benefits from its proximity to Vyšehrad metro station (Line C) and the Nuselský Bridge. The price is fair given the location and condition of the property.'
),
(
    'Byt 2+kk s balkonem, Táborská',
    'Apartment 2+kk with balcony, Táborská',
    'Nusle',
    5360000,
    50.5,
    50.0656, 14.4402,
    'Skvělá nabídka (-13 %)',
    'AI model porovnal 62 srovnatelných nabídek v lokalitě Nusle za posledních 45 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 13 % oproti průměru 122 000 Kč/m². Lokalita těží z blízkosti stanice metra C "Vyšehrad" a Nuselského mostu. Doporučujeme rychlé jednání, podobné nabídky mizí z trhu během několika týdnů.',
    'The AI model compared 62 similar listings in Nusle over the last 45 days and found this property undervalued by 13% versus the area average of 122 000 CZK/m². The location benefits from its proximity to Vyšehrad metro station (Line C) and the Nuselský Bridge. We recommend acting quickly — comparable listings tend to sell within a few weeks.'
),
(
    'Novostavba, byt 4+kk, Táborská',
    'New building, apartment 4+kk, Táborská',
    'Nusle',
    14195000,
    103.9,
    50.0639, 14.4381,
    'Nadprůměrná cena (+12 %)',
    'Nabídka je o 12 % nad průměrnou cenou v lokalitě Nusle (122 000 Kč/m²). Lokalita těží z blízkosti stanice metra C "Vyšehrad" a Nuselského mostu. I přes vyšší cenu zůstává v lokalitě silná poptávka.',
    'This listing is priced 12% above the average for Nusle (122 000 CZK/m²). The location benefits from its proximity to Vyšehrad metro station (Line C) and the Nuselský Bridge. Despite the higher price, demand in the area remains strong.'
),
(
    'Byt 3+1 v klidné lokalitě, Neklanova',
    'Apartment 3+1 in a quiet location, Neklanova',
    'Vyšehrad',
    11275000,
    81.9,
    50.0643, 14.4185,
    'Pod tržní cenou (-7 %)',
    'AI model porovnal 35 srovnatelných nabídek v lokalitě Vyšehrad za posledních 45 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 7 % oproti průměru 148 000 Kč/m². Lokalita těží z blízkosti pevnosti a parku Vyšehrad. Doporučujeme rychlé jednání, podobné nabídky mizí z trhu během několika týdnů.',
    'The AI model compared 35 similar listings in Vyšehrad over the last 45 days and found this property undervalued by 7% versus the area average of 148 000 CZK/m². The location benefits from its proximity to the Vyšehrad fortress and park. We recommend acting quickly — comparable listings tend to sell within a few weeks.'
),
(
    'Útulný byt 1+kk, Neklanova',
    'Cozy apartment 1+kk, Neklanova',
    'Vyšehrad',
    4610000,
    29.4,
    50.0626, 14.4155,
    'Nadprůměrná cena (+6 %)',
    'Nabídka je o 6 % nad průměrnou cenou v lokalitě Vyšehrad (148 000 Kč/m²). Lokalita těží z blízkosti pevnosti a parku Vyšehrad. Cena je vyšší než srovnatelné nabídky, kupující by měl zvážit vyjednávání.',
    'This listing is priced 6% above the average for Vyšehrad (148 000 CZK/m²). The location benefits from its proximity to the Vyšehrad fortress and park. The price is higher than comparable listings; buyers should consider negotiating.'
),
(
    'Byt 1+kk s balkonem, Na Podkovce',
    'Apartment 1+kk with balcony, Na Podkovce',
    'Podolí',
    4930000,
    35.1,
    50.0562, 14.4158,
    'Nadprůměrná cena (+4 %)',
    'Nabídka je o 4 % nad průměrnou cenou v lokalitě Podolí (135 000 Kč/m²). Lokalita těží z blízkosti podolského nábřeží a plaveckého stadionu. Cena je vyšší než srovnatelné nabídky, kupující by měl zvážit vyjednávání.',
    'This listing is priced 4% above the average for Podolí (135 000 CZK/m²). The location benefits from its proximity to the Podolí riverside promenade and swimming stadium. The price is higher than comparable listings; buyers should consider negotiating.'
),
(
    'Světlý byt 5+kk mezonet po rekonstrukci, Podolské nábřeží',
    'Bright, recently renovated apartment 5+kk duplex, Podolské nábřeží',
    'Podolí',
    18925000,
    140.2,
    50.0586, 14.4149,
    'Tržní cena',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Podolí (135 000 Kč/m²). Lokalita těží z blízkosti podolského nábřeží a plaveckého stadionu. Nabídka odpovídá standardnímu tržnímu standardu v této části Prahy.',
    'The price matches the current market average for Podolí (135 000 CZK/m²). The location benefits from its proximity to the Podolí riverside promenade and swimming stadium. The listing matches the standard market rate for this part of Prague.'
),
(
    'Zrekonstruovaný byt 3+1, U Ledáren',
    'Renovated apartment 3+1, U Ledáren',
    'Braník',
    7420000,
    72.0,
    50.0357, 14.4178,
    'Pod tržní cenou (-8 %)',
    'AI model porovnal 34 srovnatelných nabídek v lokalitě Braník za posledních 30 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 8 % oproti průměru 112 000 Kč/m². Lokalita těží z blízkosti klidné okrajové části při řece. Vzhledem k lokalitě a ceně jde o nadprůměrně likvidní investici.',
    'The AI model compared 34 similar listings in Braník over the last 30 days and found this property undervalued by 8% versus the area average of 112 000 CZK/m². The location benefits from its proximity to a quiet riverside neighborhood on the edge of the city. Given the location and price, this is an above-average liquid investment.'
),
(
    'Cihlový byt 3+kk, Branická',
    'Brick apartment 3+kk, Branická',
    'Braník',
    6835000,
    74.4,
    50.0318, 14.4134,
    'Skvělá nabídka (-18 %)',
    'AI model porovnal 36 srovnatelných nabídek v lokalitě Braník za posledních 90 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 18 % oproti průměru 112 000 Kč/m². Lokalita těží z blízkosti klidné okrajové části při řece. Doporučujeme rychlé jednání, podobné nabídky mizí z trhu během několika týdnů.',
    'The AI model compared 36 similar listings in Braník over the last 90 days and found this property undervalued by 18% versus the area average of 112 000 CZK/m². The location benefits from its proximity to a quiet riverside neighborhood on the edge of the city. We recommend acting quickly — comparable listings tend to sell within a few weeks.'
),
(
    'Světlý byt 2+1 po rekonstrukci, Krčská',
    'Bright, recently renovated apartment 2+1, Krčská',
    'Krč',
    5085000,
    51.0,
    50.0358, 14.4436,
    'Pod tržní cenou (-5 %)',
    'AI model porovnal 34 srovnatelných nabídek v lokalitě Krč za posledních 30 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 5 % oproti průměru 105 000 Kč/m². Lokalita těží z blízkosti stanice metra C "Kačerov" a Krčského lesa. Poměr cena/lokalita je u této nabídky výrazně nadprůměrný.',
    'The AI model compared 34 similar listings in Krč over the last 30 days and found this property undervalued by 5% versus the area average of 105 000 CZK/m². The location benefits from its proximity to Kačerov metro station (Line C) and Krč forest. The price-to-location ratio for this listing is well above average.'
),
(
    'Prostorný byt Garsoniéra, Krčská',
    'Spacious apartment Studio, Krčská',
    'Krč',
    3330000,
    31.7,
    50.0326, 14.4398,
    'Tržní cena',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Krč (105 000 Kč/m²). Lokalita těží z blízkosti stanice metra C "Kačerov" a Krčského lesa. Model neočekává výrazný pohyb ceny v následujících měsících.',
    'The price matches the current market average for Krč (105 000 CZK/m²). The location benefits from its proximity to Kačerov metro station (Line C) and Krč forest. The model does not expect a significant price move in the coming months.'
),
(
    'Novostavba, byt 3+1, Choceradská',
    'New building, apartment 3+1, Choceradská',
    'Krč',
    7100000,
    65.0,
    50.0367, 14.4429,
    'Nadprůměrná cena (+4 %)',
    'Nabídka je o 4 % nad průměrnou cenou v lokalitě Krč (105 000 Kč/m²). Lokalita těží z blízkosti stanice metra C "Kačerov" a Krčského lesa. Prémiová cena je částečně vyvážena kvalitou provedení a vybavením.',
    'This listing is priced 4% above the average for Krč (105 000 CZK/m²). The location benefits from its proximity to Kačerov metro station (Line C) and Krč forest. The premium price is partly offset by the quality of finish and fittings.'
),
(
    'Zrekonstruovaný byt 1+1, Plzeňská',
    'Renovated apartment 1+1, Plzeňská',
    'Košíře',
    2965000,
    31.9,
    50.0686, 14.3724,
    'Skvělá nabídka (-14 %)',
    'AI model porovnal 48 srovnatelných nabídek v lokalitě Košíře za posledních 30 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 14 % oproti průměru 108 000 Kč/m². Lokalita těží z blízkosti tramvajové trati směr centrum. Doporučení: velmi zajímavá investiční příležitost.',
    'The AI model compared 48 similar listings in Košíře over the last 30 days and found this property undervalued by 14% versus the area average of 108 000 CZK/m². The location benefits from its proximity to the tram line into the city center. Recommendation: a very attractive investment opportunity.'
),
(
    'Prostorný byt 5+kk mezonet, Musílkova',
    'Spacious apartment 5+kk duplex, Musílkova',
    'Košíře',
    14765000,
    136.7,
    50.0645, 14.3721,
    'Tržní cena',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Košíře (108 000 Kč/m²). Lokalita těží z blízkosti tramvajové trati směr centrum. Cena je adekvátní vzhledem k lokalitě a stavu nemovitosti.',
    'The price matches the current market average for Košíře (108 000 CZK/m²). The location benefits from its proximity to the tram line into the city center. The price is fair given the location and condition of the property.'
),
(
    'Cihlový byt 2+kk, Wolkerova',
    'Brick apartment 2+kk, Wolkerova',
    'Dejvice',
    6450000,
    44.8,
    50.1016, 14.3844,
    'Pod tržní cenou (-4 %)',
    'AI model porovnal 33 srovnatelných nabídek v lokalitě Dejvice za posledních 90 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 4 % oproti průměru 150 000 Kč/m². Lokalita těží z blízkosti stanice metra A "Dejvická" a univerzitního kampusu ČVUT. Poměr cena/lokalita je u této nabídky výrazně nadprůměrný.',
    'The AI model compared 33 similar listings in Dejvice over the last 90 days and found this property undervalued by 4% versus the area average of 150 000 CZK/m². The location benefits from its proximity to Dejvická metro station (Line A) and the CTU university campus. The price-to-location ratio for this listing is well above average.'
),
(
    'Cihlový byt 5+kk mezonet, Šolínova',
    'Brick apartment 5+kk duplex, Šolínova',
    'Dejvice',
    22820000,
    138.3,
    50.1024, 14.3871,
    'Nadprůměrná cena (+10 %)',
    'Nabídka je o 10 % nad průměrnou cenou v lokalitě Dejvice (150 000 Kč/m²). Lokalita těží z blízkosti stanice metra A "Dejvická" a univerzitního kampusu ČVUT. Cena je vyšší než srovnatelné nabídky, kupující by měl zvážit vyjednávání.',
    'This listing is priced 10% above the average for Dejvice (150 000 CZK/m²). The location benefits from its proximity to Dejvická metro station (Line A) and the CTU university campus. The price is higher than comparable listings; buyers should consider negotiating.'
),
(
    'Zrekonstruovaný byt 2+1, Jugoslávských partyzánů',
    'Renovated apartment 2+1, Jugoslávských partyzánů',
    'Dejvice',
    6720000,
    50.9,
    50.1007, 14.394,
    'Skvělá nabídka (-12 %)',
    'AI model porovnal 34 srovnatelných nabídek v lokalitě Dejvice za posledních 30 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 12 % oproti průměru 150 000 Kč/m². Lokalita těží z blízkosti stanice metra A "Dejvická" a univerzitního kampusu ČVUT. Poměr cena/lokalita je u této nabídky výrazně nadprůměrný.',
    'The AI model compared 34 similar listings in Dejvice over the last 30 days and found this property undervalued by 12% versus the area average of 150 000 CZK/m². The location benefits from its proximity to Dejvická metro station (Line A) and the CTU university campus. The price-to-location ratio for this listing is well above average.'
),
(
    'Byt 2+kk v klidné lokalitě, Nad Královskou oborou',
    'Apartment 2+kk in a quiet location, Nad Královskou oborou',
    'Bubeneč',
    6645000,
    46.1,
    50.104, 14.4128,
    'Pod tržní cenou (-7 %)',
    'AI model porovnal 51 srovnatelných nabídek v lokalitě Bubeneč za posledních 60 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 7 % oproti průměru 155 000 Kč/m². Lokalita těží z blízkosti parku Stromovka. Doporučujeme rychlé jednání, podobné nabídky mizí z trhu během několika týdnů.',
    'The AI model compared 51 similar listings in Bubeneč over the last 60 days and found this property undervalued by 7% versus the area average of 155 000 CZK/m². The location benefits from its proximity to Stromovka park. We recommend acting quickly — comparable listings tend to sell within a few weeks.'
),
(
    'Novostavba, byt 4+kk, Terronská',
    'New building, apartment 4+kk, Terronská',
    'Bubeneč',
    12925000,
    101.7,
    50.1019, 14.4139,
    'Skvělá nabídka (-18 %)',
    'AI model porovnal 69 srovnatelných nabídek v lokalitě Bubeneč za posledních 30 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 18 % oproti průměru 155 000 Kč/m². Lokalita těží z blízkosti parku Stromovka. Poměr cena/lokalita je u této nabídky výrazně nadprůměrný.',
    'The AI model compared 69 similar listings in Bubeneč over the last 30 days and found this property undervalued by 18% versus the area average of 155 000 CZK/m². The location benefits from its proximity to Stromovka park. The price-to-location ratio for this listing is well above average.'
),
(
    'Prostorný byt 2+1, Bělohorská',
    'Spacious apartment 2+1, Bělohorská',
    'Břevnov',
    6875000,
    57.1,
    50.0831, 14.3669,
    'Nadprůměrná cena (+2 %)',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Břevnov (118 000 Kč/m²). Lokalita těží z blízkosti Břevnovského kláštera a tramvajové trati. Nabídka odpovídá standardnímu tržnímu standardu v této části Prahy.',
    'The price matches the current market average for Břevnov (118 000 CZK/m²). The location benefits from its proximity to Břevnov Monastery and the tram line. The listing matches the standard market rate for this part of Prague.'
),
(
    'Byt 2+1 v klidné lokalitě, Loretánská',
    'Apartment 2+1 in a quiet location, Loretánská',
    'Břevnov',
    6430000,
    52.9,
    50.0826, 14.3643,
    'Nadprůměrná cena (+3 %)',
    'Nabídka je o 3 % nad průměrnou cenou v lokalitě Břevnov (118 000 Kč/m²). Lokalita těží z blízkosti Břevnovského kláštera a tramvajové trati. I přes vyšší cenu zůstává v lokalitě silná poptávka.',
    'This listing is priced 3% above the average for Břevnov (118 000 CZK/m²). The location benefits from its proximity to Břevnov Monastery and the tram line. Despite the higher price, demand in the area remains strong.'
),
(
    'Novostavba, byt Garsoniéra, Jateční',
    'New building, apartment Studio, Jateční',
    'Holešovice',
    3365000,
    22.9,
    50.0974, 14.4373,
    'Nadprůměrná cena (+5 %)',
    'Nabídka je o 5 % nad průměrnou cenou v lokalitě Holešovice (140 000 Kč/m²). Lokalita těží z blízkosti stanice metra C "Vltavská" a Výstaviště. Cena je vyšší než srovnatelné nabídky, kupující by měl zvážit vyjednávání.',
    'This listing is priced 5% above the average for Holešovice (140 000 CZK/m²). The location benefits from its proximity to Vltavská metro station (Line C) and the Výstaviště exhibition grounds. The price is higher than comparable listings; buyers should consider negotiating.'
),
(
    'Útulný byt 4+kk, Jateční',
    'Cozy apartment 4+kk, Jateční',
    'Holešovice',
    11560000,
    96.0,
    50.0971, 14.4348,
    'Skvělá nabídka (-14 %)',
    'AI model porovnal 72 srovnatelných nabídek v lokalitě Holešovice za posledních 45 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 14 % oproti průměru 140 000 Kč/m². Lokalita těží z blízkosti stanice metra C "Vltavská" a Výstaviště. Poměr cena/lokalita je u této nabídky výrazně nadprůměrný.',
    'The AI model compared 72 similar listings in Holešovice over the last 45 days and found this property undervalued by 14% versus the area average of 140 000 CZK/m². The location benefits from its proximity to Vltavská metro station (Line C) and the Výstaviště exhibition grounds. The price-to-location ratio for this listing is well above average.'
),
(
    'Útulný byt Garsoniéra, Ortenovo náměstí',
    'Cozy apartment Studio, Ortenovo náměstí',
    'Holešovice',
    4240000,
    30.3,
    50.0982, 14.4353,
    'Tržní cena',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Holešovice (140 000 Kč/m²). Lokalita těží z blízkosti stanice metra C "Vltavská" a Výstaviště. Cena je adekvátní vzhledem k lokalitě a stavu nemovitosti.',
    'The price matches the current market average for Holešovice (140 000 CZK/m²). The location benefits from its proximity to Vltavská metro station (Line C) and the Výstaviště exhibition grounds. The price is fair given the location and condition of the property.'
),
(
    'Byt 3+kk s balkonem, Milady Horákové',
    'Apartment 3+kk with balcony, Milady Horákové',
    'Letná',
    9115000,
    63.8,
    50.0958, 14.4166,
    'Pod tržní cenou (-6 %)',
    'AI model porovnal 54 srovnatelných nabídek v lokalitě Letná za posledních 45 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 6 % oproti průměru 152 000 Kč/m². Lokalita těží z blízkosti Letenského parku s výhledem na Vltavu. Doporučujeme rychlé jednání, podobné nabídky mizí z trhu během několika týdnů.',
    'The AI model compared 54 similar listings in Letná over the last 45 days and found this property undervalued by 6% versus the area average of 152 000 CZK/m². The location benefits from its proximity to Letná park with views over the Vltava river. We recommend acting quickly — comparable listings tend to sell within a few weeks.'
),
(
    'Byt 1+1 s výhledem, Milady Horákové',
    'Apartment 1+1 with a view, Milady Horákové',
    'Letná',
    5870000,
    39.8,
    50.0932, 14.4184,
    'Pod tržní cenou (-3 %)',
    'AI model porovnal 49 srovnatelných nabídek v lokalitě Letná za posledních 90 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 3 % oproti průměru 152 000 Kč/m². Lokalita těží z blízkosti Letenského parku s výhledem na Vltavu. Doporučujeme rychlé jednání, podobné nabídky mizí z trhu během několika týdnů.',
    'The AI model compared 49 similar listings in Letná over the last 90 days and found this property undervalued by 3% versus the area average of 152 000 CZK/m². The location benefits from its proximity to Letná park with views over the Vltava river. We recommend acting quickly — comparable listings tend to sell within a few weeks.'
),
(
    'Byt 2+1 s balkonem, U Balabenky',
    'Apartment 2+1 with balcony, U Balabenky',
    'Libeň',
    5490000,
    47.1,
    50.1071, 14.4604,
    'Nadprůměrná cena (+6 %)',
    'Nabídka je o 6 % nad průměrnou cenou v lokalitě Libeň (110 000 Kč/m²). Lokalita těží z blízkosti stanice metra B "Palmovka". Cena je vyšší než srovnatelné nabídky, kupující by měl zvážit vyjednávání.',
    'This listing is priced 6% above the average for Libeň (110 000 CZK/m²). The location benefits from its proximity to Palmovka metro station (Line B). The price is higher than comparable listings; buyers should consider negotiating.'
),
(
    'Cihlový byt 4+kk, Zenklova',
    'Brick apartment 4+kk, Zenklova',
    'Libeň',
    9210000,
    92.0,
    50.1042, 14.4619,
    'Pod tržní cenou (-9 %)',
    'AI model porovnal 49 srovnatelných nabídek v lokalitě Libeň za posledních 60 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 9 % oproti průměru 110 000 Kč/m². Lokalita těží z blízkosti stanice metra B "Palmovka". Doporučení: velmi zajímavá investiční příležitost.',
    'The AI model compared 49 similar listings in Libeň over the last 60 days and found this property undervalued by 9% versus the area average of 110 000 CZK/m². The location benefits from its proximity to Palmovka metro station (Line B). Recommendation: a very attractive investment opportunity.'
),
(
    'Byt 2+1 s výhledem, U Balabenky',
    'Apartment 2+1 with a view, U Balabenky',
    'Libeň',
    5785000,
    49.6,
    50.1094, 14.4684,
    'Nadprůměrná cena (+6 %)',
    'Nabídka je o 6 % nad průměrnou cenou v lokalitě Libeň (110 000 Kč/m²). Lokalita těží z blízkosti stanice metra B "Palmovka". Model doporučuje před koupí individuální posouzení technického stavu.',
    'This listing is priced 6% above the average for Libeň (110 000 CZK/m²). The location benefits from its proximity to Palmovka metro station (Line B). The model recommends an individual technical inspection before purchase.'
),
(
    'Zrekonstruovaný byt 2+1, Kolbenova',
    'Renovated apartment 2+1, Kolbenova',
    'Vysočany',
    5160000,
    47.3,
    50.1099, 14.4863,
    'Nadprůměrná cena (+7 %)',
    'Nabídka je o 7 % nad průměrnou cenou v lokalitě Vysočany (102 000 Kč/m²). Lokalita těží z blízkosti stanice metra B "Vysočanská" a nové výstavby v okolí. Prémiová cena je částečně vyvážena kvalitou provedení a vybavením.',
    'This listing is priced 7% above the average for Vysočany (102 000 CZK/m²). The location benefits from its proximity to Vysočanská metro station (Line B) and new developments nearby. The premium price is partly offset by the quality of finish and fittings.'
),
(
    'Byt 5+kk mezonet s výhledem, Freyova',
    'Apartment 5+kk duplex with a view, Freyova',
    'Vysočany',
    14175000,
    154.4,
    50.1162, 14.4839,
    'Pod tržní cenou (-10 %)',
    'AI model porovnal 30 srovnatelných nabídek v lokalitě Vysočany za posledních 90 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 10 % oproti průměru 102 000 Kč/m². Lokalita těží z blízkosti stanice metra B "Vysočanská" a nové výstavby v okolí. Doporučení: velmi zajímavá investiční příležitost.',
    'The AI model compared 30 similar listings in Vysočany over the last 90 days and found this property undervalued by 10% versus the area average of 102 000 CZK/m². The location benefits from its proximity to Vysočanská metro station (Line B) and new developments nearby. Recommendation: a very attractive investment opportunity.'
),
(
    'Cihlový byt 4+1, Poděbradská',
    'Brick apartment 4+1, Poděbradská',
    'Vysočany',
    9850000,
    108.5,
    50.1119, 14.4827,
    'Pod tržní cenou (-11 %)',
    'AI model porovnal 70 srovnatelných nabídek v lokalitě Vysočany za posledních 60 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 11 % oproti průměru 102 000 Kč/m². Lokalita těží z blízkosti stanice metra B "Vysočanská" a nové výstavby v okolí. Poměr cena/lokalita je u této nabídky výrazně nadprůměrný.',
    'The AI model compared 70 similar listings in Vysočany over the last 60 days and found this property undervalued by 11% versus the area average of 102 000 CZK/m². The location benefits from its proximity to Vysočanská metro station (Line B) and new developments nearby. The price-to-location ratio for this listing is well above average.'
);

-- 6c. Price history seed data — 5 points per listing (~8 months
--     back to today), the source for each card's sparkline. The
--     most recent point always matches that listing's current price.
insert into public.price_history (property_id, price, recorded_at)
values
(1, 9763000, '2026-01-23'),
(1, 9734000, '2026-03-23'),
(1, 9455000, '2026-05-23'),
(1, 9414000, '2026-07-23'),
(1, 9260000, '2026-09-23'),
(2, 7411000, '2026-01-23'),
(2, 7479000, '2026-03-23'),
(2, 7382000, '2026-05-23'),
(2, 7441000, '2026-07-23'),
(2, 7440000, '2026-09-23'),
(3, 5453000, '2026-01-23'),
(3, 5557000, '2026-03-23'),
(3, 5672000, '2026-05-23'),
(3, 5638000, '2026-07-23'),
(3, 5750000, '2026-09-23'),
(4, 11667000, '2026-01-23'),
(4, 11599000, '2026-03-23'),
(4, 11341000, '2026-05-23'),
(4, 11138000, '2026-07-23'),
(4, 11010000, '2026-09-23'),
(5, 9058000, '2026-01-23'),
(5, 9009000, '2026-03-23'),
(5, 8662000, '2026-05-23'),
(5, 8408000, '2026-07-23'),
(5, 8255000, '2026-09-23'),
(6, 16034000, '2026-01-23'),
(6, 16152000, '2026-03-23'),
(6, 15832000, '2026-05-23'),
(6, 15908000, '2026-07-23'),
(6, 15800000, '2026-09-23'),
(7, 4581000, '2026-01-23'),
(7, 4690000, '2026-03-23'),
(7, 4725000, '2026-05-23'),
(7, 4814000, '2026-07-23'),
(7, 4955000, '2026-09-23'),
(8, 7880000, '2026-01-23'),
(8, 7730000, '2026-03-23'),
(8, 7606000, '2026-05-23'),
(8, 7553000, '2026-07-23'),
(8, 7435000, '2026-09-23'),
(9, 7900000, '2026-01-23'),
(9, 7990000, '2026-03-23'),
(9, 7967000, '2026-05-23'),
(9, 7876000, '2026-07-23'),
(9, 7920000, '2026-09-23'),
(10, 11946000, '2026-01-23'),
(10, 11822000, '2026-03-23'),
(10, 11558000, '2026-05-23'),
(10, 11215000, '2026-07-23'),
(10, 11050000, '2026-09-23'),
(12, 29081000, '2026-01-23'),
(12, 30016000, '2026-03-23'),
(12, 30990000, '2026-05-23'),
(12, 31262000, '2026-07-23'),
(12, 32250000, '2026-09-23'),
(13, 5150000, '2026-01-23'),
(13, 5228000, '2026-03-23'),
(13, 5239000, '2026-05-23'),
(13, 5215000, '2026-07-23'),
(13, 5205000, '2026-09-23'),
(14, 19377000, '2026-01-23'),
(14, 20008000, '2026-03-23'),
(14, 20411000, '2026-05-23'),
(14, 20855000, '2026-07-23'),
(14, 21265000, '2026-09-23'),
(15, 24097000, '2026-01-23'),
(15, 24144000, '2026-03-23'),
(15, 23861000, '2026-05-23'),
(15, 23957000, '2026-07-23'),
(15, 23850000, '2026-09-23'),
(16, 6930000, '2026-01-23'),
(16, 6883000, '2026-03-23'),
(16, 6901000, '2026-05-23'),
(16, 6835000, '2026-07-23'),
(16, 6745000, '2026-09-23'),
(17, 5727000, '2026-01-23'),
(17, 5848000, '2026-03-23'),
(17, 5838000, '2026-05-23'),
(17, 5983000, '2026-07-23'),
(17, 6070000, '2026-09-23'),
(18, 17777000, '2026-01-23'),
(18, 17974000, '2026-03-23'),
(18, 18509000, '2026-05-23'),
(18, 18450000, '2026-07-23'),
(18, 18840000, '2026-09-23'),
(19, 18794000, '2026-01-23'),
(19, 18751000, '2026-03-23'),
(19, 18142000, '2026-05-23'),
(19, 18046000, '2026-07-23'),
(19, 17810000, '2026-09-23'),
(20, 8451000, '2026-01-23'),
(20, 8444000, '2026-03-23'),
(20, 8458000, '2026-05-23'),
(20, 8345000, '2026-07-23'),
(20, 8395000, '2026-09-23'),
(21, 5713000, '2026-01-23'),
(21, 5691000, '2026-03-23'),
(21, 5607000, '2026-05-23'),
(21, 5407000, '2026-07-23'),
(21, 5360000, '2026-09-23'),
(22, 13425000, '2026-01-23'),
(22, 13595000, '2026-03-23'),
(22, 13848000, '2026-05-23'),
(22, 14054000, '2026-07-23'),
(22, 14195000, '2026-09-23'),
(23, 11799000, '2026-01-23'),
(23, 11752000, '2026-03-23'),
(23, 11572000, '2026-05-23'),
(23, 11460000, '2026-07-23'),
(23, 11275000, '2026-09-23'),
(24, 4221000, '2026-01-23'),
(24, 4305000, '2026-03-23'),
(24, 4418000, '2026-05-23'),
(24, 4527000, '2026-07-23'),
(24, 4610000, '2026-09-23'),
(25, 4771000, '2026-01-23'),
(25, 4809000, '2026-03-23'),
(25, 4871000, '2026-05-23'),
(25, 4914000, '2026-07-23'),
(25, 4930000, '2026-09-23'),
(26, 18981000, '2026-01-23'),
(26, 18821000, '2026-03-23'),
(26, 19037000, '2026-05-23'),
(26, 18752000, '2026-07-23'),
(26, 18925000, '2026-09-23'),
(27, 7708000, '2026-01-23'),
(27, 7614000, '2026-03-23'),
(27, 7562000, '2026-05-23'),
(27, 7425000, '2026-07-23'),
(27, 7420000, '2026-09-23'),
(28, 7060000, '2026-01-23'),
(28, 6981000, '2026-03-23'),
(28, 6955000, '2026-05-23'),
(28, 6828000, '2026-07-23'),
(28, 6835000, '2026-09-23'),
(29, 5618000, '2026-01-23'),
(29, 5427000, '2026-03-23'),
(29, 5312000, '2026-05-23'),
(29, 5195000, '2026-07-23'),
(29, 5085000, '2026-09-23'),
(30, 3322000, '2026-01-23'),
(30, 3375000, '2026-03-23'),
(30, 3381000, '2026-05-23'),
(30, 3333000, '2026-07-23'),
(30, 3330000, '2026-09-23'),
(31, 6576000, '2026-01-23'),
(31, 6692000, '2026-03-23'),
(31, 6845000, '2026-05-23'),
(31, 6946000, '2026-07-23'),
(31, 7100000, '2026-09-23'),
(32, 3231000, '2026-01-23'),
(32, 3148000, '2026-03-23'),
(32, 3145000, '2026-05-23'),
(32, 3040000, '2026-07-23'),
(32, 2965000, '2026-09-23'),
(33, 15046000, '2026-01-23'),
(33, 14794000, '2026-03-23'),
(33, 14908000, '2026-05-23'),
(33, 15002000, '2026-07-23'),
(33, 14765000, '2026-09-23'),
(34, 7135000, '2026-01-23'),
(34, 6899000, '2026-03-23'),
(34, 6754000, '2026-05-23'),
(34, 6560000, '2026-07-23'),
(34, 6450000, '2026-09-23'),
(35, 21023000, '2026-01-23'),
(35, 21604000, '2026-03-23'),
(35, 21824000, '2026-05-23'),
(35, 22218000, '2026-07-23'),
(35, 22820000, '2026-09-23'),
(36, 7460000, '2026-01-23'),
(36, 7272000, '2026-03-23'),
(36, 7099000, '2026-05-23'),
(36, 6936000, '2026-07-23'),
(36, 6720000, '2026-09-23'),
(37, 7210000, '2026-01-23'),
(37, 7107000, '2026-03-23'),
(37, 6927000, '2026-05-23'),
(37, 6721000, '2026-07-23'),
(37, 6645000, '2026-09-23'),
(38, 13416000, '2026-01-23'),
(38, 13269000, '2026-03-23'),
(38, 13267000, '2026-05-23'),
(38, 13209000, '2026-07-23'),
(38, 12925000, '2026-09-23'),
(39, 6965000, '2026-01-23'),
(39, 6969000, '2026-03-23'),
(39, 6959000, '2026-05-23'),
(39, 6857000, '2026-07-23'),
(39, 6875000, '2026-09-23'),
(40, 6065000, '2026-01-23'),
(40, 6141000, '2026-03-23'),
(40, 6223000, '2026-05-23'),
(40, 6368000, '2026-07-23'),
(40, 6430000, '2026-09-23'),
(41, 3101000, '2026-01-23'),
(41, 3147000, '2026-03-23'),
(41, 3232000, '2026-05-23'),
(41, 3316000, '2026-07-23'),
(41, 3365000, '2026-09-23'),
(42, 12152000, '2026-01-23'),
(42, 12087000, '2026-03-23'),
(42, 11913000, '2026-05-23'),
(42, 11767000, '2026-07-23'),
(42, 11560000, '2026-09-23'),
(43, 4212000, '2026-01-23'),
(43, 4273000, '2026-03-23'),
(43, 4225000, '2026-05-23'),
(43, 4272000, '2026-07-23'),
(43, 4240000, '2026-09-23'),
(44, 10083000, '2026-01-23'),
(44, 9837000, '2026-03-23'),
(44, 9715000, '2026-05-23'),
(44, 9414000, '2026-07-23'),
(44, 9115000, '2026-09-23'),
(45, 6125000, '2026-01-23'),
(45, 6052000, '2026-03-23'),
(45, 6084000, '2026-05-23'),
(45, 5991000, '2026-07-23'),
(45, 5870000, '2026-09-23'),
(46, 5276000, '2026-01-23'),
(46, 5360000, '2026-03-23'),
(46, 5383000, '2026-05-23'),
(46, 5407000, '2026-07-23'),
(46, 5490000, '2026-09-23'),
(47, 9846000, '2026-01-23'),
(47, 9640000, '2026-03-23'),
(47, 9680000, '2026-05-23'),
(47, 9425000, '2026-07-23'),
(47, 9210000, '2026-09-23'),
(48, 5455000, '2026-01-23'),
(48, 5486000, '2026-03-23'),
(48, 5642000, '2026-05-23'),
(48, 5733000, '2026-07-23'),
(48, 5785000, '2026-09-23'),
(49, 4873000, '2026-01-23'),
(49, 4942000, '2026-03-23'),
(49, 5000000, '2026-05-23'),
(49, 5106000, '2026-07-23'),
(49, 5160000, '2026-09-23'),
(50, 14980000, '2026-01-23'),
(50, 14669000, '2026-03-23'),
(50, 14736000, '2026-05-23'),
(50, 14333000, '2026-07-23'),
(50, 14175000, '2026-09-23'),
(51, 10584000, '2026-01-23'),
(51, 10485000, '2026-03-23'),
(51, 10187000, '2026-05-23'),
(51, 10129000, '2026-07-23'),
(51, 9850000, '2026-09-23');

-- --------------------------------------------------------------
-- 7. Quick sanity checks (optional — run separately if you like)
-- --------------------------------------------------------------
-- select title, district, price, area_sqm, price_per_sqm, deal_rating
-- from public.properties
-- order by district, price;

-- Example bounding-box query covering roughly all of central Prague:
-- select title, district from public.properties_in_bbox(14.35, 50.03, 14.55, 50.13);
