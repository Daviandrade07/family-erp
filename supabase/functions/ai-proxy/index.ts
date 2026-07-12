// Supabase Edge Function: ai-proxy
//
// Proxy genérico para a Groq. Mantém a chave do Groq como SEGREDO no servidor
// (nunca no app público). Só usuários AUTENTICADOS conseguem usar — a função
// valida o token de sessão contra o Supabase Auth antes de encaminhar, então
// a chave não pode ser abusada mesmo que alguém descubra a publishable key.
//
// Encaminha qualquer sub-rota para a API da Groq:
//   POST /functions/v1/ai-proxy/chat/completions     -> chat + function calling
//   POST /functions/v1/ai-proxy/audio/transcriptions -> Whisper (voz -> texto)

const GROQ_BASE = "https://api.groq.com/openai/v1";
const allowedPaths = new Set(["/chat/completions", "/audio/transcriptions"]);
const maxRequestBytes = 10 * 1024 * 1024;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, obj: unknown) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, "content-type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  const groqKey = Deno.env.get("GROQ_API_KEY");
  if (!groqKey) return json(500, { error: { message: "Proxy sem GROQ_API_KEY." } });

  // --- Autenticação: exige um usuário logado válido -------------------------
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const authHeader = req.headers.get("authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json(401, { error: { message: "Não autenticado." } });

  const userResp = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: { apikey: anonKey, authorization: `Bearer ${token}` },
  });
  if (!userResp.ok) {
    return json(401, { error: { message: "Sessão inválida ou expirada." } });
  }

  // --- Encaminha para a Groq ------------------------------------------------
  const url = new URL(req.url);
  const marker = "/ai-proxy";
  const i = url.pathname.indexOf(marker);
  let sub = i >= 0 ? url.pathname.slice(i + marker.length) : "";
  if (!sub || sub === "/") sub = "/chat/completions";
  if (!allowedPaths.has(sub)) {
    return json(404, { error: { message: "Rota de IA não permitida." } });
  }

  const contentLength = Number(req.headers.get("content-length") ?? "0");
  if (contentLength > maxRequestBytes) {
    return json(413, { error: { message: "Pedido de IA muito grande." } });
  }

  const headers: Record<string, string> = {
    authorization: `Bearer ${groqKey}`,
  };
  const ct = req.headers.get("content-type");
  if (ct) headers["content-type"] = ct;

  try {
    const body = await req.arrayBuffer();
    if (body.byteLength > maxRequestBytes) {
      return json(413, { error: { message: "Pedido de IA muito grande." } });
    }
    const upstream = await fetch(`${GROQ_BASE}${sub}`, {
      method: "POST",
      headers,
      body,
    });
    const buf = await upstream.arrayBuffer();
    return new Response(buf, {
      status: upstream.status,
      headers: {
        ...cors,
        "content-type":
          upstream.headers.get("content-type") ?? "application/json",
      },
    });
  } catch (e) {
    return json(502, { error: { message: String(e) } });
  }
});
