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

-- 6b. Additional 40 listings spread across the rest of Prague
--     (Staré Město, Nové Město, Malá Strana, Nusle, Vyšehrad, Podolí,
--      Braník, Krč, Košíře, Dejvice, Bubeneč, Břevnov, Holešovice,
--      Letná, Libeň, Vysočany) — 20 districts and 50 listings total.
insert into public.properties
    (title, district, price, area_sqm, lat, lng, deal_rating, ai_summary)
values
(
    'Cihlový byt 5+kk mezonet, Kožná',
    'Staré Město',
    32250000,
    142.2,
    50.0848, 14.4201,
    'Nadprůměrná cena (+8 %)',
    'Nabídka je o 8 % nad průměrnou cenou v lokalitě Staré Město (210 000 Kč/m²). Lokalita těží z blízkosti stanice metra A "Staroměstská". I přes vyšší cenu zůstává v lokalitě silná poptávka.'
),
(
    'Byt Garsoniéra v klidné lokalitě, Dlouhá',
    'Staré Město',
    5205000,
    24.3,
    50.0867, 14.417,
    'Nadprůměrná cena (+2 %)',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Staré Město (210 000 Kč/m²). Lokalita těží z blízkosti stanice metra A "Staroměstská". Model neočekává výrazný pohyb ceny v následujících měsících.'
),
(
    'Světlý byt 4+kk po rekonstrukci, Kožná',
    'Staré Město',
    21265000,
    92.9,
    50.0846, 14.4177,
    'Nadprůměrná cena (+9 %)',
    'Nabídka je o 9 % nad průměrnou cenou v lokalitě Staré Město (210 000 Kč/m²). Lokalita těží z blízkosti stanice metra A "Staroměstská". Prémiová cena je částečně vyvážena kvalitou provedení a vybavením.'
),
(
    'Prostorný byt 5+kk mezonet, Ječná',
    'Nové Město',
    23850000,
    134.0,
    50.0809, 14.4224,
    'Tržní cena',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Nové Město (178 000 Kč/m²). Lokalita těží z blízkosti stanic metra "Můstek" a "Národní třída". Model neočekává výrazný pohyb ceny v následujících měsících.'
),
(
    'Byt 1+1 s terasou, Štěpánská',
    'Nové Město',
    6745000,
    37.9,
    50.0773, 14.4253,
    'Tržní cena',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Nové Město (178 000 Kč/m²). Lokalita těží z blízkosti stanic metra "Můstek" a "Národní třída". Cena je adekvátní vzhledem k lokalitě a stavu nemovitosti.'
),
(
    'Novostavba, byt 1+kk, Sokolská',
    'Nové Město',
    6070000,
    32.8,
    50.0829, 14.4249,
    'Nadprůměrná cena (+4 %)',
    'Nabídka je o 4 % nad průměrnou cenou v lokalitě Nové Město (178 000 Kč/m²). Lokalita těží z blízkosti stanic metra "Můstek" a "Národní třída". Cena je vyšší než srovnatelné nabídky, kupující by měl zvážit vyjednávání.'
),
(
    'Novostavba, byt 4+kk, Míšeňská',
    'Malá Strana',
    18840000,
    85.1,
    50.0903, 14.406,
    'Nadprůměrná cena (+8 %)',
    'Nabídka je o 8 % nad průměrnou cenou v lokalitě Malá Strana (205 000 Kč/m²). Lokalita těží z blízkosti stanice metra A "Malostranská". I přes vyšší cenu zůstává v lokalitě silná poptávka.'
),
(
    'Byt 4+1 v klidné lokalitě, Nerudova',
    'Malá Strana',
    17810000,
    102.2,
    50.0886, 14.4038,
    'Skvělá nabídka (-15 %)',
    'AI model porovnal 61 srovnatelných nabídek v lokalitě Malá Strana za posledních 30 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 15 % oproti průměru 205 000 Kč/m². Lokalita těží z blízkosti stanice metra A "Malostranská". Poměr cena/lokalita je u této nabídky výrazně nadprůměrný.'
),
(
    'Byt 3+kk v klidné lokalitě, Táborská',
    'Nusle',
    8395000,
    68.8,
    50.0667, 14.4403,
    'Tržní cena',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Nusle (122 000 Kč/m²). Lokalita těží z blízkosti stanice metra C "Vyšehrad" a Nuselského mostu. Cena je adekvátní vzhledem k lokalitě a stavu nemovitosti.'
),
(
    'Byt 2+kk s balkonem, Táborská',
    'Nusle',
    5360000,
    50.5,
    50.0656, 14.4402,
    'Skvělá nabídka (-13 %)',
    'AI model porovnal 62 srovnatelných nabídek v lokalitě Nusle za posledních 45 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 13 % oproti průměru 122 000 Kč/m². Lokalita těží z blízkosti stanice metra C "Vyšehrad" a Nuselského mostu. Doporučujeme rychlé jednání, podobné nabídky mizí z trhu během několika týdnů.'
),
(
    'Novostavba, byt 4+kk, Táborská',
    'Nusle',
    14195000,
    103.9,
    50.0639, 14.4381,
    'Nadprůměrná cena (+12 %)',
    'Nabídka je o 12 % nad průměrnou cenou v lokalitě Nusle (122 000 Kč/m²). Lokalita těží z blízkosti stanice metra C "Vyšehrad" a Nuselského mostu. I přes vyšší cenu zůstává v lokalitě silná poptávka.'
),
(
    'Byt 3+1 v klidné lokalitě, Neklanova',
    'Vyšehrad',
    11275000,
    81.9,
    50.0643, 14.4185,
    'Pod tržní cenou (-7 %)',
    'AI model porovnal 35 srovnatelných nabídek v lokalitě Vyšehrad za posledních 45 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 7 % oproti průměru 148 000 Kč/m². Lokalita těží z blízkosti pevnosti a parku Vyšehrad. Doporučujeme rychlé jednání, podobné nabídky mizí z trhu během několika týdnů.'
),
(
    'Útulný byt 1+kk, Neklanova',
    'Vyšehrad',
    4610000,
    29.4,
    50.0626, 14.4155,
    'Nadprůměrná cena (+6 %)',
    'Nabídka je o 6 % nad průměrnou cenou v lokalitě Vyšehrad (148 000 Kč/m²). Lokalita těží z blízkosti pevnosti a parku Vyšehrad. Cena je vyšší než srovnatelné nabídky, kupující by měl zvážit vyjednávání.'
),
(
    'Byt 1+kk s balkonem, Na Podkovce',
    'Podolí',
    4930000,
    35.1,
    50.0562, 14.4158,
    'Nadprůměrná cena (+4 %)',
    'Nabídka je o 4 % nad průměrnou cenou v lokalitě Podolí (135 000 Kč/m²). Lokalita těží z blízkosti podolského nábřeží a plaveckého stadionu. Cena je vyšší než srovnatelné nabídky, kupující by měl zvážit vyjednávání.'
),
(
    'Světlý byt 5+kk mezonet po rekonstrukci, Podolské nábřeží',
    'Podolí',
    18925000,
    140.2,
    50.0586, 14.4149,
    'Tržní cena',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Podolí (135 000 Kč/m²). Lokalita těží z blízkosti podolského nábřeží a plaveckého stadionu. Nabídka odpovídá standardnímu tržnímu standardu v této části Prahy.'
),
(
    'Zrekonstruovaný byt 3+1, U Ledáren',
    'Braník',
    7420000,
    72.0,
    50.0357, 14.4178,
    'Pod tržní cenou (-8 %)',
    'AI model porovnal 34 srovnatelných nabídek v lokalitě Braník za posledních 30 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 8 % oproti průměru 112 000 Kč/m². Lokalita těží z blízkosti klidné okrajové části při řece. Vzhledem k lokalitě a ceně jde o nadprůměrně likvidní investici.'
),
(
    'Cihlový byt 3+kk, Branická',
    'Braník',
    6835000,
    74.4,
    50.0318, 14.4134,
    'Skvělá nabídka (-18 %)',
    'AI model porovnal 36 srovnatelných nabídek v lokalitě Braník za posledních 90 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 18 % oproti průměru 112 000 Kč/m². Lokalita těží z blízkosti klidné okrajové části při řece. Doporučujeme rychlé jednání, podobné nabídky mizí z trhu během několika týdnů.'
),
(
    'Světlý byt 2+1 po rekonstrukci, Krčská',
    'Krč',
    5085000,
    51.0,
    50.0358, 14.4436,
    'Pod tržní cenou (-5 %)',
    'AI model porovnal 34 srovnatelných nabídek v lokalitě Krč za posledních 30 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 5 % oproti průměru 105 000 Kč/m². Lokalita těží z blízkosti stanice metra C "Kačerov" a Krčského lesa. Poměr cena/lokalita je u této nabídky výrazně nadprůměrný.'
),
(
    'Prostorný byt Garsoniéra, Krčská',
    'Krč',
    3330000,
    31.7,
    50.0326, 14.4398,
    'Tržní cena',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Krč (105 000 Kč/m²). Lokalita těží z blízkosti stanice metra C "Kačerov" a Krčského lesa. Model neočekává výrazný pohyb ceny v následujících měsících.'
),
(
    'Novostavba, byt 3+1, Choceradská',
    'Krč',
    7100000,
    65.0,
    50.0367, 14.4429,
    'Nadprůměrná cena (+4 %)',
    'Nabídka je o 4 % nad průměrnou cenou v lokalitě Krč (105 000 Kč/m²). Lokalita těží z blízkosti stanice metra C "Kačerov" a Krčského lesa. Prémiová cena je částečně vyvážena kvalitou provedení a vybavením.'
),
(
    'Zrekonstruovaný byt 1+1, Plzeňská',
    'Košíře',
    2965000,
    31.9,
    50.0686, 14.3724,
    'Skvělá nabídka (-14 %)',
    'AI model porovnal 48 srovnatelných nabídek v lokalitě Košíře za posledních 30 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 14 % oproti průměru 108 000 Kč/m². Lokalita těží z blízkosti tramvajové trati směr centrum. Doporučení: velmi zajímavá investiční příležitost.'
),
(
    'Prostorný byt 5+kk mezonet, Musílkova',
    'Košíře',
    14765000,
    136.7,
    50.0645, 14.3721,
    'Tržní cena',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Košíře (108 000 Kč/m²). Lokalita těží z blízkosti tramvajové trati směr centrum. Cena je adekvátní vzhledem k lokalitě a stavu nemovitosti.'
),
(
    'Cihlový byt 2+kk, Wolkerova',
    'Dejvice',
    6450000,
    44.8,
    50.1016, 14.3844,
    'Pod tržní cenou (-4 %)',
    'AI model porovnal 33 srovnatelných nabídek v lokalitě Dejvice za posledních 90 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 4 % oproti průměru 150 000 Kč/m². Lokalita těží z blízkosti stanice metra A "Dejvická" a univerzitního kampusu ČVUT. Poměr cena/lokalita je u této nabídky výrazně nadprůměrný.'
),
(
    'Cihlový byt 5+kk mezonet, Šolínova',
    'Dejvice',
    22820000,
    138.3,
    50.1024, 14.3871,
    'Nadprůměrná cena (+10 %)',
    'Nabídka je o 10 % nad průměrnou cenou v lokalitě Dejvice (150 000 Kč/m²). Lokalita těží z blízkosti stanice metra A "Dejvická" a univerzitního kampusu ČVUT. Cena je vyšší než srovnatelné nabídky, kupující by měl zvážit vyjednávání.'
),
(
    'Zrekonstruovaný byt 2+1, Jugoslávských partyzánů',
    'Dejvice',
    6720000,
    50.9,
    50.1007, 14.394,
    'Skvělá nabídka (-12 %)',
    'AI model porovnal 34 srovnatelných nabídek v lokalitě Dejvice za posledních 30 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 12 % oproti průměru 150 000 Kč/m². Lokalita těží z blízkosti stanice metra A "Dejvická" a univerzitního kampusu ČVUT. Poměr cena/lokalita je u této nabídky výrazně nadprůměrný.'
),
(
    'Byt 2+kk v klidné lokalitě, Nad Královskou oborou',
    'Bubeneč',
    6645000,
    46.1,
    50.104, 14.4128,
    'Pod tržní cenou (-7 %)',
    'AI model porovnal 51 srovnatelných nabídek v lokalitě Bubeneč za posledních 60 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 7 % oproti průměru 155 000 Kč/m². Lokalita těží z blízkosti parku Stromovka. Doporučujeme rychlé jednání, podobné nabídky mizí z trhu během několika týdnů.'
),
(
    'Novostavba, byt 4+kk, Terronská',
    'Bubeneč',
    12925000,
    101.7,
    50.1019, 14.4139,
    'Skvělá nabídka (-18 %)',
    'AI model porovnal 69 srovnatelných nabídek v lokalitě Bubeneč za posledních 30 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 18 % oproti průměru 155 000 Kč/m². Lokalita těží z blízkosti parku Stromovka. Poměr cena/lokalita je u této nabídky výrazně nadprůměrný.'
),
(
    'Prostorný byt 2+1, Bělohorská',
    'Břevnov',
    6875000,
    57.1,
    50.0831, 14.3669,
    'Nadprůměrná cena (+2 %)',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Břevnov (118 000 Kč/m²). Lokalita těží z blízkosti Břevnovského kláštera a tramvajové trati. Nabídka odpovídá standardnímu tržnímu standardu v této části Prahy.'
),
(
    'Byt 2+1 v klidné lokalitě, Loretánská',
    'Břevnov',
    6430000,
    52.9,
    50.0826, 14.3643,
    'Nadprůměrná cena (+3 %)',
    'Nabídka je o 3 % nad průměrnou cenou v lokalitě Břevnov (118 000 Kč/m²). Lokalita těží z blízkosti Břevnovského kláštera a tramvajové trati. I přes vyšší cenu zůstává v lokalitě silná poptávka.'
),
(
    'Novostavba, byt Garsoniéra, Jateční',
    'Holešovice',
    3365000,
    22.9,
    50.0974, 14.4373,
    'Nadprůměrná cena (+5 %)',
    'Nabídka je o 5 % nad průměrnou cenou v lokalitě Holešovice (140 000 Kč/m²). Lokalita těží z blízkosti stanice metra C "Vltavská" a Výstaviště. Cena je vyšší než srovnatelné nabídky, kupující by měl zvážit vyjednávání.'
),
(
    'Útulný byt 4+kk, Jateční',
    'Holešovice',
    11560000,
    96.0,
    50.0971, 14.4348,
    'Skvělá nabídka (-14 %)',
    'AI model porovnal 72 srovnatelných nabídek v lokalitě Holešovice za posledních 45 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 14 % oproti průměru 140 000 Kč/m². Lokalita těží z blízkosti stanice metra C "Vltavská" a Výstaviště. Poměr cena/lokalita je u této nabídky výrazně nadprůměrný.'
),
(
    'Útulný byt Garsoniéra, Ortenovo náměstí',
    'Holešovice',
    4240000,
    30.3,
    50.0982, 14.4353,
    'Tržní cena',
    'Cena odpovídá aktuálnímu tržnímu průměru lokality Holešovice (140 000 Kč/m²). Lokalita těží z blízkosti stanice metra C "Vltavská" a Výstaviště. Cena je adekvátní vzhledem k lokalitě a stavu nemovitosti.'
),
(
    'Byt 3+kk s balkonem, Milady Horákové',
    'Letná',
    9115000,
    63.8,
    50.0958, 14.4166,
    'Pod tržní cenou (-6 %)',
    'AI model porovnal 54 srovnatelných nabídek v lokalitě Letná za posledních 45 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 6 % oproti průměru 152 000 Kč/m². Lokalita těží z blízkosti Letenského parku s výhledem na Vltavu. Doporučujeme rychlé jednání, podobné nabídky mizí z trhu během několika týdnů.'
),
(
    'Byt 1+1 s výhledem, Milady Horákové',
    'Letná',
    5870000,
    39.8,
    50.0932, 14.4184,
    'Pod tržní cenou (-3 %)',
    'AI model porovnal 49 srovnatelných nabídek v lokalitě Letná za posledních 90 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 3 % oproti průměru 152 000 Kč/m². Lokalita těží z blízkosti Letenského parku s výhledem na Vltavu. Doporučujeme rychlé jednání, podobné nabídky mizí z trhu během několika týdnů.'
),
(
    'Byt 2+1 s balkonem, U Balabenky',
    'Libeň',
    5490000,
    47.1,
    50.1071, 14.4604,
    'Nadprůměrná cena (+6 %)',
    'Nabídka je o 6 % nad průměrnou cenou v lokalitě Libeň (110 000 Kč/m²). Lokalita těží z blízkosti stanice metra B "Palmovka". Cena je vyšší než srovnatelné nabídky, kupující by měl zvážit vyjednávání.'
),
(
    'Cihlový byt 4+kk, Zenklova',
    'Libeň',
    9210000,
    92.0,
    50.1042, 14.4619,
    'Pod tržní cenou (-9 %)',
    'AI model porovnal 49 srovnatelných nabídek v lokalitě Libeň za posledních 60 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 9 % oproti průměru 110 000 Kč/m². Lokalita těží z blízkosti stanice metra B "Palmovka". Doporučení: velmi zajímavá investiční příležitost.'
),
(
    'Byt 2+1 s výhledem, U Balabenky',
    'Libeň',
    5785000,
    49.6,
    50.1094, 14.4684,
    'Nadprůměrná cena (+6 %)',
    'Nabídka je o 6 % nad průměrnou cenou v lokalitě Libeň (110 000 Kč/m²). Lokalita těží z blízkosti stanice metra B "Palmovka". Model doporučuje před koupí individuální posouzení technického stavu.'
),
(
    'Zrekonstruovaný byt 2+1, Kolbenova',
    'Vysočany',
    5160000,
    47.3,
    50.1099, 14.4863,
    'Nadprůměrná cena (+7 %)',
    'Nabídka je o 7 % nad průměrnou cenou v lokalitě Vysočany (102 000 Kč/m²). Lokalita těží z blízkosti stanice metra B "Vysočanská" a nové výstavby v okolí. Prémiová cena je částečně vyvážena kvalitou provedení a vybavením.'
),
(
    'Byt 5+kk mezonet s výhledem, Freyova',
    'Vysočany',
    14175000,
    154.4,
    50.1162, 14.4839,
    'Pod tržní cenou (-10 %)',
    'AI model porovnal 30 srovnatelných nabídek v lokalitě Vysočany za posledních 90 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 10 % oproti průměru 102 000 Kč/m². Lokalita těží z blízkosti stanice metra B "Vysočanská" a nové výstavby v okolí. Doporučení: velmi zajímavá investiční příležitost.'
),
(
    'Cihlový byt 4+1, Poděbradská',
    'Vysočany',
    9850000,
    108.5,
    50.1119, 14.4827,
    'Pod tržní cenou (-11 %)',
    'AI model porovnal 70 srovnatelných nabídek v lokalitě Vysočany za posledních 60 dní a vyhodnotil tuto nemovitost jako podhodnocenou o 11 % oproti průměru 102 000 Kč/m². Lokalita těží z blízkosti stanice metra B "Vysočanská" a nové výstavby v okolí. Poměr cena/lokalita je u této nabídky výrazně nadprůměrný.'
);

-- --------------------------------------------------------------
-- 7. Quick sanity checks (optional — run separately if you like)
-- --------------------------------------------------------------
-- select title, district, price, area_sqm, price_per_sqm, deal_rating
-- from public.properties
-- order by district, price;

-- Example bounding-box query covering roughly all of central Prague:
-- select title, district from public.properties_in_bbox(14.35, 50.03, 14.55, 50.13);
