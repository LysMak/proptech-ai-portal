// Vercel serverless function — injects per-listing Open Graph / Twitter
// meta tags into index.html before it's served, so sharing a permalink
// (?id=<propertyId>) in Telegram/WhatsApp/Slack/etc. shows that
// listing's title, price and district instead of the generic site
// description. Crawlers for those previews don't execute JavaScript,
// so this can't be done client-side — it has to happen before the
// HTML leaves the server.
//
// Only requests to "/" that carry an ?id= query param are routed here
// (see vercel.json); a plain "/" is still served as a static file, so
// this function never adds latency to the common case.
const fs = require("fs");
const path = require("path");

function readSupabaseConfig() {
  const configText = fs.readFileSync(path.join(process.cwd(), "config.js"), "utf8");
  const urlMatch = configText.match(/SUPABASE_URL\s*=\s*"([^"]+)"/);
  const keyMatch = configText.match(/SUPABASE_ANON_KEY\s*=\s*"([^"]+)"/);
  if (!urlMatch || !keyMatch) throw new Error("Could not read Supabase config");
  return { url: urlMatch[1], key: keyMatch[1] };
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function formatPriceShort(price) {
  const millions = Math.round((price / 1000000) * 100) / 100;
  return `${millions}M Kč`;
}

function injectMeta(html, { title, description, url }) {
  const safeTitle = escapeHtml(title);
  const safeDescription = escapeHtml(description);
  const safeUrl = escapeHtml(url);
  return html
    .replace(/<title>[^<]*<\/title>/, `<title>${safeTitle}</title>`)
    .replace(/(<meta name="description" content=")[^"]*(" \/>)/, `$1${safeDescription}$2`)
    .replace(/(<meta property="og:url" content=")[^"]*(" \/>)/, `$1${safeUrl}$2`)
    .replace(/(<meta property="og:title" content=")[^"]*(" \/>)/, `$1${safeTitle}$2`)
    .replace(/(<meta property="og:description" content=")[^"]*(" \/>)/, `$1${safeDescription}$2`)
    .replace(/(<meta name="twitter:title" content=")[^"]*(" \/>)/, `$1${safeTitle}$2`)
    .replace(/(<meta name="twitter:description" content=")[^"]*(" \/>)/, `$1${safeDescription}$2`);
}

module.exports = async (req, res) => {
  let html;
  try {
    html = fs.readFileSync(path.join(process.cwd(), "index.html"), "utf8");
  } catch (e) {
    res.status(500).send("Could not load page");
    return;
  }

  const id = req.query && req.query.id;
  if (id) {
    try {
      const { url: supabaseUrl, key: supabaseKey } = readSupabaseConfig();
      const apiUrl = `${supabaseUrl}/rest/v1/properties?id=eq.${encodeURIComponent(
        id
      )}&select=title,district,price,deal_rating`;
      const supaRes = await fetch(apiUrl, {
        headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` },
      });
      const rows = await supaRes.json();
      const property = Array.isArray(rows) ? rows[0] : null;
      if (property) {
        const proto = req.headers["x-forwarded-proto"] || "https";
        const baseUrl = `${proto}://${req.headers.host}`;
        html = injectMeta(html, {
          title: `${property.title} — ${formatPriceShort(property.price)}`,
          description: `${property.district}, Praha · ${property.deal_rating}`,
          url: `${baseUrl}/?id=${encodeURIComponent(id)}`,
        });
      }
    } catch (e) {
      // Bad/stale id, network hiccup, etc. — fall back to the
      // page's own default static meta tags, already in html.
    }
  }

  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "public, max-age=0, s-maxage=300, stale-while-revalidate=600");
  res.status(200).send(html);
};
