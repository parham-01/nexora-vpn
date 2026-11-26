// Nexora VPN — Cloudflare Worker relay (version 1)
//
// فقط درخواست‌های ورود/حساب/لیست سرورها از این رله رد می‌شوند، نه ترافیک VPN.
// Only sign-in / account / server-list requests use this relay, never VPN traffic.
//
// ===== چی باید جایگزین بشه؟ / WHAT TO REPLACE =====
//  1) این کد را کامل جایگزین کد پیش‌فرض Worker کن (Edit code ← Deploy).
//  2) Worker ← Settings ← Variables and Secrets ← Add:
//        Type: Secret     Name: RELAY_SECRET     Value: <یک رمز دلخواه، مثلا ۳۲ حرف>
//  3) آدرس رله‌ای که داخل اپ می‌گذاری:
//        https://WORKER.ACCOUNT.workers.dev/?secret=SECRET
//     WORKER.ACCOUNT ← همان آدرسی که کلادفلر بعد از Deploy نشانت می‌دهد
//                      (مثلا relay.myname.workers.dev؛ اگر Worker را «relay» نام بگذاری،
//                      فقط myname را با زیردامنه‌ی حساب خودت جایگزین کن)
//     SECRET         ← دقیقا همان مقدار RELAY_SECRET
//  4) در اپ: گزینه‌ها ← رله‌ی شخصی ← آدرس را بگذار ← «تست سلامت رله».

const HOP = new Set([
  "host", "connection", "keep-alive", "transfer-encoding", "upgrade",
  "proxy-authorization", "proxy-authenticate", "te", "trailer",
  "content-length", "x-forwarded-for", "x-forwarded-proto", "x-real-ip",
  "forwarded", "via",
]);

function fail(status, reason) {
  return new Response(JSON.stringify({ error: reason }), {
    status,
    headers: { "content-type": "application/json", "x-relay-error": reason, "cache-control": "no-store" },
  });
}

function sameSecret(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function privateHost(h) {
  h = h.toLowerCase();
  return (
    h === "localhost" || h.endsWith(".localhost") || h.endsWith(".local") || h.endsWith(".internal") ||
    /^(127|10|0)\./.test(h) || /^192\.168\./.test(h) || /^169\.254\./.test(h) ||
    /^172\.(1[6-9]|2\d|3[01])\./.test(h) || h === "[::1]" || h.startsWith("[fc") || h.startsWith("[fd") || h.startsWith("[fe80")
  );
}

export default {
  async fetch(request, env) {
    const secret = env.RELAY_SECRET;
    if (!secret) return fail(500, "no secret is set in the relay");

    const self = new URL(request.url);
    if (!sameSecret(self.searchParams.get("secret") || "", String(secret))) {
      return fail(403, "wrong secret");
    }

    // Health check used by the app's «تست سلامت رله» button.
    if (self.searchParams.has("health")) {
      return new Response(JSON.stringify({ relay: "nexora-vpn", version: 1, ready: true }), {
        headers: { "content-type": "application/json", "cache-control": "no-store" },
      });
    }

    const target = self.searchParams.get("url");
    if (!target) return fail(400, "missing url");
    let dest;
    try { dest = new URL(target); } catch { return fail(400, "bad url"); }
    if (dest.protocol !== "https:") return fail(400, "https only");
    if (dest.username || dest.password) return fail(400, "credentials in url");
    if (privateHost(dest.hostname)) return fail(403, "private host");
    if (dest.hostname === self.hostname) return fail(403, "loop");

    // Optional: lock the relay to specific hosts, e.g. env var ALLOW = "firefox.com,mozilla.com,mozilla.org"
    if (env.ALLOW) {
      const ok = String(env.ALLOW).split(",").map((s) => s.trim().toLowerCase()).filter(Boolean)
        .some((d) => dest.hostname === d || dest.hostname.endsWith("." + d));
      if (!ok) return fail(403, "host not allowed");
    }

    const headers = new Headers();
    for (const [k, v] of request.headers) {
      const key = k.toLowerCase();
      if (HOP.has(key) || key.startsWith("cf-") || key.startsWith("x-forwarded-")) continue;
      headers.set(k, v);
    }

    const init = { method: request.method, headers, redirect: "manual" };
    if (!["GET", "HEAD"].includes(request.method)) init.body = request.body;

    let upstream;
    try {
      upstream = await fetch(dest.toString(), init);
    } catch (e) {
      return fail(502, "upstream unreachable");
    }

    const out = new Headers(upstream.headers);
    out.delete("content-length");
    out.set("cache-control", "no-store");
    return new Response(upstream.body, { status: upstream.status, statusText: upstream.statusText, headers: out });
  },
};
