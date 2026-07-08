import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import { createParser } from "./provider.ts";

const MAX_INPUT_CHARS = 4000;
const MAX_IMAGE_B64 = 2_000_000; // ~1.5 MB decoded
const ALLOWED_IMAGE_MIME = new Set(["image/jpeg", "image/png", "image/webp"]);
const RATE_MAX = 30;
const RATE_WINDOW_SECONDS = 3600;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "unauthorized" }, 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData?.user) {
    return json({ error: "unauthorized" }, 401);
  }

  // Validate input before consuming a rate-limit slot so malformed requests
  // never burn the user's quota.
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "bad_request" }, 400);
  }

  const text = typeof body.text === "string" ? body.text : "";
  if (text.length > MAX_INPUT_CHARS) {
    return json({ error: "too_long" }, 413);
  }

  let image: { mimeType: string; data: string } | undefined;
  const rawImage = body.image;
  if (rawImage !== undefined && rawImage !== null) {
    if (
      typeof rawImage !== "object" ||
      typeof (rawImage as Record<string, unknown>).mime !== "string" ||
      typeof (rawImage as Record<string, unknown>).data !== "string"
    ) {
      return json({ error: "bad_request" }, 400);
    }
    const mime = (rawImage as Record<string, string>).mime;
    const dataB64 = (rawImage as Record<string, string>).data;
    if (!ALLOWED_IMAGE_MIME.has(mime)) {
      return json({ error: "unsupported_media" }, 415);
    }
    if (dataB64.length === 0 || dataB64.length > MAX_IMAGE_B64) {
      return json({ error: "bad_request" }, 400);
    }
    image = { mimeType: mime, data: dataB64 };
  }

  if (text.trim().length === 0 && image === undefined) {
    return json({ error: "bad_request" }, 400);
  }

  const { data: allowed, error: rlErr } = await supabase.rpc(
    "check_ai_parse_rate_limit",
    { p_max: RATE_MAX, p_window_seconds: RATE_WINDOW_SECONDS },
  );
  if (rlErr) {
    console.error("rate_limit_rpc_error");
    return json({ error: "internal" }, 500);
  }
  if (allowed !== true) {
    return json({ error: "rate_limited" }, 429);
  }

  try {
    const parser = createParser();
    const result = await parser.parse({ text, image });
    return json(result, 200);
  } catch (e) {
    // Label only — never the chat text or provider payload.
    const label = e instanceof Error ? e.message : "unknown";
    console.error(`parse_failed:${label}`);
    return json({ error: "parse_failed" }, 502);
  }
});
