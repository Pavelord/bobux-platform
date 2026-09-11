process.env.BOBUX_API_NO_START = "1";

const { requestStudioAiPlan, sanitizeStudioAiContext, validateStudioAiPlan } = await import("./server.js");

const prompt = process.argv.slice(2).join(" ").trim()
  || "Создай небольшой дом с полом, четырьмя стенами, дверью и крышей";
const context = sanitizeStudioAiContext({ map_name: "AI smoke test" });
const rawPlan = await requestStudioAiPlan(prompt, context);
const validatedPlan = validateStudioAiPlan(rawPlan);

console.log(JSON.stringify({
  raw_type: Array.isArray(rawPlan) ? "array" : typeof rawPlan,
  raw_keys: rawPlan && typeof rawPlan === "object" ? Object.keys(rawPlan) : [],
  raw_plan: rawPlan,
  validated_message: validatedPlan.message,
  validated_action_count: validatedPlan.actions.length,
  validated_action_types: validatedPlan.actions.map((action) => action.type)
}, null, 2));

if (validatedPlan.actions.length === 0) process.exitCode = 2;
