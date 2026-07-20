import { assertEquals } from "jsr:@std/assert";
import { NeutralSchema, toGeminiSchema, toOpenAiSchema } from "./schema.ts";

const parseEnquiryLike: NeutralSchema = {
  type: "object",
  properties: {
    customer_name: { type: "string", nullable: true },
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          name: { type: "string" },
          qty: { type: "integer" },
          price: { type: "number", nullable: true },
        },
        required: ["name", "qty"],
      },
    },
    intent: { type: "string", enum: ["inquiry", "order", "follow_up"] },
    confidence: { type: "number" },
  },
  required: ["items", "intent", "confidence"],
};

Deno.test("toGeminiSchema uppercases types and preserves enum/required/nullable", () => {
  const g = toGeminiSchema(parseEnquiryLike) as Record<string, unknown>;
  assertEquals(g.type, "OBJECT");
  const props = g.properties as Record<string, Record<string, unknown>>;
  assertEquals(props.customer_name.type, "STRING");
  assertEquals(props.customer_name.nullable, true);
  assertEquals(props.intent.enum, ["inquiry", "order", "follow_up"]);
  assertEquals((props.items.items as Record<string, unknown>).type, "OBJECT");
  assertEquals(g.required, ["items", "intent", "confidence"]);
  assertEquals("additionalProperties" in g, false);
});

Deno.test("toOpenAiSchema makes all props required, adds additionalProperties:false, null-unions optionals", () => {
  const o = toOpenAiSchema(parseEnquiryLike) as Record<string, unknown>;
  assertEquals(o.type, "object");
  assertEquals(o.additionalProperties, false);
  assertEquals(
    (o.required as string[]).sort(),
    ["confidence", "customer_name", "intent", "items"],
  );
  const props = o.properties as Record<string, Record<string, unknown>>;
  assertEquals(props.customer_name.type, ["string", "null"]);
  assertEquals(props.confidence.type, "number");
  const item = props.items.items as Record<string, unknown>;
  assertEquals(item.additionalProperties, false);
  assertEquals((item.required as string[]).sort(), ["name", "price", "qty"]);
  const itemProps = item.properties as Record<string, Record<string, unknown>>;
  assertEquals(itemProps.price.type, ["number", "null"]);
  assertEquals(itemProps.name.type, "string");
  assertEquals("nullable" in props.customer_name, false);
});

Deno.test("toOpenAiSchema treats missing `required` as all-required", () => {
  const s: NeutralSchema = {
    type: "object",
    properties: { a: { type: "string" }, b: { type: "integer" } },
  };
  const o = toOpenAiSchema(s) as Record<string, unknown>;
  assertEquals((o.required as string[]).sort(), ["a", "b"]);
  const props = o.properties as Record<string, Record<string, unknown>>;
  assertEquals(props.a.type, "string");
  assertEquals(props.b.type, "integer");
});

Deno.test("toOpenAiSchema puts null into the enum when a nullable enum is optional", () => {
  const s: NeutralSchema = {
    type: "object",
    properties: {
      status: { type: "string", enum: ["open", "closed"] }, // optional -> auto-nullable
      name: { type: "string" },
    },
    required: ["name"],
  };
  const o = toOpenAiSchema(s) as Record<string, unknown>;
  const props = o.properties as Record<string, Record<string, unknown>>;
  assertEquals(props.status.type, ["string", "null"]);
  assertEquals(props.status.enum, ["open", "closed", null]);
});

Deno.test("toOpenAiSchema gives a bare object additionalProperties:false", () => {
  const s: NeutralSchema = { type: "object" };
  const o = toOpenAiSchema(s) as Record<string, unknown>;
  assertEquals(o.type, "object");
  assertEquals(o.additionalProperties, false);
  assertEquals(o.required, []);
});

Deno.test("toOpenAiSchema throws when required names a missing property", () => {
  const s: NeutralSchema = {
    type: "object",
    properties: { a: { type: "string" } },
    required: ["a", "ghost"],
  };
  let threw = false;
  try {
    toOpenAiSchema(s);
  } catch (e) {
    threw = true;
    assertEquals((e as Error).message.includes("ghost"), true);
  }
  assertEquals(threw, true);
});

Deno.test("toOpenAiSchema marks a nullable object node as [object,null]", () => {
  const s: NeutralSchema = {
    type: "object",
    properties: {
      meta: { type: "object", nullable: true, properties: { k: { type: "string" } } },
    },
    required: ["meta"],
  };
  const o = toOpenAiSchema(s) as Record<string, unknown>;
  const props = o.properties as Record<string, Record<string, unknown>>;
  assertEquals(props.meta.type, ["object", "null"]);
  assertEquals(props.meta.additionalProperties, false);
});
