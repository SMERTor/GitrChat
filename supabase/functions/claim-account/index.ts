import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function normalizeName(value: unknown): string {
  return String(value ?? "").trim().toLowerCase().replace(/\s+/g, " ");
}

async function loginEmail(name: string): Promise<string> {
  const bytes = new TextEncoder().encode(name);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const hex = Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
  return `u_${hex.slice(0, 40)}@accounts.gitrchat.invalid`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return response(405, { error: "method_not_allowed" });

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return response(401, { error: "auth_required" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const verifier = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  const { data: authData, error: authError } = await verifier.auth.getUser(token);
  if (authError || !authData.user) return response(401, { error: "invalid_session" });
  const user = authData.user;

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return response(400, { error: "invalid_json" }); }
  const displayName = String(body.name ?? "").trim();
  const usernameKey = normalizeName(body.name);
  const pin = String(body.pin ?? "");
  if (!displayName || displayName.length > 24 || usernameKey.length < 1 || usernameKey.length > 64) {
    return response(400, { error: "invalid_name" });
  }
  if (!/^\d{6}$/.test(pin)) return response(400, { error: "pin_must_be_six_digits" });

  const { data: byName, error: nameLookupError } = await admin
    .from("account_claims").select("user_id").eq("username_key", usernameKey).maybeSingle();
  if (nameLookupError) return response(500, { error: "account_lookup_failed" });
  if (byName && byName.user_id !== user.id) return response(409, { error: "name_already_claimed" });

  const { data: byUser, error: userLookupError } = await admin
    .from("account_claims").select("username_key").eq("user_id", user.id).maybeSingle();
  if (userLookupError) return response(500, { error: "account_lookup_failed" });
  if (byUser && byUser.username_key !== usernameKey) {
    return response(409, { error: "account_name_cannot_be_changed" });
  }

  const email = await loginEmail(usernameKey);
  const { error: updateError } = await admin.auth.admin.updateUserById(user.id, {
    email,
    password: pin,
    email_confirm: true,
    user_metadata: { ...user.user_metadata, display_name: displayName, gitrchat_login: usernameKey },
  });
  if (updateError) return response(400, { error: "account_link_failed", detail: updateError.message });

  if (!byName) {
    const { error: claimError } = await admin.from("account_claims").insert({
      username_key: usernameKey,
      user_id: user.id,
    });
    if (claimError) return response(409, { error: "name_already_claimed" });
  }

  const { error: profileError } = await admin.from("profiles").upsert({
    id: user.id,
    name: displayName,
    updated_at: new Date().toISOString(),
  });
  if (profileError) return response(500, { error: "profile_update_failed", detail: profileError.message });

  return response(200, { success: true, name: displayName });
});