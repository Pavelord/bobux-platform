import assert from "node:assert/strict";

process.env.BOBUX_API_NO_START = "1";
const { buildStudioAiFallback, ensureStudioAiPlanMatchesPrompt, sanitizeStudioAiContext, validateStudioAiPlan } = await import("./server.js");

const scriptRepair = validateStudioAiPlan({ actions: [{
  type: "update_script", target: "node:123", script_type: "LocalScript", parent: "StarterCharacterScripts",
  source: 'local text = [[\n&#x20;literal]]\n-- &#32;comment\n&#x20;print("a&#32;b")', disabled: false
}] }).actions[0];
assert.equal(scriptRepair.script_type, "LocalScript");
assert.equal(scriptRepair.parent, "StarterCharacterScripts");
assert.equal(scriptRepair.source, 'local text = [[\n&#x20;literal]]\n-- &#32;comment\n print("a&#32;b")');
const dependentEdit = validateStudioAiPlan({ actions: [
  {type: "create_model", id: "extension", name: "Extension", parts: [{name: "Part", size: [2, 2, 2]}]},
  {type: "create_script", parent: "action:extension", source: "print(script.Parent.Name)"},
  {type: "modify_object", target: "node:123", color: "#123456"}
] });
assert.equal(ensureStudioAiPlanMatchesPrompt(dependentEdit, "измени дом и добавь пристройку").actions.length, 3);

const context = sanitizeStudioAiContext({
  map_name: "A".repeat(300),
  selected_name: "Spawn",
  selected_position: [Number.POSITIVE_INFINITY, -200000, 12]
});
assert.equal(context.map_name.length, 120);
assert.deepEqual(context.selected_position, [0, -100000, 12]);

const plan = validateStudioAiPlan({
  message: "ready",
  actions: [
    {
      type: "create_part",
      name: "Bad/Name",
      shape: "ShellCommand",
      size: [-20, 9999, Number.NaN],
      position: [-9999, 9999, 1],
      color: "not-a-color",
      material: "Unknown",
      effects: [
        { type: "Fire", color: "#ff7814", rate: 9999 },
        { type: "ShellCommand" }
      ],
      interaction: { mode: "click", action: "toggle_effect", prompt: "Switch fire", max_distance: 999 }
    },
    {
      type: "create_script",
      name: "Logic",
      script_type: "Executable",
      parent: "Computer",
      source: "print('safe')"
    },
    {
      type: "modify_selected",
      color: "#123456",
      effects: [{ type: "PointLight", brightness: -50, range: 500 }]
    },
    { type: "delete_everything" }
  ]
});

assert.equal(plan.actions.length, 3);
assert.deepEqual(plan.actions[0].size, [0.1, 256, 2]);
assert.deepEqual(plan.actions[0].position, [-512, 512, 1]);
assert.equal(plan.actions[0].shape, "Box");
assert.equal(plan.actions[0].color, "#A3A2A5");
assert.equal(plan.actions[0].effects.length, 1);
assert.equal(plan.actions[0].effects[0].rate, 256);
assert.equal(plan.actions[0].interaction.action, "toggle_effect");
assert.equal(plan.actions[0].interaction.max_distance, 64);
assert.equal(plan.actions[1].script_type, "Script");
assert.equal(plan.actions[1].parent, "ServerScriptService");
assert.equal(plan.actions[2].color, "#123456");
assert.equal(plan.actions[2].effects[0].brightness, 0);
assert.equal(plan.actions[2].effects[0].range, 128);

const house = validateStudioAiPlan(buildStudioAiFallback("Создай небольшой синий дом", { map_name: "Test" }));
assert.equal(house.actions[0].type, "create_model");
assert.ok(house.actions[0].parts.length >= 24);
assert.equal(house.actions[0].parts[1].color, "#2584D8");
assert.ok(house.actions[0].parts.some((part) => part.material === "Glass"));
assert.ok(house.actions[0].parts.filter((part) => part.material === "Glass").length >= 5);

const incompleteProviderHouse = ensureStudioAiPlanMatchesPrompt(validateStudioAiPlan({
  message: "done",
  actions: [{
    type: "create_model",
    name: "House",
    parts: Array.from({ length: 20 }, (_, index) => ({
      name: index === 0 ? "Floor" : (index === 1 ? "Door" : (index === 2 ? "Roof" : `Wall${index}`)),
      shape: "Box",
      size: [24, 12, 18],
      position: [0, 6, 0]
    }))
  }]
}), "Создай подробный дом с окнами", { map_name: "Test" });
assert.ok(incompleteProviderHouse.actions[0].parts.filter((part) => part.material === "Glass").length >= 5);

const tinyHouse = validateStudioAiPlan({
  message: "tiny",
  actions: [{
    type: "create_model",
    name: "Tiny House",
    parts: [
      { name: "Floor", shape: "Box", size: [6, 0.5, 5], position: [0, 0, 0] },
      { name: "Wall", shape: "Box", size: [6, 3, 0.5], position: [0, 1.5, -2.25] },
      { name: "Door", shape: "Box", size: [1, 2, 0.3], position: [0, 1, 2.25] }
    ]
  }]
});
const tinyParts = tinyHouse.actions[0].parts;
const xMin = Math.min(...tinyParts.map(part => part.position[0] - part.size[0] / 2));
const xMax = Math.max(...tinyParts.map(part => part.position[0] + part.size[0] / 2));
const yMin = Math.min(...tinyParts.map(part => part.position[1] - part.size[1] / 2));
const yMax = Math.max(...tinyParts.map(part => part.position[1] + part.size[1] / 2));
const zMin = Math.min(...tinyParts.map(part => part.position[2] - part.size[2] / 2));
const zMax = Math.max(...tinyParts.map(part => part.position[2] + part.size[2] / 2));
assert.ok(xMax - xMin >= 24);
assert.ok(yMax - yMin >= 12);
assert.ok(zMax - zMin >= 18);

const collectible = validateStudioAiPlan(buildStudioAiFallback(
  "Поставь синий блок, пусть он парит в воздухе, горит огнем и его можно подобрать",
  { map_name: "Test" }
));
assert.equal(collectible.actions[0].type, "create_part");
assert.equal(collectible.actions[0].color, "#2584D8");
assert.equal(collectible.actions[0].position[1], 8);
assert.equal(collectible.actions[0].effects[0].type, "Fire");
assert.equal(collectible.actions[0].interaction.action, "collect");

const sky = validateStudioAiPlan(buildStudioAiFallback("Сделай ночное синее небо", { map_name: "Test" }));
assert.equal(sky.actions[0].type, "set_environment");
assert.equal(sky.actions[0].clock_time, 0);

const workingDoor = ensureStudioAiPlanMatchesPrompt(validateStudioAiPlan({
  message: "done",
  actions: [{
    type: "create_part",
    name: "Door",
    shape: "Box",
    size: [2, 3, 0.2],
    position: [0, 1.5, 0],
    anchored: true,
    can_collide: false
  }]
}), "Создай рабочую синюю дверь, которую можно открыть", { map_name: "Test" });
assert.equal(workingDoor.actions[0].type, "create_model");
const workingDoorPart = workingDoor.actions[0].parts.find(part => part.name === "Door");
assert.ok(workingDoorPart);
assert.ok(workingDoorPart.size[0] >= 4 && workingDoorPart.size[1] >= 7);
assert.equal(workingDoorPart.can_collide, true);
assert.equal(workingDoorPart.interaction.action, "toggle_door");

const physicsBall = ensureStudioAiPlanMatchesPrompt(validateStudioAiPlan({
  message: "done",
  actions: [{
    type: "create_part",
    name: "Ball",
    shape: "Sphere",
    size: [3, 3, 3],
    position: [0, 5, 0],
    anchored: true,
    can_collide: true
  }]
}), "Создай мяч с физикой, который можно катать и который прыгает", { map_name: "Test" });
assert.equal(physicsBall.actions[0].shape, "Sphere");
assert.equal(physicsBall.actions[0].anchored, false);
assert.equal(physicsBall.actions[0].physics_mode, "Dynamic");
assert.ok(physicsBall.actions[0].bounce >= 0.5);

const countryHouse = validateStudioAiPlan(buildStudioAiFallback("Создай большой подробный загородный дом с входом", { map_name: "Test" }));
assert.equal(countryHouse.actions[0].type, "create_model");
const countryParts = countryHouse.actions[0].parts;
const countryXMin = Math.min(...countryParts.map(part => part.position[0] - part.size[0] / 2));
const countryXMax = Math.max(...countryParts.map(part => part.position[0] + part.size[0] / 2));
const countryZMin = Math.min(...countryParts.map(part => part.position[2] - part.size[2] / 2));
const countryZMax = Math.max(...countryParts.map(part => part.position[2] + part.size[2] / 2));
assert.ok(countryXMax - countryXMin >= 40);
assert.ok(countryZMax - countryZMin >= 28);
assert.ok(countryParts.filter(part => part.material === "Glass").length >= 4);
assert.ok(countryParts.some(part => part.name === "Door" && part.interaction?.action === "toggle_door"));

const undersizedDetailedHouseParts = [
  { name: "Floor", shape: "Box", size: [24, 1, 18], position: [0, 0.5, 0] },
  { name: "WallFront", shape: "Box", size: [24, 10, 1], position: [0, 5, 8.5] },
  { name: "WallBack", shape: "Box", size: [24, 10, 1], position: [0, 5, -8.5] },
  { name: "WallLeft", shape: "Box", size: [1, 10, 18], position: [-11.5, 5, 0] },
  { name: "WallRight", shape: "Box", size: [1, 10, 18], position: [11.5, 5, 0] },
  { name: "Roof", shape: "Box", size: [24, 1, 18], position: [0, 11.5, 0] },
  {
    name: "Door", shape: "Box", size: [4, 8, 0.5], position: [0, 4, 8],
    anchored: true, can_collide: true,
    interaction: { action: "toggle_door", prompt: "Open", distance: 12 }
  },
  ...Array.from({ length: 5 }, (_, index) => ({
    name: `Window${index + 1}`, shape: "Box", size: [3, 3, 0.2],
    position: [-8 + index * 4, 6, 8], material: "Glass"
  })),
  ...Array.from({ length: 8 }, (_, index) => ({
    name: `Trim${index + 1}`, shape: "Box", size: [1, 1, 1],
    position: [-8 + index * 2, 10, -8]
  }))
];
const rejectedTinyCountryHouse = ensureStudioAiPlanMatchesPrompt(validateStudioAiPlan({
  message: "done",
  actions: [{ type: "create_model", name: "CountryHouse", parts: undersizedDetailedHouseParts }]
}), "Создай большой подробный загородный дом", { map_name: "Test" });
const rejectedCountryParts = rejectedTinyCountryHouse.actions[0].parts;
const rejectedCountryXMin = Math.min(...rejectedCountryParts.map(part => part.position[0] - part.size[0] / 2));
const rejectedCountryXMax = Math.max(...rejectedCountryParts.map(part => part.position[0] + part.size[0] / 2));
const rejectedCountryZMin = Math.min(...rejectedCountryParts.map(part => part.position[2] - part.size[2] / 2));
const rejectedCountryZMax = Math.max(...rejectedCountryParts.map(part => part.position[2] + part.size[2] / 2));
assert.ok(rejectedCountryXMax - rejectedCountryXMin >= 40);
assert.ok(rejectedCountryZMax - rejectedCountryZMin >= 28);

const hammer = validateStudioAiPlan(buildStudioAiFallback("Добавь игроку синий молоток в инвентарь", { map_name: "Test" }));
assert.equal(hammer.actions[0].type, "create_tool");
assert.equal(hammer.actions[0].tool_kind, "Hammer");
assert.equal(hammer.actions[0].color, "#2584D8");
assert.equal(hammer.actions[0].damage, 25);

const coin = validateStudioAiPlan(buildStudioAiFallback("Создай золотую монетку", { map_name: "Test" }));
assert.equal(coin.actions[0].type, "insert_asset");
assert.equal(coin.actions[0].asset, "Coin");
assert.deepEqual(coin.actions[0].rotation, [0, 0, 90]);
console.log("[bobux-api] Studio AI validation tests passed");

const assets = sanitizeStudioAiContext({asset_candidates: [
  {id: "kenney_house", name: "House", type: "model", role: "building", category: "Buildings", tags: ["house"]},
  {id: "kenney_shot", name: "Shot", type: "sound", role: "sound", category: "Weapons", tags: ["gunshot"]},
  {id: "../../secret", name: "Invalid", type: "model"}
]});
assert.equal(assets.asset_candidates.length, 2);
const assetHouse = validateStudioAiPlan({actions: [{type: "spawn_asset", id: "house", asset_id: "kenney_house"}]});
assert.equal(ensureStudioAiPlanMatchesPrompt(assetHouse, "Create a house", assets).actions[0].type, "spawn_asset");
assert.equal(ensureStudioAiPlanMatchesPrompt(assetHouse, "Create a house", {}).actions.length, 0);
assert.equal(ensureStudioAiPlanMatchesPrompt(validateStudioAiPlan({actions: [{type: "attach_sound", asset_id: "kenney_shot", parent: "node:123"}]}), "Edit selected object: add sound", assets).actions[0].parent, "node:123");
const customGun = validateStudioAiPlan({actions: [
  {type: "create_instance", class: "Tool", id: "gun", name: "CustomGun", parent: "StarterPack"},
  {type: "create_script", parent: "action:gun", source: "script.Parent.Activated:Connect(function() workspace:Raycast(Vector3.zero, Vector3.new(0,0,100)) end)"}
]});
assert.equal(ensureStudioAiPlanMatchesPrompt(customGun, "Create a pistol").actions[0].class, "Tool");
assert.equal(ensureStudioAiPlanMatchesPrompt(validateStudioAiPlan({actions: [{type: "create_part", name: "Zombie"}]}), "Create an NPC").actions.length, 0);
console.log("[bobux-api] Asset IDs, edits and scripted gameplay contracts passed");
