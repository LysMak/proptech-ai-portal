/**
 * Pure, framework-free helper functions shared between the browser app
 * (index.html, loaded as a plain <script>) and the test suite
 * (tests/*.test.js, loaded via Node/Vitest). No DOM, no network, no
 * Supabase/Leaflet — everything here is a plain function of its inputs,
 * which is what makes it worth unit testing on its own.
 */

// dealRating is always the raw Czech DB value (e.g. "Pod tržní cenou
// (-8 %)"); this classifies it purely from the leading +/- sign, so it
// works regardless of which language it's about to be displayed in.
function dealClass(dealRating) {
  if (/-\s?\d/.test(dealRating)) return "deal-good";
  if (/\+\s?\d/.test(dealRating)) return "deal-bad";
  return "deal-neutral";
}

// Pulls the signed percentage out of a deal_rating string, e.g.
// "Pod tržní cenou (-8 %)" -> -8, "Nadprůměrná cena (+6 %)" -> 6,
// "Tržní cena" (no percentage at all) -> null.
function extractDealPct(dealRating) {
  const m = dealRating.match(/([+-]\d+)\s*%/);
  return m ? parseInt(m[1], 10) : null;
}

// Builds the display label for a deal_rating in a given language.
// Czech is stored verbatim in the DB; English (or any other language)
// is derived from the same leading percentage via `labels`, so the two
// can never disagree on the underlying number.
function dealRatingLabel(dealRating, locale, dealRatingCs, labels) {
  if (locale === "cs") return dealRatingCs;
  const pct = extractDealPct(dealRatingCs);
  if (pct === null) return labels.marketPrice;
  if (pct <= -12) return `${labels.greatDeal} (${pct}%)`;
  if (pct < 0) return `${labels.belowMarket} (${pct}%)`;
  return `${labels.aboveMarket} (+${pct}%)`;
}

function formatPriceShort(price, currency) {
  const millions = Math.round((price / 1000000) * 100) / 100;
  return millions + "M " + currency;
}

// Generic JSON-stat value lookup: `selection` maps each dimension id
// (as listed in dataset.id) to the category key to pick within it.
// Used to read values out of ČSÚ's open-data JSON-stat responses.
function jsonStatValue(dataset, selection) {
  let flat = 0;
  for (let d = 0; d < dataset.id.length; d++) {
    const dimId = dataset.id[d];
    const idx = dataset.dimension[dimId].category.index[selection[dimId]];
    flat = flat * dataset.size[d] + idx;
  }
  return dataset.value[flat];
}

// Year-on-year percentage change; null when there's no prior value to
// compare against (e.g. only one year of data available yet).
function computeYoyTrendPct(latestValue, prevValue) {
  if (prevValue === null || prevValue === undefined || prevValue === 0) return null;
  return (latestValue / prevValue - 1) * 100;
}

// Percentage change from the first to the last point in a price
// history series; null for fewer than two points.
function computeHistoryChangePct(prices) {
  if (!prices || prices.length < 2) return null;
  const first = prices[0];
  const last = prices[prices.length - 1];
  if (!first) return null;
  return ((last - first) / first) * 100;
}

// Renders a tiny inline SVG sparkline for a price history series.
// Returns "" for fewer than two points (nothing meaningful to draw).
// Rising price -> upColor (default: less favorable for a buyer),
// falling/flat price -> downColor (default: more favorable).
function sparklineSvg(prices, options) {
  const opts = options || {};
  const width = opts.width || 64;
  const height = opts.height || 22;
  const pad = opts.pad != null ? opts.pad : 2;
  const upColor = opts.upColor || "#f2555a";
  const downColor = opts.downColor || "#34c77b";

  if (!prices || prices.length < 2) return "";

  const min = Math.min(...prices);
  const max = Math.max(...prices);
  const range = max - min || 1;
  const stepX = (width - pad * 2) / (prices.length - 1);

  const points = prices
    .map((p, i) => {
      const x = pad + i * stepX;
      const y = pad + (1 - (p - min) / range) * (height - pad * 2);
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(" ");

  const color = prices[prices.length - 1] >= prices[0] ? upColor : downColor;

  return (
    `<svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" class="sparkline" aria-hidden="true">` +
    `<polyline points="${points}" fill="none" stroke="${color}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>` +
    `</svg>`
  );
}

// Standard fixed-rate amortizing-loan monthly payment formula.
// downPaymentPct/annualRatePct are whole percent (20 = 20%, 5.5 = 5.5%).
// A 0% interest rate is handled as a straight-line split (no formula
// singularity), and a down payment >= 100% means no loan at all.
function mortgagePayment(price, downPaymentPct, annualRatePct, years) {
  const principal = price * (1 - downPaymentPct / 100);
  const numPayments = years * 12;
  if (principal <= 0 || numPayments <= 0) return 0;

  const monthlyRate = annualRatePct / 100 / 12;
  if (monthlyRate === 0) return principal / numPayments;

  const factor = Math.pow(1 + monthlyRate, numPayments);
  return (principal * (monthlyRate * factor)) / (factor - 1);
}

const PropTechUtils = {
  dealClass,
  extractDealPct,
  dealRatingLabel,
  formatPriceShort,
  jsonStatValue,
  computeYoyTrendPct,
  computeHistoryChangePct,
  sparklineSvg,
  mortgagePayment,
};

// Node/Vitest (CommonJS require/import interop) picks this branch up;
// the browser (plain <script src="utils.js">) picks up the global.
if (typeof module !== "undefined" && module.exports) {
  module.exports = PropTechUtils;
}
if (typeof window !== "undefined") {
  window.PropTechUtils = PropTechUtils;
}
