import { assertEquals, assertRejects } from "jsr:@std/assert";
import { OpenAiProvider } from "./openai.ts";
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

function openaiContent(obj: unknown) {
  return { choices: [{ message: { role: "assistant", content: JSON.stringify(obj) } }] };
}

Deno.test("generateJson posts chat/completions with strict json_schema and parses content", async () => {
  const { calls, restore } = stubFetch([openaiContent({ answer: "hi" })]);
  try {
    const p = new OpenAiProvider("KEY", "gpt-4o-mini", 5000);
    const out = await p.generateJson<{ answer: string }>({
      system: "sys",
      messages: [{ role: "user", content: "hello" }],
      schema,
      temperature: 0.2,
    });
    assertEquals(out.answer, "hi");
    assertEquals(calls[0].url, "https://api.openai.com/v1/chat/completions");
    assertEquals(calls[0].headers.Authorization, "Bearer KEY");
    const body = calls[0].body;
    assertEquals(body.model, "gpt-4o-mini");
    assertEquals(body.temperature, 0.2);
    const rf = body.response_format as { type: string; json_schema: Record<string, unknown> };
    assertEquals(rf.type, "json_schema");
    assertEquals(rf.json_schema.strict, true);
    const msgs = body.messages as Array<{ role: string; content: unknown }>;
    assertEquals(msgs[0].role, "system");
    assertEquals(msgs[1].role, "user");
  } finally { restore(); }
});

Deno.test("generateJson sends an image as a data URL in the user message content", async () => {
  const { calls, restore } = stubFetch([openaiContent({ answer: "ok" })]);
  try {
    const p = new OpenAiProvider("KEY", "gpt-4o-mini", 5000);
    await p.generateJson({
      messages: [{ role: "user", content: "read" }],
      schema,
      image: { mimeType: "image/png", dataBase64: "AAAA" },
    });
    const msgs = calls[0].body.messages as Array<{ role: string; content: Array<Record<string, unknown>> }>;
    const parts = msgs[msgs.length - 1].content;
    assertEquals(parts[0].type, "text");
    assertEquals(parts[1].type, "image_url");
    assertEquals(
      (parts[1].image_url as Record<string, string>).url,
      "data:image/png;base64,AAAA",
    );
  } finally { restore(); }
});

Deno.test("runToolLoop handles tool_calls, appends tool messages, then a final structured call", async () => {
  const execed: string[] = [];
  const toolTurn = {
    choices: [{
      message: {
        role: "assistant",
        content: null,
        tool_calls: [{ id: "call_1", type: "function", function: { name: "pipeline_stats", arguments: "{}" } }],
      },
    }],
  };
  // iter1: tool_calls -> execute; iter2: plain assistant text -> break; final: structured.
  const assistantText = { choices: [{ message: { role: "assistant", content: "thinking done" } }] };
  const { calls, restore } = stubFetch([toolTurn, assistantText, openaiContent({ answer: "done" })]);
  try {
    const p = new OpenAiProvider("KEY", "gpt-4o-mini", 5000);
    const out = await p.runToolLoop<{ answer: string }>({
      system: "sys",
      messages: [{ role: "user", content: "stats?" }],
      tools: [{ name: "pipeline_stats", description: "d", parameters: { type: "object" } }],
      finalSchema: schema,
      executeTool: (name: string) => { execed.push(name); return Promise.resolve({ leads: 3 }); },
    });
    assertEquals(out.answer, "done");
    assertEquals(execed, ["pipeline_stats"]);
    // Final call carries response_format; the loop calls do not.
    const finalBody = calls[calls.length - 1].body;
    assertEquals("response_format" in finalBody, true);
    // A tool-result message with the matching tool_call_id was appended.
    const finalMsgs = finalBody.messages as Array<{ role: string; tool_call_id?: string }>;
    assertEquals(finalMsgs.some((m) => m.role === "tool" && m.tool_call_id === "call_1"), true);
  } finally { restore(); }
});

Deno.test("runToolLoop stops after maxToolCalls", async () => {
  let execs = 0;
  const toolTurn = {
    choices: [{ message: { role: "assistant", tool_calls: [{ id: "c", type: "function", function: { name: "t", arguments: "{}" } }] } }],
  };
  const { calls, restore } = stubFetch([toolTurn, toolTurn, openaiContent({ answer: "capped" })]);
  try {
    const p = new OpenAiProvider("KEY", "gpt-4o-mini", 5000);
    const out = await p.runToolLoop<{ answer: string }>({
      system: "s",
      messages: [{ role: "user", content: "go" }],
      tools: [{ name: "t", description: "d", parameters: { type: "object" } }],
      finalSchema: schema,
      executeTool: () => { execs++; return Promise.resolve({}); },
      maxToolCalls: 2,
    });
    assertEquals(execs, 2);
    assertEquals(out.answer, "capped");
    assertEquals(calls.length, 3); // 2 loop + 1 final
  } finally { restore(); }
});

Deno.test("generateJson throws on non-200", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve(new Response("no", { status: 401 }))) as typeof fetch;
  try {
    const p = new OpenAiProvider("KEY", "m", 5000);
    await assertRejects(
      () => p.generateJson({ messages: [{ role: "user", content: "x" }], schema }),
      Error,
      "openai_http_401",
    );
  } finally { globalThis.fetch = original; }
});

Deno.test("runToolLoop fans out over multiple tool_calls in one turn", async () => {
  const execed: Array<{ name: string; id: string }> = [];
  const twoCalls = {
    choices: [{
      message: {
        role: "assistant",
        content: null,
        tool_calls: [
          { id: "a1", type: "function", function: { name: "one", arguments: "{}" } },
          { id: "a2", type: "function", function: { name: "two", arguments: "{}" } },
        ],
      },
    }],
  };
  const done = { choices: [{ message: { role: "assistant", content: "ok" } }] };
  const { calls, restore } = stubFetch([twoCalls, done, openaiContent({ answer: "z" })]);
  try {
    const p = new OpenAiProvider("KEY", "gpt-4o-mini", 5000);
    const out = await p.runToolLoop<{ answer: string }>({
      system: "s",
      messages: [{ role: "user", content: "go" }],
      tools: [
        { name: "one", description: "d", parameters: { type: "object" } },
        { name: "two", description: "d", parameters: { type: "object" } },
      ],
      finalSchema: schema,
      executeTool: (name) => {
        const id = name === "one" ? "a1" : "a2";
        execed.push({ name, id });
        return Promise.resolve({ ok: name });
      },
    });
    assertEquals(out.answer, "z");
    assertEquals(execed.map((e) => e.name), ["one", "two"]);
    // Both tool results appended with their matching tool_call_ids.
    const finalMsgs = calls[calls.length - 1].body.messages as Array<{ role: string; tool_call_id?: string }>;
    const toolIds = finalMsgs.filter((m) => m.role === "tool").map((m) => m.tool_call_id);
    assertEquals(toolIds, ["a1", "a2"]);
  } finally { restore(); }
});

Deno.test("runToolLoop throws on malformed tool arguments", async () => {
  const badArgs = {
    choices: [{
      message: {
        role: "assistant",
        tool_calls: [{ id: "x", type: "function", function: { name: "t", arguments: "{not json" } }],
      },
    }],
  };
  const { restore } = stubFetch([badArgs]);
  try {
    const p = new OpenAiProvider("KEY", "m", 5000);
    let threw = false;
    try {
      await p.runToolLoop({
        system: "s",
        messages: [{ role: "user", content: "go" }],
        tools: [{ name: "t", description: "d", parameters: { type: "object" } }],
        finalSchema: schema,
        executeTool: () => Promise.resolve({}),
      });
    } catch (e) {
      threw = true;
      assertEquals((e as Error).message, "openai_bad_tool_args:t");
    }
    assertEquals(threw, true);
  } finally { restore(); }
});
