// Supabase Edge Function: ai-proxy
// Proxy autenticado para a Groq. Segredos permanecem no servidor.

const GROQ_BASE = "https://api.groq.com/openai/v1";
const allowedOrigins = (Deno.env.get("AI_ALLOWED_ORIGINS") ??
  "https://daviandrade07.github.io,http://localhost:3000,http://localhost:8080")
  .split(",").map((value) => value.trim()).filter(Boolean);

function corsFor(req: Request) {
  const origin = req.headers.get("origin") ?? "";
  return {
    "Access-Control-Allow-Origin": allowedOrigins.includes(origin) ? origin : allowedOrigins[0],
    "Vary": "Origin",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

function json(req: Request, status: number, obj: unknown) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsFor(req), "content-type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsFor(req) });
  if (req.method !== "POST") return json(req, 405, { error: { message: "Método não permitido." } });

  const groqKey = Deno.env.get("GROQ_API_KEY");
  if (!groqKey) return json(req, 500, { error: { message: "Serviço temporariamente indisponível." } });

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const authHeader = req.headers.get("authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json(req, 401, { error: { message: "Não autenticado." } });

  const userResp = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: { apikey: anonKey, authorization: `Bearer ${token}` },
  });
  if (!userResp.ok) return json(req, 401, { error: { message: "Sessão inválida ou expirada." } });

  const url = new URL(req.url);
  const marker = "/ai-proxy";
  const i = url.pathname.indexOf(marker);
  let sub = i >= 0 ? url.pathname.slice(i + marker.length) : "";
  if (!sub || sub === "/") sub = "/chat/completions";
  if (sub !== "/chat/completions" && sub !== "/audio/transcriptions") {
    return json(req, 404, { error: { message: "Endpoint não disponível." } });
  }

  const maxBody = sub === "/audio/transcriptions" ? 10 * 1024 * 1024 : 256 * 1024;
  const contentLength = Number(req.headers.get("content-length") ?? 0);
  if (contentLength > maxBody) return json(req, 413, { error: { message: "Solicitação acima do limite permitido." } });

  const headers: Record<string, string> = { authorization: `Bearer ${groqKey}` };
  const ct = req.headers.get("content-type");
  if (ct) headers["content-type"] = ct;

  try {
    const body = await req.arrayBuffer();
    if (body.byteLength > maxBody) return json(req, 413, { error: { message: "Solicitação acima do limite permitido." } });
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 60_000);
    const upstream = await fetch(`${GROQ_BASE}${sub}`, {
      method: "POST", headers, body, signal: controller.signal,
    });
    clearTimeout(timeout);
    const buf = await upstream.arrayBuffer();
    return new Response(buf, {
      status: upstream.status,
      headers: { ...corsFor(req), "content-type": upstream.headers.get("content-type") ?? "application/json" },
    });
  } catch (_) {
    return json(req, 502, { error: { message: "Não foi possível concluir a solicitação." } });
  }
});
