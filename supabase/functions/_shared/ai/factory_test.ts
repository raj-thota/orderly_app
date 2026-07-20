import { assertEquals, assertInstanceOf, assertThrows } from "jsr:@std/assert";
import { createProvider } from "./factory.ts";
import { GeminiProvider } from "./gemini.ts";
import { OpenAiProvider } from "./openai.ts";

const ENV_KEYS = [
  "AI_PROVIDER",
  "AI_PROVIDER_ASSISTANT",
  "AI_PROVIDER_PARSE_ENQUIRY",
  "GEMINI_API_KEY",
  "GEMINI_MODEL",
  "OPENAI_API_KEY",
  "OPENAI_MODEL",
  "OPENAI_BASE_URL",
  "AI_TIMEOUT_MS",
];
function clearEnv() { for (const k of ENV_KEYS) Deno.env.delete(k); }

Deno.test("defaults to gemini when nothing is set", () => {
  clearEnv();
  Deno.env.set("GEMINI_API_KEY", "g");
  assertInstanceOf(createProvider("assistant"), GeminiProvider);
});

Deno.test("global AI_PROVIDER selects openai", () => {
  clearEnv();
  Deno.env.set("AI_PROVIDER", "openai");
  Deno.env.set("OPENAI_API_KEY", "o");
  assertInstanceOf(createProvider("draft-reply"), OpenAiProvider);
});

Deno.test("per-function override beats global", () => {
  clearEnv();
  Deno.env.set("AI_PROVIDER", "gemini");
  Deno.env.set("GEMINI_API_KEY", "g");
  Deno.env.set("AI_PROVIDER_PARSE_ENQUIRY", "openai");
  Deno.env.set("OPENAI_API_KEY", "o");
  assertInstanceOf(createProvider("parse-enquiry"), OpenAiProvider);
  assertInstanceOf(createProvider("assistant"), GeminiProvider);
});

Deno.test("missing key throws a labelled error", () => {
  clearEnv();
  Deno.env.set("AI_PROVIDER", "openai");
  assertThrows(() => createProvider("assistant"), Error, "missing_openai_key");
});

Deno.test("unknown provider throws", () => {
  clearEnv();
  Deno.env.set("AI_PROVIDER", "llama");
  assertThrows(() => createProvider("assistant"), Error, "unsupported_provider_llama");
});

Deno.test("invalid AI_TIMEOUT_MS throws", () => {
  clearEnv();
  Deno.env.set("GEMINI_API_KEY", "g");
  Deno.env.set("AI_TIMEOUT_MS", "15s");
  assertThrows(() => createProvider("assistant"), Error, "invalid_AI_TIMEOUT_MS");
});
