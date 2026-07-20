import { assertEquals, assertRejects } from "jsr:@std/assert";
import { GeminiProvider } from "./gemini.ts";
import type { NeutralSchema } from "./schema.ts";

const schema: NeutralSchema = {
  type: "object",
  properties: { answer: { type: "string" } },
  required: ["answer"],
};

interface Captured { url: string; body: Record<string, unknown>; headers: Record<string, string>; }

function stubFetch(responses: unknown[]): { calls: Captured[]; restore: () => void } {
  const original = globalThis.fetch;
  const calls: Captured[] = [];
  let i = 0;
  globalThis.fetch = ((url: string | URL | Request, init?: RequestInit) => {
    calls.push({
      url: String(url),
      body: JSON.parse(String(init?.body ?? "{}")),
      headers: (init?.headers ?? {}) as Record<string, string>,
    });
    const payload = responses[Math.min(i, responses.length - 1)];
    i++;
    return Promise.resolve(new Response(JSON.stringify(payload), { status: 200 }));
  }) as typeof fetch;
  return { calls, restore: () => { globalThis.fetch = original; } };
}

function geminiText(obj: unknown) {
  return { candidates: [{ content: { parts: [{ text: JSON.stringify(obj) }] } }] };
}

Deno.test("generateJson builds a generateContent body and parses candidate text", async () => {
  const { calls, restore } = stubFetch([geminiText({ answer: "hi" })]);
  try {
    const p = new GeminiProvider("KEY", "gemini-2.5-flash", 5000);
    const out = await p.generateJson<{ answer: string }>({
      messages: [{ role: "user", content: "hello" }],
      schema,
      temperature: 0.3,
    });
    assertEquals(out.answer, "hi");
    const body = calls[0].body;
    const gc = body.generationConfig as Record<string, unknown>;
    assertEquals(gc.responseMimeType, "application/json");
    assertEquals((gc.responseSchema as Record<string, unknown>).type, "OBJECT");
    assertEquals(gc.temperature, 0.3);
    const contents = body.contents as Array<{ role: string; parts: unknown[] }>;
    assertEquals(contents[0].role, "user");
    assertEquals(calls[0].headers["x-goog-api-key"], "KEY");
    assertEquals(calls[0].url.includes("key="), false);
  } finally { restore(); }
});

Deno.test("generateJson appends an inline image part", async () => {
  const { calls, restore } = stubFetch([geminiText({ answer: "ok" })]);
  try {
    const p = new GeminiProvider("KEY", "m", 5000);
    await p.generateJson({
      messages: [{ role: "user", content: "read this" }],
      schema,
      image: { mimeType: "image/png", dataBase64: "AAAA" },
    });
    const contents = calls[0].body.contents as Array<{ parts: Record<string, unknown>[] }>;
    const parts = contents[0].parts;
    assertEquals((parts[1].inlineData as Record<string, unknown>).mimeType, "image/png");
  } finally { restore(); }
});

Deno.test("runToolLoop executes a tool, then makes the final structured call", async () => {
  const calledTools: Array<{ name: string; args: Record<string, unknown> }> = [];
  const responses = [
    // iter1: model calls a tool
    { candidates: [{ content: { parts: [{ functionCall: { name: "pipeline_stats", args: {} } }] } }] },
    // iter2: model returns text (no functionCall) -> loop breaks
    geminiText({ answer: "ignored" }),
    // final structured call
    geminiText({ answer: "done" }),
  ];
  const { calls, restore } = stubFetch(responses);
  try {
    const p = new GeminiProvider("KEY", "m", 5000);
    const out = await p.runToolLoop<{ answer: string }>({
      system: "sys",
      messages: [{ role: "user", content: "stats?" }],
      tools: [{ name: "pipeline_stats", description: "d", parameters: { type: "object" } }],
      finalSchema: schema,
      executeTool: (name, args) => { calledTools.push({ name, args }); return Promise.resolve({ leads: 3 }); },
    });
    assertEquals(out.answer, "done");
    assertEquals(calledTools[0].name, "pipeline_stats");
    // First call carries the tool declarations.
    assertEquals("tools" in calls[0].body, true);
    // The final call carries the structured-output config.
    const finalGc = calls[calls.length - 1].body.generationConfig as Record<string, unknown>;
    assertEquals(finalGc.responseMimeType, "application/json");
  } finally { restore(); }
});

Deno.test("runToolLoop stops after maxToolCalls even if the model keeps calling tools", async () => {
  let toolExecs = 0;
  const toolResp = { candidates: [{ content: { parts: [{ functionCall: { name: "t", args: {} } }] } }] };
  const responses = [toolResp, toolResp, geminiText({ answer: "capped" })];
  const { calls, restore } = stubFetch(responses);
  try {
    const p = new GeminiProvider("KEY", "m", 5000);
    const out = await p.runToolLoop<{ answer: string }>({
      system: "s",
      messages: [{ role: "user", content: "go" }],
      tools: [{ name: "t", description: "d", parameters: { type: "object" } }],
      finalSchema: schema,
      executeTool: () => { toolExecs++; return Promise.resolve({}); },
      maxToolCalls: 2,
    });
    assertEquals(toolExecs, 2);
    assertEquals(out.answer, "capped");
    // 2 tool-loop calls + 1 final call = 3 fetches.
    assertEquals(calls.length, 3);
  } finally { restore(); }
});

Deno.test("generateJson throws on non-200", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve(new Response("no", { status: 500 }))) as typeof fetch;
  try {
    const p = new GeminiProvider("KEY", "m", 5000);
    await assertRejects(
      () => p.generateJson({ messages: [{ role: "user", content: "x" }], schema }),
      Error,
      "gemini_http_500",
    );
  } finally { globalThis.fetch = original; }
});

Deno.test("runToolLoop records the model turn even when executeTool throws, and clears the timer", async () => {
  const toolResp = { candidates: [{ content: { parts: [{ functionCall: { name: "boom", args: {} } }] } }] };
  const { restore } = stubFetch([toolResp]);
  try {
    const p = new GeminiProvider("KEY", "m", 5000);
    let threw = false;
    try {
      await p.runToolLoop({
        system: "s",
        messages: [{ role: "user", content: "go" }],
        tools: [{ name: "boom", description: "d", parameters: { type: "object" } }],
        finalSchema: schema,
        executeTool: () => Promise.reject(new Error("tool_failed")),
      });
    } catch (e) {
      threw = true;
      assertEquals((e as Error).message, "tool_failed");
    }
    assertEquals(threw, true);
  } finally { restore(); }
});
