import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import { createWorkItemsProvider } from "./provider.ts";
import { CustomerSignal, WorkItemKind, WorkItemPriority } from "./schema.ts";

const RATE_MAX = 10;
const RATE_WINDOW_SECONDS = 3600;
const MAX_CUSTOMERS = 30;
const MAX_ITEMS = 20;
const ALLOWED_KINDS = new Set<WorkItemKind>([
  "payment_reminder",
  "reply",
  "create_order",
  "invoice",
  "follow_up",
  "share_catalog",
]);
const ALLOWED_PRIORITIES = new Set<WorkItemPriority>(["high", "medium", "low"]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "unauthorized" }, 401);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData?.user) return json({ error: "unauthorized" }, 401);
  const userId = userData.user.id;

  // Rate limit — generate-work-items is expensive; 10/hour is generous.
  const { data: allowed, error: rlErr } = await supabase.rpc(
    "check_ai_parse_rate_limit",
    { p_max: RATE_MAX, p_window_seconds: RATE_WINDOW_SECONDS },
  );
  if (rlErr) return json({ error: "internal" }, 500);
  if (allowed !== true) return json({ error: "rate_limited" }, 429);

  // ── 1. Gather signals from DB ──────────────────────────────────────────────
  // Amounts, UPI IDs, phone numbers stay in DB — never sent to the model.

  const now = new Date();

  const { data: customers } = await supabase
    .from("customers")
    .select("id, name")
    .eq("user_id", userId)
    .limit(MAX_CUSTOMERS);

  if (!customers?.length) {
    return json({ inserted: 0 }, 200);
  }

  const customerIds = customers.map((c) => c.id);

  // Latest message per customer via conversations → messages.
  const { data: convRows } = await supabase
    .from("conversations")
    .select("id, customer_id")
    .eq("user_id", userId)
    .in("customer_id", customerIds);

  const convByCustomer = new Map<string, string>();
  for (const row of convRows ?? []) {
    convByCustomer.set(row.customer_id, row.id);
  }

  const { data: lastMsgs } = convRows?.length
    ? await supabase
      .from("messages")
      .select("conversation_id, direction, body, created_at")
      .eq("user_id", userId)
      .in("conversation_id", Array.from(convByCustomer.values()))
      .order("created_at", { ascending: false })
      .limit(MAX_CUSTOMERS)
    : { data: [] };

  const lastMsgByConv = new Map<string, typeof lastMsgs extends (infer T)[] | null ? T : never>();
  for (const msg of lastMsgs ?? []) {
    if (!lastMsgByConv.has(msg.conversation_id)) {
      lastMsgByConv.set(msg.conversation_id, msg);
    }
  }

  // Unpaid orders per customer (only existence — amounts NOT sent to model).
  const { data: unpaidOrders } = await supabase
    .from("orders")
    .select("customer_id")
    .eq("user_id", userId)
    .eq("payment_status", "unpaid")
    .in("customer_id", customerIds);

  const unpaidSet = new Set<string>((unpaidOrders ?? []).map((o) => o.customer_id));

  // Overdue follow-ups.
  const { data: followUps } = await supabase
    .from("leads")
    .select("customer_id, follow_up_date")
    .eq("user_id", userId)
    .eq("status", "follow")
    .lte("follow_up_date", now.toISOString())
    .in("customer_id", customerIds);

  const overdueByCustomer = new Map<string, number>();
  for (const fu of followUps ?? []) {
    if (!fu.follow_up_date) continue;
    const days = Math.floor(
      (now.getTime() - new Date(fu.follow_up_date).getTime()) / 86_400_000,
    );
    const existing = overdueByCustomer.get(fu.customer_id) ?? 0;
    if (days > existing) overdueByCustomer.set(fu.customer_id, days);
  }

  // Latest lead intent/message per customer.
  const { data: leadRows } = await supabase
    .from("leads")
    .select("customer_id, intent, message")
    .eq("user_id", userId)
    .in("customer_id", customerIds)
    .order("created_at", { ascending: false })
    .limit(MAX_CUSTOMERS);

  const leadByCustomer = new Map<string, { intent: string | null; message: string | null }>();
  for (const lr of leadRows ?? []) {
    if (!leadByCustomer.has(lr.customer_id)) {
      leadByCustomer.set(lr.customer_id, { intent: lr.intent, message: lr.message });
    }
  }

  // Build signal array — skip customers with no meaningful signal.
  const signals: CustomerSignal[] = [];
  for (const customer of customers) {
    const convId = convByCustomer.get(customer.id);
    const lastMsg = convId ? lastMsgByConv.get(convId) : undefined;
    const hasUnpaid = unpaidSet.has(customer.id);
    const overdueDays = overdueByCustomer.get(customer.id) ?? null;
    const lead = leadByCustomer.get(customer.id) ?? null;

    const daysSince = lastMsg?.created_at
      ? Math.floor((now.getTime() - new Date(lastMsg.created_at).getTime()) / 86_400_000)
      : null;

    // Skip customers with no signal worth acting on.
    const hasSignal = hasUnpaid || overdueDays !== null ||
      (daysSince !== null && daysSince >= 1 && lastMsg?.direction === "inbound");
    if (!hasSignal) continue;

    signals.push({
      customerId: customer.id,
      customerName: customer.name,
      lastMessage: lastMsg?.body ?? null,
      lastMessageDirection: lastMsg?.direction ?? null,
      daysSinceLastMessage: daysSince,
      hasUnpaidOrder: hasUnpaid,
      followUpOverdueDays: overdueDays,
      leadIntent: lead?.intent ?? null,
      leadMessage: lead?.message ?? null,
    });
  }

  if (!signals.length) {
    return json({ inserted: 0 }, 200);
  }

  // ── 2. Call LLM ────────────────────────────────────────────────────────────
  const { data: bizRow } = await supabase
    .from("business_profile")
    .select("name")
    .eq("user_id", userId)
    .maybeSingle();

  let rawItems: ReturnType<typeof createWorkItemsProvider> extends { generate: (...args: unknown[]) => Promise<infer R> } ? R extends { items: (infer I)[] } ? I[] : never : never;
  try {
    const provider = createWorkItemsProvider();
    const result = await provider.generate({
      signals,
      sellerName: bizRow?.name ?? "Seller",
    });
    rawItems = result.items ?? [];
  } catch (e) {
    const label = e instanceof Error ? e.message : "unknown";
    console.error(`generate_work_items_failed:${label}`);
    return json({ error: "generate_failed" }, 502);
  }

  // ── 3. Validate + coerce model output ─────────────────────────────────────
  const validCustomerIds = new Set(customerIds);
  const batchId = crypto.randomUUID();
  const expiresAt = new Date(now.getTime() + 24 * 60 * 60 * 1000).toISOString();

  const rows = rawItems
    .slice(0, MAX_ITEMS)
    .filter((item) => {
      if (typeof item !== "object" || item === null) return false;
      if (!validCustomerIds.has(item.customerId)) return false;
      if (!ALLOWED_KINDS.has(item.kind as WorkItemKind)) return false;
      if (!ALLOWED_PRIORITIES.has(item.priority as WorkItemPriority)) return false;
      if (typeof item.title !== "string" || !item.title.trim()) return false;
      // Reject if model hallucinated amounts/UPI/phone in draftMessage.
      const draft = typeof item.draftMessage === "string" ? item.draftMessage : "";
      if (/₹|\d{10}|upi|@[a-z]|paytm|gpay|phonepe/i.test(draft)) {
        console.warn(`work_item_rejected_pii:${item.customerId}`);
        return false;
      }
      return true;
    })
    .map((item) => ({
      user_id: userId,
      customer_id: item.customerId,
      kind: item.kind,
      priority: item.priority,
      score: Math.min(100, Math.max(0, Math.round(item.score))),
      title: item.title.slice(0, 120),
      context: (item.context ?? "").slice(0, 200),
      draft: { message: item.draftMessage.slice(0, 500), confidence: Math.min(1, Math.max(0, item.confidence)) },
      status: "pending",
      batch_id: batchId,
      expires_at: expiresAt,
    }));

  if (!rows.length) {
    return json({ inserted: 0 }, 200);
  }

  // ── 4. Expire old pending items, then insert new batch ────────────────────
  await supabase
    .from("ai_work_items")
    .update({ status: "expired" })
    .eq("user_id", userId)
    .eq("status", "pending");

  const { error: insertErr } = await supabase.from("ai_work_items").insert(rows);
  if (insertErr) {
    console.error(`work_items_insert_failed:${insertErr.message}`);
    return json({ error: "internal" }, 500);
  }

  return json({ inserted: rows.length, batch_id: batchId }, 200);
});
