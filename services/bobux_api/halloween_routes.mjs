import express from "express";
import { isHalloweenItem } from "./halloween_event.mjs";

const invalid = (message, status = 400) => Object.assign(new Error(message), { status });
const defaultError = (res, error) => {
  const status = Number(error?.status) || 400;
  res.status(status >= 400 && status < 600 ? status : 400).json({ message: error?.message || "Request failed", status });
};

async function authenticatedUser(req, authenticate, adoptProfile, normalizeMissingAuth = false) {
  let user;
  try { user = await authenticate(req); }
  catch (error) {
    if (normalizeMissingAuth && !error?.status) throw invalid("Войдите в аккаунт.", 401);
    throw error;
  }
  if (typeof user?.record?.id !== "string" || !user.record.id.trim()) throw invalid("Войдите в аккаунт.", 401);
  await adoptProfile(user.record);
  return user.record.id;
}

// Keep the generic catalog route's ordinary-item behavior, but reserve event
// IDs before the ordinary grant callback can be reached (including target_id).
export function catalogItemHandler({ event, authenticate, adoptProfile = async () => {}, grantOrdinary, sendError = defaultError }) {
  return async (req, res) => {
    try {
      const userId = await authenticatedUser(req, authenticate, adoptProfile);
      const itemId = String(req.body?.item_id || req.body?.target_id || "").trim();
      const itemType = String(req.body?.item_type || "avatar_item").trim();
      if (!itemId) throw invalid("Catalog item is empty.");
      if (isHalloweenItem(itemId)) {
        res.setHeader("Cache-Control", "private, no-store");
        if (itemType !== "avatar_item") throw invalid("Invalid event item type.");
        const state = await event.state(userId, itemId);
        return res.status(201).json({ ...state, item_id: itemId, item_type: "avatar_item", owned: true });
      }
      const inventory = await grantOrdinary(userId, itemId, itemType);
      res.status(201).json({ ...inventory, item_id: itemId, item_type: itemType, owned: true });
    } catch (error) { sendError(res, error); }
  };
}

export function mountHalloweenRoutes(app, { event, authenticate, adoptProfile = async () => {}, sendError = defaultError }) {
  app.post("/api/rest/v1/rpc/halloween_event", express.json({ limit: "4kb" }), async (req, res) => {
    res.setHeader("Cache-Control", "private, no-store");
    try {
      const userId = await authenticatedUser(req, authenticate, adoptProfile, true);
      const claim = String(req.body?.claim || "").trim();
      if (claim && !isHalloweenItem(claim)) throw invalid("Unknown event accessory.");
      res.json(await event.state(userId, claim));
    } catch (error) { sendError(res, error); }
  });
}
