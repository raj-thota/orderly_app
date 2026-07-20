export interface NeutralSchema {
  type: "object" | "array" | "string" | "integer" | "number" | "boolean";
  description?: string;
  properties?: Record<string, NeutralSchema>;
  items?: NeutralSchema;
  enum?: string[];
  required?: string[];
  nullable?: boolean;
}

const GEMINI_TYPE: Record<NeutralSchema["type"], string> = {
  object: "OBJECT",
  array: "ARRAY",
  string: "STRING",
  integer: "INTEGER",
  number: "NUMBER",
  boolean: "BOOLEAN",
};

/** Translate a neutral schema to Gemini's `responseSchema` dialect (uppercase
 * types, `nullable` keyword, partial `required` allowed). */
export function toGeminiSchema(s: NeutralSchema): Record<string, unknown> {
  const out: Record<string, unknown> = { type: GEMINI_TYPE[s.type] };
  if (s.description) out.description = s.description;
  if (s.enum) out.enum = s.enum;
  if (s.nullable) out.nullable = true;
  if (s.properties) {
    out.properties = Object.fromEntries(
      Object.entries(s.properties).map(([k, v]) => [k, toGeminiSchema(v)]),
    );
  }
  if (s.items) out.items = toGeminiSchema(s.items);
  if (s.required) out.required = s.required;
  return out;
}

/** Translate a neutral schema to an OpenAI `strict` json_schema: every property
 * is `required`, objects set `additionalProperties:false`, and optional/nullable
 * properties become `["<type>","null"]` unions (OpenAI has no `nullable`). */
export function toOpenAiSchema(s: NeutralSchema): Record<string, unknown> {
  // Fix 3: guard against required naming a non-existent property
  if (s.type === "object" && s.required) {
    const missing = s.required.filter((k) => !(s.properties ?? {})[k]);
    if (missing.length) {
      throw new Error(`neutral_schema_required_not_in_properties:${missing.join(",")}`);
    }
  }

  // Fix 2: bare object (no properties) must still get additionalProperties:false
  if (s.type === "object") {
    const propsIn = s.properties ?? {};
    const keys = Object.keys(propsIn);
    const requiredSet = new Set(s.required ?? keys);
    const properties = Object.fromEntries(
      keys.map((k) => {
        const prop = propsIn[k];
        const optional = !requiredSet.has(k);
        const effective = optional && !prop.nullable ? { ...prop, nullable: true } : prop;
        return [k, toOpenAiSchema(effective)];
      }),
    );
    const out: Record<string, unknown> = {
      type: s.nullable ? ["object", "null"] : "object",
      properties,
      required: keys,
      additionalProperties: false,
    };
    if (s.description) out.description = s.description;
    return out;
  }

  const out: Record<string, unknown> = {
    type: s.nullable ? [s.type, "null"] : s.type,
  };
  if (s.description) out.description = s.description;
  // Fix 1: nullable enum must include null as a member for OpenAI strict mode
  if (s.enum) out.enum = s.nullable ? [...s.enum, null] : s.enum;
  if (s.items) out.items = toOpenAiSchema(s.items);
  return out;
}
