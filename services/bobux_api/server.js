import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import express from "express";

const PORT = Number(process.env.PORT || 3000);
const PB_URL = (process.env.POCKETBASE_URL || "http://127.0.0.1:8090").replace(/\/+$/, "");
const PUBLIC_BASE_URL = (process.env.PUBLIC_BASE_URL || "http://109.71.245.162").replace(/\/+$/, "");
const STORAGE_DIR = process.env.STORAGE_DIR || "/var/www/bobux/storage";
const POCKETBASE_DATA_DIR = process.env.POCKETBASE_DATA_DIR || "/opt/pocketbase/pb_data";
const SUPERUSER_EMAIL = process.env.POCKETBASE_SUPERUSER_EMAIL || "";
const SUPERUSER_PASSWORD = process.env.POCKETBASE_SUPERUSER_PASSWORD || "";
const HEARTBEAT_TOKEN = process.env.BOBUX_SERVER_HEARTBEAT_TOKEN || "";
const SESSION_TTL_SECONDS = 60 * 60 * 24 * 30;
const MAX_INLINE_THUMBNAIL_CHARS = 4500;
const MAX_INLINE_MAP_ASSET_CHARS = 3_000_000;
const MAX_INLINE_MAP_DATA_BYTES = 768 * 1024;
const MAX_PUBLIC_AVATAR_INLINE_TEXTURE_CHARS = 140_000;
const MAX_PUBLIC_AVATAR_ITEM_PAYLOADS = 6;

let superuserToken = "";
let superuserTokenExpiresAt = 0;
const mutationTails = new Map();

async function withMutationLock(key, task) {
  const previous = mutationTails.get(key) || Promise.resolve();
  const queued = previous.catch(() => undefined).then(task);
  mutationTails.set(key, queued);
  try {
    return await queued;
  } finally {
    if (mutationTails.get(key) === queued) mutationTails.delete(key);
  }
}

const collectionFields = {
  profiles: [
    text("external_id"), text("username"), text("status"), text("current_game"),
    text("current_server_host"), text("current_server_ip"), number("current_server_port"),
    text("created"), text("updated"), text("updated_at"), text("last_seen_at"), json("avatar_data"), json("inventory_items")
  ],
  maps: [
    text("external_id"), text("name"), text("owner_id"), text("owner_name"), text("description"),
    text("thumbnail"), text("cloud_version_id"), text("updated_at"), number("likes_count"),
    number("visits_count"), text("visibility"), bool("is_public"), json("data"), bool("is_published")
  ],
  active_servers: [
    text("server_key"), text("room_id"), text("player_id"), bool("is_host"), text("transport"),
    text("server_url"), text("ip"), number("port"), text("map_id"), text("map_name"),
    text("cloud_version_id"), text("host_user_id"), text("host_username"), json("member_user_ids"),
    number("players_count"), number("max_players"), text("status"), number("last_seen"),
    text("last_seen_at"), text("last_heartbeat")
  ],
  catalog_items: [
    text("external_id"), text("item_id"), text("name"), text("category"), text("asset_type"),
    text("thumbnail"), text("color")
  ],
  model_assets: [
    text("external_id"), text("name"), text("owner_id"), text("owner_name"), text("description"),
    text("thumbnail"), text("visibility"), bool("is_public"), text("asset_type"), text("source_url"),
    text("source_file_name"), json("data"), json("tags"), number("likes_count"), number("uses_count"),
    text("created_at"), text("updated_at")
  ],
  avatar_items: [
    text("external_id"), text("name"), text("owner_id"), text("owner_name"), text("description"),
    text("thumbnail"), text("visibility"), bool("is_public"), text("category"), text("asset_type"),
    text("template_url"), text("source_url"), text("model_id"), text("attachment_slot"),
    json("attachment_transform"), json("data"), number("price_robux"), number("likes_count"), text("created_at"),
    text("updated_at")
  ],
  asset_likes: [text("user_id"), text("target_type"), text("target_id"), text("created_at")],
  user_inventory: [text("user_id"), text("item_id"), text("item_type"), text("created_at")],
  avatar_outfits: [
    text("user_id"), text("head_color"), text("torso_color"), text("left_arm_color"),
    text("right_arm_color"), text("left_leg_color"), text("right_leg_color"),
    text("face_texture_path"), text("chest_badge_texture_path"), text("shirt_texture_path"), text("pants_texture_path"),
    json("saved_shirt_texture_paths"), json("saved_pants_texture_paths"),
    json("equipped_items"), text("body_type"), text("updated_at")
  ],
  friendships: [text("user1"), text("user2"), text("status"), text("created_at")],
  friend_requests: [text("from_user"), text("to_user"), text("status"), text("created_at")],
  follows: [text("follower_id"), text("following_id"), text("created_at")]
};

function text(name) {
  return { name, type: "text", required: false, presentable: false, system: false };
}

function number(name) {
  return { name, type: "number", required: false, presentable: false, system: false, onlyInt: false };
}

function bool(name) {
  return { name, type: "bool", required: false, presentable: false, system: false };
}

function json(name) {
  return { name, type: "json", required: false, presentable: false, system: false };
}

async function main() {
  const app = express();
  app.disable("x-powered-by");
  app.use((req, res, next) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, apikey, Prefer, X-Bobux-Server-Token, cache-control, x-upsert, Range");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, HEAD, OPTIONS");
    if (req.method === "OPTIONS") return res.sendStatus(204);
    next();
  });

  await ensureCollections();
  await seedCatalog();
  await seedDefaultMaps();
  await fs.mkdir(STORAGE_DIR, { recursive: true });
  await cleanupTechnicalMapRows();

  app.get("/api/health", (_req, res) => res.json({ ok: true, database: "pocketbase", storage: "local" }));

  app.post("/api/admin/login", express.json({ limit: "1mb" }), async (req, res) => {
    try {
      const identity = String(req.body?.identity || req.body?.email || "").trim();
      const password = String(req.body?.password || "");
      if (!identity || !password) return res.status(400).json({ message: "PocketBase admin login and password are required." });
      const auth = await pbFetch("/api/collections/_superusers/auth-with-password", {
        method: "POST",
        body: { identity, password }
      });
      res.json({
        token: auth.token,
        admin: {
          id: auth.record?.id || "",
          email: auth.record?.email || identity
        }
      });
    } catch (error) {
      sendError(res, error, 401);
    }
  });

  // PRACTICE SCREENSHOT: Admin statistics endpoint - shows database counts, active rooms, catalog items and storage size for the report.
  app.get("/api/admin/stats", async (req, res) => {
    try {
      await superuserFromRequest(req);
      res.json(await buildAdminStats());
    } catch (error) {
      sendError(res, error, 401);
    }
  });

  app.use((req, res, next) => {
    const startedAt = Date.now();
    res.on("finish", () => {
      if ((req.method !== "GET" && req.method !== "HEAD" && req.method !== "OPTIONS") || res.statusCode >= 400) {
        console.log(`[BobuxAPI] ${req.method} ${req.originalUrl} -> ${res.statusCode} in ${Date.now() - startedAt}ms`);
      }
    });
    next();
  });

  // PRACTICE SCREENSHOT: Registration route - creates a Bobux/PocketBase account and returns an authenticated session to the game client.
  app.post("/api/auth/v1/signup", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const body = req.body || {};
      const metadata = body.data || {};
      const anonymous = !body.email || !body.password;
      const email = anonymous ? `${crypto.randomUUID()}@anon.bobux.local` : String(body.email).trim().toLowerCase();
      const password = anonymous ? crypto.randomBytes(18).toString("base64url") : String(body.password);
      const username = cleanUsername(metadata.username || email.split("@")[0] || "Player");
      let user;
      const existingUsername = await findProfileByUsername(username);
      if (existingUsername) {
        const existingProfileUserId = String(existingUsername.id || "").trim();
        const existingAuthUser = (existingProfileUserId ? await getAuthUserById(existingProfileUserId) : null) || await findAuthUserByEmail(email);
        if (existingAuthUser) {
          return res.status(409).json({ code: "username_taken", msg: "That username is already taken." });
        }
        user = await pbUserCreate(email, password, username, anonymous, existingProfileUserId);
        const auth = await pbUserAuth(email, password);
        await upsertRow("profiles", { id: user.id, username, updated_at: nowIso() }, ["id"]);
        return res.json(toSupabaseSession(auth, anonymous, username));
      }
      try {
        user = await pbUserCreate(email, password, username, anonymous);
      } catch (error) {
        if (!anonymous && String(error.message || "").includes("400")) {
          return res.status(400).json({ code: "user_already_exists", msg: "User already registered" });
        }
        throw error;
      }
      const auth = await pbUserAuth(email, password);
      await upsertRow("profiles", { id: user.id, username, updated_at: nowIso() }, ["id"]);
      res.json(toSupabaseSession(auth, anonymous, username));
    } catch (error) {
      sendError(res, error);
    }
  });

  // PRACTICE SCREENSHOT: Login route - verifies username/password and issues the access token used by the network module.
  app.post("/api/auth/v1/token", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const grant = String(req.query.grant_type || "password");
      if (grant === "refresh_token") {
        const auth = await pbAuthRefresh(req.body?.refresh_token || bearerToken(req));
        await adoptProfileForUserRecord(auth.record);
        return res.json(toSupabaseSession(auth, false, auth.record?.name || auth.record?.username || ""));
      }
      const email = String(req.body?.email || "").trim().toLowerCase();
      const password = String(req.body?.password || "");
      const auth = await pbUserAuthWithUsernameFallback(email, password);
      await adoptProfileForUserRecord(auth.record);
      res.json(toSupabaseSession(auth, false, auth.record?.name || email.split("@")[0]));
    } catch (error) {
      sendError(res, error);
    }
  });

  app.get("/api/auth/v1/user", async (req, res) => {
    try {
      const user = await userFromRequest(req);
      res.json(toSupabaseUser(user.record, false));
    } catch (error) {
      sendError(res, error, 401);
    }
  });

  app.post("/api/rest/v1/rpc/get_friend_count", express.json({ limit: "5mb" }), async (req, res) => {
    const userId = String(req.body?.target_user || "").trim();
    const rows = await listRows("friendships", ["user1", "user2", "status"]);
    res.json(rows.filter((row) => row.status === "accepted" && (row.user1 === userId || row.user2 === userId)).length);
  });

  app.post("/api/rest/v1/rpc/get_follow_counts", express.json({ limit: "5mb" }), async (req, res) => {
    const userId = String(req.body?.target_user || "").trim();
    const rows = await listRows("follows");
    res.json({
      followers_count: rows.filter((row) => row.following_id === userId).length,
      following_count: rows.filter((row) => row.follower_id === userId).length
    });
  });

  app.post("/api/rest/v1/rpc/send_friend_request", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const user = await userFromRequest(req);
      await adoptProfileForUserRecord(user.record);
      const fromUser = user.record.id;
      const targetValue = String(req.body?.target_user || req.body?.to_user || "").trim();
      const targetUsername = String(req.body?.target_username || "").trim();
      if (!targetValue && !targetUsername) return res.status(400).json({ message: "Friend target user is empty." });
      let targetProfile = await resolveProfileReference(targetValue || targetUsername);
      if (!targetProfile && targetUsername && targetUsername !== targetValue) targetProfile = await resolveProfileReference(targetUsername);
      if (!targetProfile) return res.status(404).json({ message: "Player profile was not found." });
      const toUser = String(targetProfile.id || "").trim();
      if (fromUser === toUser) return res.status(400).json({ message: "You cannot add yourself as a friend." });
      const existingFriendship = await findFriendshipBetween(fromUser, toUser);
      if (existingFriendship) {
        await deleteFriendRequestsBetween(fromUser, toUser);
        return res.json({ already_friends: true, data: [existingFriendship], target_user: toUser, target_profile: sanitizePublicProfileOutput(targetProfile) });
      }
      const incoming = await findFriendRequest(toUser, fromUser);
      if (incoming) return res.json({ incoming_pending: true, data: [incoming], target_user: toUser, target_profile: sanitizePublicProfileOutput(targetProfile) });
      const outgoing = await findFriendRequest(fromUser, toUser);
      if (outgoing) return res.json({ pending: true, data: [outgoing], target_user: toUser, target_profile: sanitizePublicProfileOutput(targetProfile) });
      await deleteDuplicateFriendRequestsBetween(fromUser, toUser);
      const request = await createPbRecord("friend_requests", {
        from_user: fromUser,
        to_user: toUser,
        status: "pending",
        created_at: nowIso()
      });
      res.status(201).json({ pending: true, data: [fromPbRecord(request)], target_user: toUser, target_profile: sanitizePublicProfileOutput(targetProfile) });
    } catch (error) {
      sendError(res, error);
    }
  });

  app.post("/api/rest/v1/rpc/get_incoming_friend_requests", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const user = await userFromRequest(req);
      await adoptProfileForUserRecord(user.record);
      const rows = (await listRows("friend_requests", ["from_user", "to_user", "status", "created_at"])).filter((row) => row.to_user === user.record.id && row.status === "pending");
      rows.sort((a, b) => compare(b.created_at, a.created_at));
      const profileById = await buildPublicProfileIndex(rows.map((row) => row.from_user));
      const enriched = [];
      for (const row of rows) {
        const senderProfile = profileById.get(String(row.from_user || "").trim());
        if (!senderProfile) continue;
        enriched.push({ ...row, sender_profile: sanitizePublicProfileOutput(senderProfile) });
        if (enriched.length >= 100) break;
      }
      res.json(enriched);
    } catch (error) {
      sendError(res, error);
    }
  });

  app.post("/api/rest/v1/rpc/get_outgoing_friend_requests", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const user = await userFromRequest(req);
      await adoptProfileForUserRecord(user.record);
      const rows = (await listRows("friend_requests", ["from_user", "to_user", "status", "created_at"])).filter((row) => row.from_user === user.record.id && row.status === "pending");
      rows.sort((a, b) => compare(b.created_at, a.created_at));
      const profileById = await buildPublicProfileIndex(rows.map((row) => row.to_user));
      const enriched = [];
      for (const row of rows) {
        const targetProfile = profileById.get(String(row.to_user || "").trim());
        if (!targetProfile) continue;
        enriched.push({ ...row, target_profile: sanitizePublicProfileOutput(targetProfile) });
        if (enriched.length >= 100) break;
      }
      res.json(enriched);
    } catch (error) {
      sendError(res, error);
    }
  });

  app.post("/api/rest/v1/rpc/accept_friend_request", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const user = await userFromRequest(req);
      await adoptProfileForUserRecord(user.record);
      const senderValue = String(req.body?.from_user || "").trim();
      const senderUsername = String(req.body?.sender_username || "").trim();
      if (!senderValue && !senderUsername) return res.status(400).json({ message: "Friend request sender is empty." });
      let senderProfile = await resolveProfileReference(senderValue || senderUsername);
      if (!senderProfile && senderUsername && senderUsername !== senderValue) senderProfile = await resolveProfileReference(senderUsername);
      if (!senderProfile) return res.status(404).json({ message: "Friend request sender was not found." });
      const fromUser = String(senderProfile.id || "").trim();
      const pair = buildFriendshipPair(fromUser, user.record.id);
      const existing = await findFriendshipBetween(fromUser, user.record.id);
      const friendship = existing || fromPbRecord(await createPbRecord("friendships", {
        user1: pair.user1,
        user2: pair.user2,
        status: "accepted",
        created_at: nowIso()
      }));
      await deleteFriendRequestsBetween(fromUser, user.record.id);
      res.json(friendship);
    } catch (error) {
      sendError(res, error);
    }
  });

  app.post("/api/rest/v1/rpc/decline_friend_request", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const user = await userFromRequest(req);
      await adoptProfileForUserRecord(user.record);
      const senderValue = String(req.body?.from_user || "").trim();
      const senderUsername = String(req.body?.sender_username || "").trim();
      if (!senderValue && !senderUsername) return res.status(400).json({ message: "Friend request sender is empty." });
      let senderProfile = await resolveProfileReference(senderValue || senderUsername);
      if (!senderProfile && senderUsername && senderUsername !== senderValue) senderProfile = await resolveProfileReference(senderUsername);
      if (!senderProfile) return res.status(404).json({ message: "Friend request sender was not found." });
      const fromUser = String(senderProfile.id || "").trim();
      const deleted = await deleteFriendRequestsBetween(fromUser, user.record.id);
      res.json({ deleted_count: deleted });
    } catch (error) {
      sendError(res, error);
    }
  });

  app.post("/api/rest/v1/rpc/cancel_friend_request", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const user = await userFromRequest(req);
      await adoptProfileForUserRecord(user.record);
      const targetValue = String(req.body?.to_user || "").trim();
      const targetUsername = String(req.body?.target_username || "").trim();
      if (!targetValue && !targetUsername) return res.status(400).json({ message: "Friend request target is empty." });
      let targetProfile = await resolveProfileReference(targetValue || targetUsername);
      if (!targetProfile && targetUsername && targetUsername !== targetValue) targetProfile = await resolveProfileReference(targetUsername);
      if (!targetProfile) return res.status(404).json({ message: "Friend request target was not found." });
      const toUser = String(targetProfile.id || "").trim();
      const deleted = await deleteConcreteFriendRequest(user.record.id, toUser);
      res.json({ deleted_count: deleted });
    } catch (error) {
      sendError(res, error);
    }
  });

  app.post("/api/rest/v1/rpc/get_friends_list", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const user = await userFromRequest(req);
      await adoptProfileForUserRecord(user.record);
      const friendships = dedupeFriendshipsForUser(
        (await listRows("friendships", ["user1", "user2", "status", "created_at"])).filter((row) => row.status === "accepted" && (row.user1 === user.record.id || row.user2 === user.record.id)),
        user.record.id
      );
      const profileById = await buildPublicProfileIndex(friendships.map((row) => row.user1 === user.record.id ? row.user2 : row.user1));
      const outfitByUserId = await buildAvatarOutfitIndex(friendships.map((row) => row.user1 === user.record.id ? row.user2 : row.user1));
      const profiles = [];
      for (const row of friendships) {
        const friendId = row.user1 === user.record.id ? row.user2 : row.user1;
        const profile = profileById.get(String(friendId || "").trim());
        if (profile) profiles.push(sanitizePublicProfileOutput(mergePublicProfileWithAvatarOutfit(profile, outfitByUserId.get(String(friendId || "").trim()))));
        if (profiles.length >= 200) break;
      }
      res.json(dedupeProfilesByUsername(profiles));
    } catch (error) {
      sendError(res, error);
    }
  });

  // PRACTICE SCREENSHOT: Model publishing route - saves user-created 3D assets with owner, visibility and thumbnail metadata.
  app.post("/api/rest/v1/rpc/publish_model_asset", express.json({ limit: "80mb" }), async (req, res) => {
    try {
      const user = await userFromRequest(req);
      await adoptProfileForUserRecord(user.record);
      const payload = req.body || {};
      const modelName = String(payload.name || "Untitled Model").trim().slice(0, 80) || "Untitled Model";
      const now = nowIso();
      const modelId = String(payload.id || payload.model_id || crypto.randomUUID()).trim();
      const visibility = normalizeVisibility(payload.visibility || (payload.is_public === false ? "private" : "public"));
      const saved = await upsertRow("model_assets", {
        id: modelId,
        name: modelName,
        owner_id: user.record.id,
        owner_name: user.record.name || user.record.username || String(user.record.email || "Player").split("@")[0],
        description: String(payload.description || "").trim().slice(0, 1000),
        thumbnail: String(payload.thumbnail || "").trim(),
        visibility,
        is_public: visibility === "public",
        asset_type: String(payload.asset_type || "model").trim() || "model",
        source_url: String(payload.source_url || "").trim(),
        source_file_name: String(payload.source_file_name || "").trim(),
        data: payload.data && typeof payload.data === "object" ? payload.data : {},
        tags: Array.isArray(payload.tags) ? payload.tags.slice(0, 20) : [],
        likes_count: Number(payload.likes_count || 0),
        uses_count: Number(payload.uses_count || 0),
        created_at: String(payload.created_at || now),
        updated_at: now
      }, ["id"]);
      res.status(201).json(saved);
    } catch (error) {
      sendError(res, error);
    }
  });

  // PRACTICE SCREENSHOT: Avatar catalog publishing route - stores player-created clothes/accessories and grants ownership to the author.
  app.post("/api/rest/v1/rpc/publish_avatar_item", express.json({ limit: "80mb" }), async (req, res) => {
    try {
      const user = await userFromRequest(req);
      await adoptProfileForUserRecord(user.record);
      const payload = req.body || {};
      const itemName = String(payload.name || "Untitled Item").trim().slice(0, 80) || "Untitled Item";
      const now = nowIso();
      const itemId = String(payload.id || payload.item_id || crypto.randomUUID()).trim();
      const visibility = normalizeVisibility(payload.visibility || (payload.is_public === false ? "private" : "public"));
      const payloadData = payload.data && typeof payload.data === "object" ? payload.data : {};
      const category = String(payload.category || payload.item_kind || payloadData.category || payloadData.item_kind || "model").trim().toLowerCase() || "model";
      const saved = await upsertRow("avatar_items", {
        id: itemId,
        name: itemName,
        owner_id: user.record.id,
        owner_name: user.record.name || user.record.username || String(user.record.email || "Player").split("@")[0],
        description: String(payload.description || "").trim().slice(0, 1000),
        thumbnail: String(payload.thumbnail || "").trim(),
        visibility,
        is_public: visibility === "public",
        category,
        asset_type: String(payload.asset_type || "avatar_item").trim() || "avatar_item",
        template_url: String(payload.template_url || payloadData.template_url || payloadData.texture_path || "").trim(),
        source_url: String(payload.source_url || payloadData.source_url || payload.template_url || payloadData.template_url || "").trim(),
        model_id: String(payload.model_id || "").trim(),
        attachment_slot: String(payload.attachment_slot || "Head").trim(),
        attachment_transform: payload.attachment_transform && typeof payload.attachment_transform === "object" ? payload.attachment_transform : {},
        data: payloadData,
        price_robux: Number(payload.price_robux || 0),
        likes_count: Number(payload.likes_count || 0),
        created_at: String(payload.created_at || now),
        updated_at: now
      }, ["id"]);
      await grantInventoryItemToUser(user.record.id, itemId, "avatar_item");
      res.status(201).json({ ...saved, owned: true });
    } catch (error) {
      sendError(res, error);
    }
  });

  // PRACTICE SCREENSHOT: Marketplace loading route - returns public and owner-visible models for the catalog UI.
  app.post("/api/rest/v1/rpc/fetch_marketplace_models", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const user = await optionalUserFromRequest(req);
      if (user) await adoptProfileForUserRecord(user.record);
      const limit = clampLimit(req.body?.limit, 96);
      const includePrivate = Boolean(req.body?.include_private);
      const ownerOnly = Boolean(req.body?.owner_only);
      let rows = await listRows("model_assets");
      rows = rows.filter((row) => isVisibleMarketplaceRow(row, user?.record?.id || "", includePrivate, ownerOnly));
      rows.sort((a, b) => compare(b.updated_at || b.created_at, a.updated_at || a.created_at));
      res.json(rows.slice(0, limit).map((row) => sanitizeMarketplaceOutput(row)));
    } catch (error) {
      sendError(res, error);
    }
  });

  // PRACTICE SCREENSHOT: Avatar marketplace loading route - marks already owned items and filters private content by owner.
  app.post("/api/rest/v1/rpc/fetch_avatar_marketplace_items", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const user = await optionalUserFromRequest(req);
      if (user) await adoptProfileForUserRecord(user.record);
      const limit = clampLimit(req.body?.limit, 96);
      const includePrivate = Boolean(req.body?.include_private);
      const ownerOnly = Boolean(req.body?.owner_only);
      let rows = await listRows("avatar_items");
      rows = rows.filter((row) => isVisibleMarketplaceRow(row, user?.record?.id || "", includePrivate, ownerOnly));
      rows.sort((a, b) => compare(b.updated_at || b.created_at, a.updated_at || a.created_at));
      const ownedIds = user ? await getOwnedInventoryItemIds(user.record.id, "avatar_item") : new Set();
      res.json(rows.slice(0, limit).map((row) => {
        const output = sanitizeMarketplaceOutput(row);
        output.owned = Boolean(user && (row.owner_id === user.record.id || ownedIds.has(String(row.id || ""))));
        return output;
      }));
    } catch (error) {
      sendError(res, error);
    }
  });

  // PRACTICE SCREENSHOT: "My creations" route - gathers maps, models and avatar items created by the current user.
  app.post("/api/rest/v1/rpc/fetch_my_creations", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const user = await userFromRequest(req);
      await adoptProfileForUserRecord(user.record);
      const userId = user.record.id;
      const maps = (await listRows("maps")).filter((row) => rowBelongsToUser(row, user.record) && !isTechnicalCreationRow(row));
      const models = (await listRows("model_assets")).filter((row) => rowBelongsToUser(row, user.record));
      const avatarItems = (await listRows("avatar_items")).filter((row) => rowBelongsToUser(row, user.record));
      res.json({
        maps: maps.map((row) => sanitizeOutputRow("maps", row)),
        models: models.map((row) => sanitizeMarketplaceOutput(row)),
        avatar_items: avatarItems.map((row) => sanitizeMarketplaceOutput(row))
      });
    } catch (error) {
      sendError(res, error);
    }
  });

  app.post("/api/rest/v1/rpc/like_catalog_asset", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const user = await userFromRequest(req);
      await adoptProfileForUserRecord(user.record);
      const targetType = normalizeLikeTargetType(req.body?.target_type);
      const targetId = String(req.body?.target_id || "").trim();
      if (!targetType || !targetId) return res.status(400).json({ message: "Like target is empty." });
      const result = await withMutationLock(`like:${targetType}:${targetId}`, async () => {
        const existing = await findAssetLike(user.record.id, targetType, targetId);
        if (existing) return { already_liked: true, likes_count: await getLikesCountForTarget(targetType, targetId) };
        await createPbRecord("asset_likes", {
          user_id: user.record.id,
          target_type: targetType,
          target_id: targetId,
          created_at: nowIso()
        });
        return { liked: true, likes_count: await incrementLikesCount(targetType, targetId) };
      });
      res.status(result.liked ? 201 : 200).json(result);
    } catch (error) {
      sendError(res, error);
    }
  });

  app.post("/api/rest/v1/rpc/increment_map_visit", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const targetId = String(req.body?.target_id || req.body?.map_id || "").trim();
      if (!targetId) return res.status(400).json({ message: "Map id is empty." });
      const visitsCount = await incrementMapVisitCount(targetId);
      res.json({ visits_count: visitsCount });
    } catch (error) {
      sendError(res, error);
    }
  });

  app.post("/api/rest/v1/rpc/update_catalog_asset_visibility", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const user = await userFromRequest(req);
      await adoptProfileForUserRecord(user.record);
      const targetType = normalizeLikeTargetType(req.body?.target_type);
      const targetId = String(req.body?.target_id || "").trim();
      const visibility = normalizeVisibility(req.body?.visibility || "public");
      if (!targetType || !targetId) return res.status(400).json({ message: "Visibility target is empty." });
      const collection = collectionForLikeTarget(targetType);
      const rows = await listRows(collection);
      const row = rows.find((candidate) => candidate.id === targetId || candidate._pb_id === targetId);
      if (!row) return res.status(404).json({ message: "Catalog asset not found." });
      if (row.owner_id !== user.record.id) return res.status(403).json({ message: "Only the asset owner can change visibility." });
      const saved = await updatePbRecord(collection, row._pb_id || row.id, {
        visibility,
        is_public: visibility === "public",
        updated_at: nowIso()
      });
      res.json(sanitizeMarketplaceOutput(saved));
    } catch (error) {
      sendError(res, error);
    }
  });

  app.post("/api/rest/v1/rpc/delete_avatar_item", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const user = await userFromRequest(req);
      await adoptProfileForUserRecord(user.record);
      const itemId = String(req.body?.item_id || req.body?.target_id || "").trim();
      if (!itemId) return res.status(400).json({ message: "Avatar item id is empty." });
      const rows = await listRows("avatar_items");
      const row = rows.find((candidate) => String(candidate.id || "").trim() === itemId || String(candidate._pb_id || "").trim() === itemId);
      if (!row) return res.status(404).json({ message: "Avatar item not found." });
      if (row.owner_id !== user.record.id) return res.status(403).json({ message: "Only the item owner can delete this avatar item." });
      await pbDeleteRecord("avatar_items", row._pb_id);
      const inventoryRows = (await listRows("user_inventory")).filter((candidate) => String(candidate.item_id || "").trim() === itemId);
      for (const inventoryRow of inventoryRows) await pbDeleteRecord("user_inventory", inventoryRow._pb_id);
      const profile = await getProfileByExternalId(user.record.id);
      if (profile && profile._pb_id) {
        const inventoryItems = Array.isArray(profile.inventory_items) ? profile.inventory_items.map((value) => String(value)).filter((value) => value !== itemId) : [];
        const avatarData = profile.avatar_data && typeof profile.avatar_data === "object" ? { ...profile.avatar_data } : {};
        if (Array.isArray(avatarData.equipped)) avatarData.equipped = avatarData.equipped.map(String).filter((value) => value !== itemId);
        for (const key of ["owned_avatar_item_payloads", "equipped_avatar_item_payloads"]) {
          if (!Array.isArray(avatarData[key])) continue;
          avatarData[key] = avatarData[key].filter((payload) => String(payload?.id || payload?.item_id || "").trim() !== itemId);
        }
        await updatePbRecord("profiles", profile._pb_id, { inventory_items: inventoryItems, avatar_data: avatarData, updated_at: nowIso() });
      }
      res.json({ deleted: true, id: itemId });
    } catch (error) {
      sendError(res, error);
    }
  });

  app.post("/api/rest/v1/rpc/delete_model_asset", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const user = await userFromRequest(req);
      await adoptProfileForUserRecord(user.record);
      const modelId = String(req.body?.model_id || req.body?.target_id || "").trim();
      if (!modelId) return res.status(400).json({ message: "Model id is empty." });
      const rows = await listRows("model_assets");
      const row = rows.find((candidate) => String(candidate.id || "").trim() === modelId || String(candidate._pb_id || "").trim() === modelId);
      if (!row) return res.status(404).json({ message: "Model asset not found." });
      if (row.owner_id !== user.record.id) return res.status(403).json({ message: "Only the model owner can delete this asset." });
      await pbDeleteRecord("model_assets", row._pb_id);
      await fs.rm(
        path.join(STORAGE_DIR, "model-assets", safePathSegment(user.record.id), safePathSegment(String(row.id || modelId))),
        { recursive: true, force: true }
      );
      res.json({ deleted: true, id: modelId });
    } catch (error) {
      sendError(res, error);
    }
  });

  app.post("/api/rest/v1/rpc/get_catalog_item", express.json({ limit: "5mb" }), async (req, res) => {
    try {
      const user = await userFromRequest(req);
      await adoptProfileForUserRecord(user.record);
      const itemId = String(req.body?.item_id || req.body?.target_id || "").trim();
      const itemType = String(req.body?.item_type || "avatar_item").trim();
      if (!itemId) return res.status(400).json({ message: "Catalog item is empty." });
      const inventory = await grantInventoryItemToUser(user.record.id, itemId, itemType);
      res.status(201).json({ ...inventory, item_id: itemId, item_type: itemType, owned: true });
    } catch (error) {
      sendError(res, error);
    }
  });

  app.post("/api/rest/v1/rpc/delete_own_maps_by_name_and_cleanup", express.json({ limit: "5mb" }), async (req, res) => {
    const user = await userFromRequest(req);
    const targetName = String(req.body?.target_map_name || "").trim();
    const rows = (await listRows("maps")).filter((row) => row.name === targetName && rowBelongsToUser(row, user.record));
    const deleted = await deleteRowsAndStorage(rows);
    res.json({ deleted_count: deleted });
  });

  app.post("/api/rest/v1/rpc/delete_own_map_and_cleanup", express.json({ limit: "5mb" }), async (req, res) => {
    const user = await userFromRequest(req);
    const targetId = String(req.body?.target_map_id || "").trim();
    const rows = (await listRows("maps")).filter((row) => row.id === targetId && rowBelongsToUser(row, user.record));
    const deleted = await deleteRowsAndStorage(rows);
    res.json({ deleted_count: deleted });
  });

  // PRACTICE SCREENSHOT: REST compatibility layer - exposes PocketBase collections through Supabase-like CRUD endpoints.
  app.get("/api/rest/v1/:collection", async (req, res) => {
    try {
      assertCollection(req.params.collection);
      const rows = await queryRows(req.params.collection, req.query);
      res.json(rows);
    } catch (error) {
      sendError(res, error);
    }
  });

  app.post("/api/rest/v1/:collection", express.json({ limit: "80mb" }), async (req, res) => {
    try {
      assertCollection(req.params.collection);
      const payloads = Array.isArray(req.body) ? req.body : [req.body || {}];
      const conflictKeys = conflictKeysFromQuery(req.query, req.params.collection);
      const saved = [];
      for (const payload of payloads) saved.push(await upsertRow(req.params.collection, payload, conflictKeys));
      const responseRows = saved.map((row) => sanitizeOutputRow(req.params.collection, row));
      res.status(201).json(Array.isArray(req.body) ? responseRows : responseRows[0]);
    } catch (error) {
      sendError(res, error);
    }
  });

  app.patch("/api/rest/v1/:collection", express.json({ limit: "80mb" }), async (req, res) => {
    try {
      assertCollection(req.params.collection);
      const rows = await queryRows(req.params.collection, req.query, false);
      const updated = [];
      for (const row of rows) {
        updated.push(await updatePbRecord(req.params.collection, row._pb_id, sanitizeForStorage(req.body || {})));
      }
      res.json(updated.map(fromPbRecord).map((row) => sanitizeOutputRow(req.params.collection, row)));
    } catch (error) {
      sendError(res, error);
    }
  });

  app.delete("/api/rest/v1/:collection", async (req, res) => {
    try {
      assertCollection(req.params.collection);
      const rows = await queryRows(req.params.collection, req.query, false);
      for (const row of rows) await pbDeleteRecord(req.params.collection, row._pb_id);
      res.status(204).send("");
    } catch (error) {
      sendError(res, error);
    }
  });

  // PRACTICE SCREENSHOT: Storage upload endpoint - accepts map thumbnails, avatar textures and model assets from the client.
  app.post("/api/storage/v1/object/:bucket/*", express.raw({ type: "*/*", limit: "512mb" }), async (req, res) => {
    try {
      const relPath = safeObjectPath(`${req.params.bucket}/${req.params[0] || ""}`);
      const target = path.join(STORAGE_DIR, relPath);
      await fs.mkdir(path.dirname(target), { recursive: true });
      await fs.writeFile(target, req.body || Buffer.alloc(0));
      res.status(201).json({
        Key: relPath,
        publicUrl: `${PUBLIC_BASE_URL}/api/storage/v1/object/public/${relPath}`
      });
    } catch (error) {
      sendError(res, error);
    }
  });

  // PRACTICE SCREENSHOT: Public storage endpoint - serves uploaded media back to the game and website.
  app.get("/api/storage/v1/object/public/:bucket/*", async (req, res) => {
    const relPath = safeObjectPath(`${req.params.bucket}/${req.params[0] || ""}`);
    res.sendFile(path.join(STORAGE_DIR, relPath), (error) => {
      if (error && !res.headersSent) res.status(404).json({ message: "Object not found" });
    });
  });

  app.head("/api/storage/v1/object/public/:bucket/*", async (req, res) => {
    try {
      const relPath = safeObjectPath(`${req.params.bucket}/${req.params[0] || ""}`);
      const stat = await fs.stat(path.join(STORAGE_DIR, relPath));
      res.setHeader("Content-Length", String(stat.size));
      res.status(200).send("");
    } catch {
      res.status(404).send("");
    }
  });

  app.listen(PORT, "127.0.0.1", () => {
    console.log(`Bobux API listening on 127.0.0.1:${PORT}`);
  });
}

function assertCollection(collection) {
  if (!Object.prototype.hasOwnProperty.call(collectionFields, collection)) {
    throw new Error(`Unknown collection: ${collection}`);
  }
}

async function ensureCollections() {
  await ensureSuperuserToken();
  for (const [name, fields] of Object.entries(collectionFields)) {
    const existing = await pbFetch(`/api/collections/${name}`, { admin: true, allow404: true });
    if (existing) {
      await ensureCollectionFields(name, existing, fields);
      continue;
    }
    await pbFetch("/api/collections", {
      method: "POST",
      admin: true,
      body: {
        name,
        type: "base",
        fields,
        listRule: "",
        viewRule: "",
        createRule: "",
        updateRule: "",
        deleteRule: ""
      }
    });
    console.log(`Created PocketBase collection ${name}`);
  }
}

async function ensureCollectionFields(name, existingCollection, desiredFields) {
  const currentFields = Array.isArray(existingCollection.fields) ? existingCollection.fields : [];
  const currentNames = new Set(currentFields.map((field) => field.name));
  const missingFields = desiredFields.filter((field) => !currentNames.has(field.name));
  if (missingFields.length === 0) return;
  await pbFetch(`/api/collections/${name}`, {
    method: "PATCH",
    admin: true,
    body: { fields: [...currentFields, ...missingFields] }
  });
  console.log(`Updated PocketBase collection ${name}: added ${missingFields.map((field) => field.name).join(", ")}`);
}

async function seedCatalog() {
  const legacyIds = new Set(["classic_head", "blue_torso", "green_legs"]);
  const rows = await listRows("catalog_items", ["id", "item_id", "asset_type"]);
  for (const row of rows) {
    const legacyId = String(row.item_id || row.id || "").trim();
    if (legacyIds.has(legacyId) || String(row.asset_type || "").trim() === "part") {
      await pbFetch(`/api/collections/catalog_items/records/${row._pb_id}`, { method: "DELETE", admin: true });
    }
  }
}

async function seedDefaultMaps() {
  const maps = await listRows("maps");
  if (maps.length > 0) return;
  const updatedAt = nowIso();
  await upsertRow("maps", {
    id: "classic",
    name: "Classic Baseplate",
    owner_id: "bobux",
    owner_name: "Bobux",
    description: "A clean starter world for testing movement, spawns, chat, and multiplayer.",
    thumbnail: "",
    cloud_version_id: "seed-classic-1",
    updated_at: updatedAt,
    likes_count: 0,
    visits_count: 0,
    is_published: true,
    data: {
      time_of_day: 12.0,
      player_settings: {},
      mode_settings: {
        music_playlist: [],
        music_volume: 0.45
      },
      blocks: [
        {
          name: "Spawn",
          px: 0.0,
          py: 0.15,
          pz: 0.0,
          rx: 0.0,
          ry: 0.0,
          rz: 0.0,
          sx: 6.0,
          sy: 0.3,
          sz: 6.0,
          cr: 0.2,
          cg: 0.72,
          cb: 0.28,
          ca: 1.0,
          shape: "Spawn",
          material: "Plastic",
          transparency: 0.0,
          can_collide: true,
          deals_damage: false,
          damage_amount: 0,
          is_spawn: true
        },
        {
          name: "Baseplate",
          px: 0.0,
          py: -0.2,
          pz: 0.0,
          rx: 0.0,
          ry: 0.0,
          rz: 0.0,
          sx: 96.0,
          sy: 0.4,
          sz: 96.0,
          cr: 0.42,
          cg: 0.66,
          cb: 0.38,
          ca: 1.0,
          shape: "Box",
          material: "Grass",
          transparency: 0.0,
          can_collide: true,
          deals_damage: false,
          damage_amount: 0,
          is_spawn: false
        }
      ]
    }
  }, ["id"]);
  console.log("Seeded default Classic Baseplate map.");
}

async function ensureSuperuserToken() {
  if (superuserToken && Date.now() < superuserTokenExpiresAt) return superuserToken;
  if (!SUPERUSER_EMAIL || !SUPERUSER_PASSWORD) throw new Error("PocketBase superuser credentials are not configured.");
  const auth = await pbFetch("/api/collections/_superusers/auth-with-password", {
    method: "POST",
    body: { identity: SUPERUSER_EMAIL, password: SUPERUSER_PASSWORD }
  });
  superuserToken = auth.token;
  superuserTokenExpiresAt = Date.now() + 1000 * 60 * 60 * 6;
  return superuserToken;
}

async function pbFetch(endpoint, options = {}) {
  const headers = { Accept: "application/json" };
  if (options.body !== undefined) headers["Content-Type"] = "application/json";
  if (options.admin) headers.Authorization = `Bearer ${await ensureSuperuserToken()}`;
  if (options.token) headers.Authorization = `Bearer ${options.token}`;
  const response = await fetch(`${PB_URL}${endpoint}`, {
    method: options.method || "GET",
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body)
  });
  if (options.allow404 && response.status === 404) return null;
  const textBody = await response.text();
  const parsed = textBody ? JSON.parse(textBody) : {};
  if (!response.ok) {
    const message = parsed?.message || textBody || `PocketBase request failed with ${response.status}`;
    const error = new Error(`${response.status}: ${message}`);
    error.status = response.status;
    error.body = parsed;
    throw error;
  }
  return parsed;
}

async function pbUserCreate(email, password, username, anonymous, recordId = "") {
  const body = {
    email,
    password,
    passwordConfirm: password,
    verified: true,
    name: username,
    is_anonymous: anonymous
  };
  const cleanRecordId = String(recordId || "").trim();
  if (cleanRecordId) body.id = cleanRecordId;
  return await pbFetch("/api/collections/users/records", {
    method: "POST",
    admin: true,
    body
  });
}

async function getAuthUserById(userId) {
  const cleanUserId = String(userId || "").trim();
  if (!cleanUserId) return null;
  return await pbFetch(`/api/collections/users/records/${encodeURIComponent(cleanUserId)}`, {
    admin: true,
    allow404: true
  });
}

async function findAuthUserByEmail(email) {
  const cleanEmail = String(email || "").trim().toLowerCase();
  if (!cleanEmail) return null;
  const rows = await listAuthUsers();
  return rows.find((row) => String(row.email || "").trim().toLowerCase() === cleanEmail) || null;
}

async function findAuthUserForLoginIdentifier(identifier) {
  const cleanIdentifier = String(identifier || "").trim().toLowerCase();
  if (!cleanIdentifier) return null;
  const directUser = await findAuthUserByEmail(cleanIdentifier);
  if (directUser) return directUser;
  const usernameCandidate = usernameFromAuthIdentifier(cleanIdentifier);
  if (!usernameCandidate) return null;

  const profile = await findProfileByUsername(usernameCandidate);
  if (profile && profile.id) {
    const profileUser = await getAuthUserById(profile.id);
    if (profileUser) return profileUser;
  }

  const rows = await listAuthUsers();
  const candidateLower = usernameCandidate.toLowerCase();
  const candidatePrefix = `${candidateLower}-`;
  return rows.find((row) => {
    const rowName = cleanUsername(row.name || row.username || "").toLowerCase();
    const rowEmail = String(row.email || "").trim().toLowerCase();
    return rowName === candidateLower || rowEmail.startsWith(candidatePrefix);
  }) || null;
}

function usernameFromAuthIdentifier(identifier) {
  const cleanIdentifier = String(identifier || "").trim().toLowerCase();
  if (!cleanIdentifier) return "";
  const localPart = cleanIdentifier.includes("@") ? cleanIdentifier.split("@")[0] : cleanIdentifier;
  const withoutHashSuffix = localPart.replace(/-[a-f0-9]{8}$/i, "");
  const username = withoutHashSuffix.replace(/[^a-z0-9_-]+/g, "_").replace(/^_+|_+$/g, "");
  return username.length >= 3 ? username : "";
}

async function listAuthUsers() {
  const users = [];
  let page = 1;
  while (true) {
    const result = await pbFetch(`/api/collections/users/records?page=${page}&perPage=500`, { admin: true });
    users.push(...(result.items || []));
    if (page >= Number(result.totalPages || 1)) break;
    page += 1;
  }
  return users;
}

async function pbUserAuth(email, password) {
  return await pbFetch("/api/collections/users/auth-with-password", {
    method: "POST",
    body: { identity: email, password }
  });
}

async function pbUserAuthWithUsernameFallback(email, password) {
  try {
    return await pbUserAuth(email, password);
  } catch (error) {
    if (![400, 401, 404].includes(Number(error?.status || 0))) throw error;
    const fallbackUser = await findAuthUserForLoginIdentifier(email);
    const fallbackEmail = String(fallbackUser?.email || "").trim().toLowerCase();
    if (!fallbackEmail || fallbackEmail === String(email || "").trim().toLowerCase()) throw error;
    console.warn(`[BobuxAPI] Password login fallback resolved '${email}' to existing auth user '${fallbackUser.id}'.`);
    return await pbUserAuth(fallbackEmail, password);
  }
}

async function pbAuthRefresh(token) {
  return await pbFetch("/api/collections/users/auth-refresh", {
    method: "POST",
    token: String(token || "").replace(/^Bearer\s+/i, "")
  });
}

async function userFromRequest(req) {
  const token = bearerToken(req);
  if (!token) throw new Error("Missing bearer token");
  return await pbAuthRefresh(token);
}

async function optionalUserFromRequest(req) {
  try {
    return await userFromRequest(req);
  } catch {
    return null;
  }
}

async function superuserFromRequest(req) {
  const token = bearerToken(req);
  if (!token) throw new Error("Missing PocketBase admin token");
  return await pbFetch("/api/collections/_superusers/auth-refresh", {
    method: "POST",
    token
  });
}

// PRACTICE SCREENSHOT: Database statistics aggregation - combines PocketBase users, maps, active servers, catalog assets and friendships.
async function buildAdminStats() {
  const [
    authUsers,
    profiles,
    maps,
    activeServers,
    modelAssets,
    avatarItems,
    catalogItems,
    inventoryItems,
    friendships
  ] = await Promise.all([
    listAuthUsers(),
    listRows("profiles", ["id", "username", "status", "current_game", "last_seen_at", "updated_at"]),
    listRows("maps", ["id", "name", "owner_id", "owner_name", "is_public", "is_published", "visits_count", "likes_count", "updated_at"]),
    listRows("active_servers", ["server_key", "room_id", "map_id", "map_name", "players_count", "max_players", "status", "last_seen", "last_seen_at", "host_user_id", "host_username", "member_user_ids"]),
    listRows("model_assets", ["id", "owner_id", "owner_name", "is_public", "visibility", "likes_count", "uses_count", "updated_at"]),
    listRows("avatar_items", ["id", "owner_id", "owner_name", "is_public", "visibility", "category", "likes_count", "updated_at"]),
    listRows("catalog_items", ["id", "name", "category", "asset_type"]),
    listRows("user_inventory", ["user_id", "item_id", "item_type", "created_at"]),
    listRows("friendships", ["user1", "user2", "status", "created_at"])
  ]);
  const liveServers = activeServers.filter(isLiveServerRow);
  const storageStats = await buildStorageStats();
  const collectionCounts = {
    profiles: profiles.length,
    maps: maps.length,
    active_servers: activeServers.length,
    model_assets: modelAssets.length,
    avatar_items: avatarItems.length,
    catalog_items: catalogItems.length,
    user_inventory: inventoryItems.length,
    friendships: friendships.length
  };
  const onlineUserIds = new Set();
  let playersOnline = 0;
  for (const server of liveServers) {
    const members = Array.isArray(server.member_user_ids) ? server.member_user_ids.map(String).filter(Boolean) : [];
    for (const userId of members) onlineUserIds.add(userId);
    if (server.host_user_id) onlineUserIds.add(String(server.host_user_id));
    playersOnline += Math.max(Number(server.players_count || 0), members.length);
  }
  const publicMaps = maps.filter((row) => row.is_public !== false && row.is_published !== false);
  const privateMaps = maps.length - publicMaps.length;
  const totalVisits = maps.reduce((sum, row) => sum + Number(row.visits_count || 0), 0);
  const totalLikes = maps.reduce((sum, row) => sum + Number(row.likes_count || 0), 0);
  const topMaps = [...maps]
    .sort((a, b) => (Number(b.visits_count || 0) - Number(a.visits_count || 0)) || (Number(b.likes_count || 0) - Number(a.likes_count || 0)))
    .slice(0, 12)
    .map((row) => ({
      id: row.id,
      name: row.name || "Untitled",
      owner_name: row.owner_name || "",
      visits_count: Number(row.visits_count || 0),
      likes_count: Number(row.likes_count || 0),
      is_public: row.is_public !== false,
      is_published: row.is_published !== false,
      updated_at: row.updated_at || ""
    }));
  return {
    generated_at: nowIso(),
    pocketbase_url: PB_URL,
    public_base_url: PUBLIC_BASE_URL,
    database: {
      engine: "PocketBase",
      collection_counts: collectionCounts,
      pocketbase_data_bytes: storageStats.pocketbase_data_bytes,
      pocketbase_data_mb: storageStats.pocketbase_data_mb
    },
    storage: {
      public_storage_dir: STORAGE_DIR,
      public_storage_bytes: storageStats.public_storage_bytes,
      public_storage_mb: storageStats.public_storage_mb
    },
    accounts: {
      auth_users: authUsers.length,
      profiles: profiles.length,
      anonymous_users: authUsers.filter((row) => Boolean(row.is_anonymous)).length,
      named_profiles: profiles.filter((row) => String(row.username || "").trim()).length
    },
    realtime: {
      players_online: playersOnline,
      unique_users_online: onlineUserIds.size,
      active_servers: liveServers.length,
      total_server_records: activeServers.length,
      servers: liveServers.slice(0, 20).map((row) => ({
        room_id: row.room_id || "",
        map_id: row.map_id || "",
        map_name: row.map_name || "",
        players_count: Number(row.players_count || 0),
        max_players: Number(row.max_players || 0),
        host_username: row.host_username || "",
        last_seen_at: row.last_seen_at || "",
        status: row.status || ""
      }))
    },
    creation: {
      maps: maps.length,
      public_maps: publicMaps.length,
      private_maps: privateMaps,
      map_creators: new Set(maps.map((row) => String(row.owner_id || "")).filter(Boolean)).size,
      total_visits: totalVisits,
      total_likes: totalLikes,
      model_assets: modelAssets.length,
      public_model_assets: modelAssets.filter(isPublicAssetRow).length,
      avatar_items: avatarItems.length,
      public_avatar_items: avatarItems.filter(isPublicAssetRow).length,
      catalog_items: catalogItems.length,
      inventory_records: inventoryItems.length
    },
    social: {
      friendships: friendships.filter((row) => row.status === "accepted").length
    },
    top_maps: topMaps
  };
}

async function buildStorageStats() {
  const [publicStorageBytes, pocketbaseDataBytes] = await Promise.all([
    dirSizeBytes(STORAGE_DIR),
    dirSizeBytes(POCKETBASE_DATA_DIR)
  ]);
  return {
    public_storage_bytes: publicStorageBytes,
    public_storage_mb: roundMegabytes(publicStorageBytes),
    pocketbase_data_bytes: pocketbaseDataBytes,
    pocketbase_data_mb: roundMegabytes(pocketbaseDataBytes)
  };
}

function roundMegabytes(bytes) {
  return Math.round((Number(bytes || 0) / 1024 / 1024) * 100) / 100;
}

async function dirSizeBytes(targetDir) {
  let total = 0;
  let entries = [];
  try {
    entries = await fs.readdir(targetDir, { withFileTypes: true });
  } catch {
    return 0;
  }
  for (const entry of entries) {
    const entryPath = path.join(targetDir, entry.name);
    try {
      if (entry.isDirectory()) {
        total += await dirSizeBytes(entryPath);
      } else if (entry.isFile()) {
        const stat = await fs.stat(entryPath);
        total += stat.size;
      }
    } catch {
      // Ignore files that disappear while stats are being collected.
    }
  }
  return total;
}

function isLiveServerRow(row) {
  const status = String(row.status || "").toLowerCase();
  if (status && ["offline", "closed", "stopped", "dead"].includes(status)) return false;
  const seen = Number(row.last_seen || 0);
  let seenMs = 0;
  if (Number.isFinite(seen) && seen > 0) seenMs = seen > 10_000_000_000 ? seen : seen * 1000;
  if (!seenMs && row.last_seen_at) {
    const parsed = Date.parse(row.last_seen_at);
    if (Number.isFinite(parsed)) seenMs = parsed;
  }
  if (!seenMs) return false;
  return Date.now() - seenMs <= 180_000;
}

function isPublicAssetRow(row) {
  const visibility = String(row.visibility || "").toLowerCase();
  return row.is_public !== false && visibility !== "private";
}

function bearerToken(req) {
  const header = String(req.headers.authorization || "");
  return header.replace(/^Bearer\s+/i, "").trim();
}

function toSupabaseSession(auth, anonymous, username) {
  const record = auth.record || {};
  return {
    access_token: auth.token,
    refresh_token: auth.token,
    token_type: "bearer",
    expires_in: SESSION_TTL_SECONDS,
    expires_at: Math.floor(Date.now() / 1000) + SESSION_TTL_SECONDS,
    user: toSupabaseUser(record, anonymous, username)
  };
}

function toSupabaseUser(record, anonymous, username = "") {
  return {
    id: record.id,
    email: record.email || "",
    is_anonymous: Boolean(anonymous || record.is_anonymous),
    user_metadata: {
      username: username || record.name || String(record.email || "Player").split("@")[0]
    }
  };
}

async function listRows(collection, requestedFields = []) {
  const records = [];
  let page = 1;
  const fields = normalizePocketBaseFields(collection, requestedFields);
  const fieldsQuery = fields.length > 0 ? `&fields=${encodeURIComponent(fields.join(","))}` : "";
  while (true) {
    const result = await pbFetch(`/api/collections/${collection}/records?page=${page}&perPage=500${fieldsQuery}`, { admin: true });
    for (const item of result.items || []) records.push(fromPbRecord(item));
    if (page >= Number(result.totalPages || 1)) break;
    page += 1;
  }
  return records;
}

async function queryRows(collection, rawQuery, applyLimit = true) {
  let rows = await listRows(collection, fieldsNeededForQuery(collection, rawQuery));
  rows = rows.filter((row) => matchesQuery(row, rawQuery));
  rows = applyOrder(rows, rawQuery.order);
  rows = rows.map((row) => sanitizeOutputRow(collection, row));
  if (applyLimit && rawQuery.limit) rows = rows.slice(0, Math.max(0, Number(rawQuery.limit)));
  if (applyLimit && rawQuery.select) rows = applySelect(rows, rawQuery.select);
  return rows;
}

function normalizePocketBaseFields(collection, requestedFields = []) {
  if (!Array.isArray(requestedFields) || requestedFields.length === 0) return [];
  const allowed = new Set(collectionFields[collection].map((field) => field.name));
  const output = new Set(["id"]);
  for (const rawField of requestedFields) {
    const field = String(rawField || "").trim();
    if (!field || field === "*") return [];
    if (field === "id") {
      output.add("external_id");
      continue;
    }
    if (allowed.has(field)) output.add(field);
  }
  return Array.from(output);
}

function fieldsNeededForQuery(collection, rawQuery = {}) {
  const fields = new Set(parseSelectFields(rawQuery.select));
  for (const key of Object.keys(rawQuery || {})) {
    if (["select", "order", "limit", "on_conflict"].includes(key)) continue;
    if (key === "or") {
      for (const orField of parseOrFilterFields(rawQuery[key])) fields.add(orField);
      continue;
    }
    fields.add(key);
  }
  if (rawQuery.order) {
    for (const orderPart of String(rawQuery.order).split(",")) {
      const field = orderPart.split(".")[0].trim();
      if (field) fields.add(field);
    }
  }
  return Array.from(fields);
}

function parseOrFilterFields(value) {
  const fields = [];
  const values = Array.isArray(value) ? value : [value];
  for (const rawValue of values) {
    const inner = stripWrappingParens(String(rawValue || ""));
    for (const group of splitTopLevel(inner)) {
      const groupInner = unwrapFilterFunction(group, "and");
      for (const part of splitTopLevel(groupInner)) {
        const field = part.split(".")[0].trim();
        if (field && !fields.includes(field)) fields.push(field);
      }
    }
  }
  return fields;
}

function splitTopLevel(source) {
  const output = [];
  let current = "";
  let depth = 0;
  for (const char of String(source || "")) {
    if (char === "(") depth += 1;
    if (char === ")") depth = Math.max(0, depth - 1);
    if (char === "," && depth === 0) {
      if (current.trim()) output.push(current.trim());
      current = "";
    } else {
      current += char;
    }
  }
  if (current.trim()) output.push(current.trim());
  return output;
}

function stripWrappingParens(value) {
  const trimmed = String(value || "").trim();
  if (trimmed.startsWith("(") && trimmed.endsWith(")")) return trimmed.slice(1, -1);
  return trimmed;
}

function unwrapFilterFunction(value, functionName) {
  const trimmed = String(value || "").trim();
  const prefix = `${functionName}(`;
  if (trimmed.startsWith(prefix) && trimmed.endsWith(")")) return trimmed.slice(prefix.length, -1);
  return trimmed;
}

function applySelect(rows, selectExpression) {
  const fields = parseSelectFields(selectExpression);
  if (fields.length === 0 || fields.includes("*")) return rows;
  return rows.map((row) => {
    const selected = {};
    for (const field of fields) {
      if (Object.prototype.hasOwnProperty.call(row, field)) selected[field] = row[field];
    }
    return selected;
  });
}

function parseSelectFields(selectExpression) {
  const source = String(Array.isArray(selectExpression) ? selectExpression[0] : selectExpression || "").trim();
  if (!source) return [];
  const fields = [];
  let current = "";
  let depth = 0;
  for (const char of source) {
    if (char === "(") depth += 1;
    if (char === ")") depth = Math.max(0, depth - 1);
    if (char === "," && depth === 0) {
      pushSelectField(fields, current);
      current = "";
    } else {
      current += char;
    }
  }
  pushSelectField(fields, current);
  return fields;
}

function pushSelectField(fields, rawField) {
  const trimmed = String(rawField || "").trim();
  if (!trimmed) return;
  const aliasSplit = trimmed.includes(":") ? trimmed.split(":").pop() : trimmed;
  const field = aliasSplit.split("(")[0].trim();
  if (field && !fields.includes(field)) fields.push(field);
}

function matchesQuery(row, rawQuery) {
	for (const [key, value] of Object.entries(rawQuery)) {
		if (["select", "order", "limit", "on_conflict"].includes(key)) continue;
		const values = Array.isArray(value) ? value : [value];
		for (const oneValue of values) {
			if (key === "or") {
				if (!matchesOr(row, String(oneValue))) return false;
				continue;
			}
			if (!matchesFilter(row, key, String(oneValue))) return false;
		}
	}
	return true;
}

function matchesOr(row, value) {
  const inner = stripWrappingParens(value);
  return splitTopLevel(inner).some((part) => matchesFilterExpression(row, part));
}

function matchesFilterExpression(row, expression) {
  const trimmed = String(expression || "").trim();
  if (!trimmed) return true;
  if (trimmed.startsWith("and(") && trimmed.endsWith(")")) {
    return splitTopLevel(unwrapFilterFunction(trimmed, "and")).every((part) => matchesFilterExpression(row, part));
  }
  if (trimmed.startsWith("or(") && trimmed.endsWith(")")) {
    return splitTopLevel(unwrapFilterFunction(trimmed, "or")).some((part) => matchesFilterExpression(row, part));
  }
  const [field, op, ...rest] = trimmed.split(".");
  return matchesFilter(row, field, `${op}.${rest.join(".")}`);
}

function matchesFilter(row, field, expression) {
  const dot = expression.indexOf(".");
  if (dot < 0) return true;
  const op = expression.slice(0, dot);
  const expectedRaw = decodeURIComponent(expression.slice(dot + 1));
  const actual = row[field];
  if (op === "eq") return String(actual ?? "") === expectedRaw || actual === parsePrimitive(expectedRaw);
  if (op === "gte") return Number(actual || 0) >= Number(expectedRaw);
  if (op === "lte") return Number(actual || 0) <= Number(expectedRaw);
  if (op === "gt") return Number(actual || 0) > Number(expectedRaw);
  if (op === "lt") return Number(actual || 0) < Number(expectedRaw);
  if (op === "ilike") return String(actual || "").toLowerCase().includes(expectedRaw.replaceAll("*", "").replaceAll("%", "").toLowerCase());
  if (op === "in") return expectedRaw.replace(/^\(/, "").replace(/\)$/, "").split(",").includes(String(actual ?? ""));
  if (op === "cs") {
    const needle = expectedRaw.replace(/^\{/, "").replace(/\}$/, "");
    return Array.isArray(actual) && actual.map(String).includes(needle);
  }
  return true;
}

function applyOrder(rows, order) {
  if (!order) return rows;
  const first = String(order).split(",")[0];
  const [field, direction] = first.split(".");
  const sign = direction === "asc" ? 1 : -1;
  return [...rows].sort((a, b) => compare(a[field], b[field]) * sign);
}

function compare(a, b) {
  if (a === b) return 0;
  if (a === undefined || a === null) return -1;
  if (b === undefined || b === null) return 1;
  return String(a) < String(b) ? -1 : 1;
}

function conflictKeysFromQuery(query, collection) {
  if (query.on_conflict) return String(query.on_conflict).split(",").map((item) => item.trim()).filter(Boolean);
  if (collection === "active_servers") return ["server_key"];
  if (collection === "avatar_outfits") return ["user_id"];
  if (collection === "friendships") return ["user1", "user2"];
  if (collection === "friend_requests") return ["from_user", "to_user"];
  if (collection === "follows") return ["follower_id", "following_id"];
  if (collection === "asset_likes") return ["user_id", "target_type", "target_id"];
  if (collection === "user_inventory") return ["user_id", "item_id", "item_type"];
  return ["id"];
}

async function upsertRow(collection, inputPayload, conflictKeys) {
	const payload = sanitizeForStorage(inputPayload, collection);
	if (collection === "maps") await externalizeOversizedMapData(payload);
	if (collection === "profiles") await assertUniqueProfileUsername(payload);
	const existing = await findExistingRowByConflict(collection, payload, conflictKeys);
	if (existing) return fromPbRecord(await updatePbRecord(collection, existing._pb_id, payload));
	return fromPbRecord(await createPbRecord(collection, payload));
}

async function externalizeOversizedMapData(payload) {
  if (!payload?.data || typeof payload.data !== "object" || Array.isArray(payload.data)) return;
  if (payload.data.__bobux_external_map_data_url) return;
  const encoded = Buffer.from(JSON.stringify(payload.data), "utf8");
  if (encoded.length <= MAX_INLINE_MAP_DATA_BYTES) return;
  const ownerId = safePathSegment(payload.owner_id || "unknown-owner");
  const mapId = safePathSegment(payload.external_id || payload.name || crypto.randomUUID());
  const versionId = safePathSegment(payload.cloud_version_id || String(Date.now()));
  const relPath = safeObjectPath(`map-assets/${ownerId}/${mapId}/map_data/${versionId}.json`);
  const targetPath = path.join(STORAGE_DIR, relPath);
  await fs.mkdir(path.dirname(targetPath), { recursive: true });
  await fs.writeFile(targetPath, encoded);
  payload.data = {
    __bobux_external_map_data_url: `${PUBLIC_BASE_URL}/api/storage/v1/object/public/${relPath}`,
    __bobux_external_map_data_size: encoded.length,
    __bobux_external_map_data_sha256: crypto.createHash("sha256").update(encoded).digest("hex"),
    __bobux_external_map_data_version: 1
  };
  console.log(`[BobuxAPI] Stored ${encoded.length} bytes of map data outside PocketBase for '${payload.external_id || payload.name || "unknown"}'.`);
}

async function findExistingRowByConflict(collection, payload, conflictKeys) {
  const lookupFields = Array.from(new Set(["id", ...conflictKeys]));
  const rows = await listRows(collection, lookupFields);
  return rows.find((row) => conflictKeys.every((key) => String(row[key] ?? "") === String(conflictValue(payload, key) ?? ""))) || null;
}

async function assertUniqueProfileUsername(payload) {
  const username = cleanUsername(payload.username || "");
  if (!username || username === "Player") return;
  const ownerId = String(payload.external_id ?? payload.id ?? "").trim();
  const existing = await findProfileByUsername(username);
  if (existing && String(existing.id || "").trim() !== ownerId) {
    const error = new Error("That username is already taken.");
    error.status = 409;
    error.body = { code: "username_taken" };
    throw error;
  }
}

async function findProfileByUsername(username) {
  const target = cleanUsername(username).toLowerCase();
  if (!target || target === "player") return null;
  const rows = await listRows("profiles", ["id", "username", "updated_at"]);
  return rows.find((row) => String(row.username || "").trim().toLowerCase() === target) || null;
}

async function getProfileByExternalId(userId) {
  const cleanUserId = String(userId || "").trim();
  if (!cleanUserId) return null;
  const rows = await listRows("profiles", ["id", "username", "status", "current_game", "current_server_host", "current_server_ip", "current_server_port", "updated_at", "avatar_data"]);
  return rows.find((row) => String(row.id || "").trim() === cleanUserId) || null;
}

async function resolveProfileReference(value) {
  const cleanValue = String(value || "").trim();
  if (!cleanValue) return null;
  const byId = await getProfileByExternalId(cleanValue);
  if (byId) return byId;
  return await findProfileByUsername(cleanValue);
}

async function adoptProfileForUserRecord(userRecord) {
  if (!userRecord || !userRecord.id) return null;
  const userId = String(userRecord.id).trim();
  const username = cleanUsername(userRecord.name || userRecord.username || String(userRecord.email || "").split("@")[0] || "Player");
  const ownProfile = await getProfileByExternalId(userId);
  if (ownProfile) {
    const existingUsernameOwner = await findProfileByUsername(username);
    if (!existingUsernameOwner || String(existingUsernameOwner.id || "").trim() === userId) {
      if (String(ownProfile.username || "").trim() !== username) {
        return fromPbRecord(await updatePbRecord("profiles", ownProfile._pb_id, { username, updated_at: nowIso() }));
      }
    }
    return ownProfile;
  }

  const existingUsernameOwner = await findProfileByUsername(username);
  if (!existingUsernameOwner) {
    return await upsertRow("profiles", { id: userId, username, updated_at: nowIso() }, ["id"]);
  }

  // A newly created auth record must never steal an older player's profile, maps,
  // friends, or avatar just because the visible username matches.
  const safeUsername = makeUniqueUsernameVariant(username, userId);
  console.warn(`[BobuxAPI] Username '${username}' already belongs to ${existingUsernameOwner.id}; creating '${safeUsername}' for auth user ${userId}.`);
  return await upsertRow("profiles", { id: userId, username: safeUsername, updated_at: nowIso() }, ["id"]);
}

function makeUniqueUsernameVariant(username, userId) {
  const base = cleanUsername(username).replace(/[^\p{L}\p{N}_-]+/gu, "_").replace(/^_+|_+$/g, "") || "Player";
  const suffix = crypto.createHash("sha256").update(String(userId || crypto.randomUUID())).digest("hex").slice(0, 6);
  return `${base}_${suffix}`;
}

async function reassignUserReferences(oldUserId, newUserId, username) {
  if (!oldUserId || !newUserId || oldUserId === newUserId) return;
  const maps = (await listRows("maps", ["id", "owner_id", "owner_name"])).filter((row) => row.owner_id === oldUserId);
  for (const row of maps) await updatePbRecord("maps", row._pb_id, { owner_id: newUserId, owner_name: username });
  const outfits = (await listRows("avatar_outfits", ["user_id"])).filter((row) => row.user_id === oldUserId);
  for (const row of outfits) await updatePbRecord("avatar_outfits", row._pb_id, { user_id: newUserId });
  const servers = (await listRows("active_servers", ["host_user_id", "member_user_ids"])).filter((row) => row.host_user_id === oldUserId || (Array.isArray(row.member_user_ids) && row.member_user_ids.includes(oldUserId)));
  for (const row of servers) {
    const members = Array.isArray(row.member_user_ids) ? row.member_user_ids.map((id) => id === oldUserId ? newUserId : id) : row.member_user_ids;
    const patch = { member_user_ids: members };
    if (row.host_user_id === oldUserId) patch.host_user_id = newUserId;
    await updatePbRecord("active_servers", row._pb_id, patch);
  }
  const friendships = (await listRows("friendships", ["user1", "user2", "status", "created_at"])).filter((row) => row.user1 === oldUserId || row.user2 === oldUserId);
  for (const row of friendships) {
    const user1 = row.user1 === oldUserId ? newUserId : row.user1;
    const user2 = row.user2 === oldUserId ? newUserId : row.user2;
    if (user1 === user2) {
      await pbDeleteRecord("friendships", row._pb_id);
      continue;
    }
    const pair = buildFriendshipPair(user1, user2);
    await updatePbRecord("friendships", row._pb_id, { user1: pair.user1, user2: pair.user2 });
  }
  const requests = (await listRows("friend_requests", ["from_user", "to_user", "status", "created_at"])).filter((row) => row.from_user === oldUserId || row.to_user === oldUserId);
  for (const row of requests) {
    const fromUser = row.from_user === oldUserId ? newUserId : row.from_user;
    const toUser = row.to_user === oldUserId ? newUserId : row.to_user;
    if (fromUser === toUser) {
      await pbDeleteRecord("friend_requests", row._pb_id);
      continue;
    }
    await updatePbRecord("friend_requests", row._pb_id, { from_user: fromUser, to_user: toUser });
  }
  const follows = (await listRows("follows", ["follower_id", "following_id", "created_at"])).filter((row) => row.follower_id === oldUserId || row.following_id === oldUserId);
  for (const row of follows) {
    const followerId = row.follower_id === oldUserId ? newUserId : row.follower_id;
    const followingId = row.following_id === oldUserId ? newUserId : row.following_id;
    if (followerId === followingId) {
      await pbDeleteRecord("follows", row._pb_id);
      continue;
    }
    await updatePbRecord("follows", row._pb_id, { follower_id: followerId, following_id: followingId });
  }
}

function buildFriendshipPair(userA, userB) {
  const cleanUserA = String(userA || "").trim();
  const cleanUserB = String(userB || "").trim();
  return cleanUserA <= cleanUserB ? { user1: cleanUserA, user2: cleanUserB } : { user1: cleanUserB, user2: cleanUserA };
}

async function findFriendshipBetween(userA, userB) {
  const pair = buildFriendshipPair(userA, userB);
  const rows = await listRows("friendships", ["user1", "user2", "status", "created_at"]);
  return rows.find((row) => row.status === "accepted" && row.user1 === pair.user1 && row.user2 === pair.user2) || null;
}

async function findFriendRequest(fromUser, toUser) {
  const rows = await listRows("friend_requests", ["from_user", "to_user", "status", "created_at"]);
  return rows.find((row) => row.status === "pending" && row.from_user === fromUser && row.to_user === toUser) || null;
}

async function deleteDuplicateFriendRequestsBetween(userA, userB) {
  const rows = (await listRows("friend_requests", ["from_user", "to_user", "status", "created_at"])).filter((row) => row.status === "pending" && ((row.from_user === userA && row.to_user === userB) || (row.from_user === userB && row.to_user === userA)));
  const seen = new Set();
  let deleted = 0;
  rows.sort((a, b) => compare(a.created_at, b.created_at));
  for (const row of rows) {
    const key = `${row.from_user}|${row.to_user}`;
    if (seen.has(key)) {
      await pbDeleteRecord("friend_requests", row._pb_id);
      deleted += 1;
      continue;
    }
    seen.add(key);
  }
  return deleted;
}

async function deleteConcreteFriendRequest(fromUser, toUser) {
  const rows = (await listRows("friend_requests", ["from_user", "to_user", "status"])).filter((row) => row.from_user === fromUser && row.to_user === toUser);
  for (const row of rows) await pbDeleteRecord("friend_requests", row._pb_id);
  return rows.length;
}

async function deleteFriendRequestsBetween(userA, userB) {
  const rows = (await listRows("friend_requests", ["from_user", "to_user", "status"])).filter((row) => (row.from_user === userA && row.to_user === userB) || (row.from_user === userB && row.to_user === userA));
  for (const row of rows) await pbDeleteRecord("friend_requests", row._pb_id);
  return rows.length;
}

function dedupeProfilesByUsername(profiles) {
  const output = [];
  const seen = new Set();
  for (const profile of profiles) {
    const key = String(profile?.username || profile?.id || "").trim().toLowerCase();
    if (!key || seen.has(key)) continue;
    seen.add(key);
    output.push(profile);
  }
  return output;
}

async function buildPublicProfileIndex(userIds = []) {
  const wanted = new Set(
    userIds
      .map((value) => String(value || "").trim())
      .filter(Boolean)
  );
  const output = new Map();
  if (wanted.size === 0) return output;
  const rows = await listRows("profiles", [
    "id",
    "username",
    "status",
    "current_game",
    "current_server_host",
    "current_server_ip",
    "current_server_port",
    "created",
    "updated",
    "updated_at",
    "avatar_data"
  ]);
  for (const row of rows) {
    const id = String(row.id || "").trim();
    if (wanted.has(id) && !output.has(id)) output.set(id, row);
    if (output.size >= wanted.size) break;
  }
  return output;
}

async function buildAvatarOutfitIndex(userIds = []) {
  const wanted = new Set(
    userIds
      .map((value) => String(value || "").trim())
      .filter(Boolean)
  );
  const output = new Map();
  if (wanted.size === 0) return output;
  const rows = await listRows("avatar_outfits", [
    "user_id",
    "head_color",
    "torso_color",
    "left_arm_color",
    "right_arm_color",
    "left_leg_color",
    "right_leg_color",
    "face_texture_path",
    "chest_badge_texture_path",
    "shirt_texture_path",
    "pants_texture_path",
    "saved_shirt_texture_paths",
    "saved_pants_texture_paths",
    "equipped_items",
    "body_type",
    "updated_at"
  ]);
  const avatarItemPayloadById = await buildAvatarItemPayloadIndex(rows);
  for (const row of rows) {
    const userId = String(row.user_id || "").trim();
    if (!wanted.has(userId) || output.has(userId)) continue;
    const publicOutfit = sanitizePublicAvatarOutfit(row, avatarItemPayloadById);
    output.set(userId, publicOutfit);
    if (output.size >= wanted.size) break;
  }
  return output;
}

async function buildAvatarItemPayloadIndex(outfitRows = []) {
  const wantedItemIds = new Set();
  for (const row of outfitRows) {
    if (!Array.isArray(row?.equipped_items)) continue;
    for (const rawId of row.equipped_items) {
      const itemId = String(rawId || "").trim();
      if (itemId) wantedItemIds.add(itemId);
    }
  }
  if (wantedItemIds.size === 0) return new Map();
  const output = new Map();
  const rows = await listRows("avatar_items", [
    "id",
    "name",
    "owner_id",
    "owner_name",
    "thumbnail",
    "visibility",
    "is_public",
    "category",
    "asset_type",
    "template_url",
    "source_url",
    "model_id",
    "attachment_slot",
    "attachment_transform",
    "data",
    "price_robux",
    "likes_count",
    "created_at",
    "updated_at"
  ]);
  for (const row of rows) {
    const itemId = String(row.id || row.item_id || "").trim();
    if (!wantedItemIds.has(itemId) || output.has(itemId)) continue;
    output.set(itemId, sanitizePublicAvatarItemPayload(row));
    if (output.size >= wantedItemIds.size) break;
  }
  return output;
}

function sanitizePublicAvatarOutfit(row, avatarItemPayloadById = new Map()) {
  const source = row || {};
  const output = {};
  for (const key of [
    "head_color",
    "torso_color",
    "left_arm_color",
    "right_arm_color",
    "left_leg_color",
    "right_leg_color"
  ]) {
    if (source[key] !== undefined) output[key] = cloneJson(source[key]);
  }
  for (const key of [
    "face_texture_path",
    "chest_badge_texture_path",
    "shirt_texture_path",
    "pants_texture_path",
    "body_type",
    "updated_at"
  ]) {
    const value = lightweightPublicString(source[key]);
    if (value) output[key] = value;
  }
  for (const key of ["saved_shirt_texture_paths", "saved_pants_texture_paths"]) {
    if (Array.isArray(source[key])) output[key] = source[key].slice(-24).map((value) => lightweightPublicString(value)).filter(Boolean);
  }
  const equippedIds = Array.isArray(source.equipped_items)
    ? source.equipped_items.map((value) => String(value || "").trim()).filter(Boolean).slice(0, 48)
    : [];
  output.equipped_items = equippedIds;
  const payloads = [];
  for (const itemId of equippedIds) {
    const payload = avatarItemPayloadById.get(itemId);
    if (payload && typeof payload === "object") payloads.push(payload);
    if (payloads.length >= MAX_PUBLIC_AVATAR_ITEM_PAYLOADS) break;
  }
  if (payloads.length > 0) output.equipped_avatar_item_payloads = payloads;
  return output;
}

function mergePublicProfileWithAvatarOutfit(profile, avatarOutfit) {
  const output = { ...(profile || {}) };
  if (!avatarOutfit || typeof avatarOutfit !== "object" || Array.isArray(avatarOutfit)) return output;
  output.avatar_outfit = avatarOutfit;
  const avatarData = output.avatar_data && typeof output.avatar_data === "object" && !Array.isArray(output.avatar_data)
    ? { ...output.avatar_data }
    : {};
  const colorMap = {
    head_color: "head",
    torso_color: "torso",
    left_arm_color: "left_arm",
    right_arm_color: "right_arm",
    left_leg_color: "left_leg",
    right_leg_color: "right_leg"
  };
  for (const [outfitKey, avatarKey] of Object.entries(colorMap)) {
    if (avatarOutfit[outfitKey] !== undefined) {
      avatarData[outfitKey] = avatarOutfit[outfitKey];
      avatarData[avatarKey] = avatarOutfit[outfitKey];
    }
  }
  for (const key of ["face_texture_path", "chest_badge_texture_path", "shirt_texture_path", "pants_texture_path", "saved_shirt_texture_paths", "saved_pants_texture_paths", "equipped_avatar_item_payloads"]) {
    if (avatarOutfit[key] !== undefined) avatarData[key] = cloneJson(avatarOutfit[key]);
  }
  if (Array.isArray(avatarOutfit.equipped_items)) {
    avatarData.equipped_items = avatarOutfit.equipped_items.slice(0, 48);
    avatarData.equipped = avatarOutfit.equipped_items.slice(0, 48);
  }
  output.avatar_data = avatarData;
  return output;
}

function dedupeFriendshipsForUser(rows, userId) {
  const output = [];
  const seenFriends = new Set();
  const cleanUserId = String(userId || "").trim();
  for (const row of rows) {
    const user1 = String(row?.user1 || "").trim();
    const user2 = String(row?.user2 || "").trim();
    if (!user1 || !user2 || user1 === user2) continue;
    if (user1 !== cleanUserId && user2 !== cleanUserId) continue;
    const friendId = user1 === cleanUserId ? user2 : user1;
    if (!friendId || seenFriends.has(friendId)) continue;
    seenFriends.add(friendId);
    output.push(row);
  }
  return output;
}

function normalizeVisibility(value) {
  const clean = String(value || "public").trim().toLowerCase();
  return clean === "private" ? "private" : "public";
}

function clampLimit(value, fallback = 64) {
  const parsed = Number(value || fallback);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(1, Math.min(200, Math.floor(parsed)));
}

function isVisibleMarketplaceRow(row, userId = "", includePrivate = false, ownerOnly = false) {
  const ownerId = String(row?.owner_id || "").trim();
  const isOwner = Boolean(userId && ownerId === userId);
  if (ownerOnly) return isOwner;
  if (Boolean(row?.is_public) || String(row?.visibility || "public").toLowerCase() === "public") return true;
  return includePrivate && isOwner;
}

function rowBelongsToUser(row, userRecord) {
  const userId = String(userRecord?.id || "").trim();
  if (!userId) return false;
  const ownerIds = [row?.owner_id, row?.creator_id, row?.user_id].map((value) => String(value || "").trim());
  if (ownerIds.includes(userId)) return true;
  const username = cleanUsername(userRecord?.name || userRecord?.username || String(userRecord?.email || "").split("@")[0] || "").toLowerCase();
  if (!username) return false;
  const ownerNames = [row?.owner_name, row?.creator_name, row?.creator].map((value) => String(value || "").trim().toLowerCase());
  return ownerNames.includes(username);
}

function isTechnicalCreationRow(row) {
  const id = String(row?.id || row?.external_id || "").trim().toLowerCase();
  const name = String(row?.name || "").trim().toLowerCase();
  return id.includes("__asset_") || name.startsWith("__asset_") || name.endsWith("_asset_roundtrip");
}

function sanitizeMarketplaceOutput(row) {
  const output = { ...(row || {}) };
  delete output._pb_id;
  if (typeof output.thumbnail === "string" && output.thumbnail.startsWith("data:") && output.thumbnail.length > MAX_INLINE_THUMBNAIL_CHARS) {
    output.thumbnail = "";
  }
  if (output.data && typeof output.data === "object" && !Array.isArray(output.data)) {
    output.data = sanitizeMarketplaceDataForClient(output.data);
  }
  return output;
}

function sanitizeMarketplaceDataForClient(data) {
  const output = cloneJson(data) || {};
  for (const key of ["thumbnail", "preview", "preview_thumbnail", "image", "icon"]) {
    if (typeof output[key] === "string" && output[key].startsWith("data:") && output[key].length > MAX_INLINE_THUMBNAIL_CHARS) {
      output[key] = "";
    }
  }
  return output;
}

function sanitizePublicProfileOutput(profile) {
  const output = { ...(profile || {}) };
  delete output._pb_id;
  if (output.avatar_data && typeof output.avatar_data === "object" && !Array.isArray(output.avatar_data)) {
    output.avatar_data = sanitizePublicAvatarData(output.avatar_data);
  } else {
    delete output.avatar_data;
  }
  if (Array.isArray(output.inventory_items) && output.inventory_items.length > 80) {
    output.inventory_items = output.inventory_items.slice(-80);
  }
  return output;
}

function sanitizePublicAvatarData(avatarData) {
  const source = avatarData || {};
  const output = {};
  for (const key of ["head", "torso", "left_arm", "right_arm", "left_leg", "right_leg"]) {
    if (source[key] !== undefined) output[key] = source[key];
  }
  for (const key of ["face_texture_path", "chest_badge_texture_path", "shirt_texture_path", "pants_texture_path"]) {
    const value = lightweightPublicString(source[key]);
    if (value) output[key] = value;
  }
  if (Array.isArray(source.equipped)) output.equipped = source.equipped.slice(0, 48);
  if (Array.isArray(source.equipped_items)) output.equipped_items = source.equipped_items.slice(0, 48);
  if (Array.isArray(source.avatar_items)) output.avatar_items = source.avatar_items.slice(0, 48);
  if (Array.isArray(source.equipped_avatar_items)) output.equipped_avatar_items = source.equipped_avatar_items.slice(0, 48);
  const payloads = Array.isArray(source.equipped_avatar_item_payloads) ? source.equipped_avatar_item_payloads : [];
  if (payloads.length > 0) {
    output.equipped_avatar_item_payloads = payloads.slice(0, MAX_PUBLIC_AVATAR_ITEM_PAYLOADS).map(sanitizePublicAvatarItemPayload);
  }
  return output;
}

function sanitizePublicAvatarItemPayload(payload) {
  const source = payload && typeof payload === "object" ? payload : {};
  const output = {};
  for (const key of [
    "id",
    "item_id",
    "name",
    "category",
    "asset_type",
    "item_kind",
    "attachment_slot",
    "attachment_transform",
    "model_id",
    "color",
    "material",
    "source_file_name",
    "source_model_path"
  ]) {
    if (source[key] !== undefined) output[key] = source[key];
  }
  for (const key of ["thumbnail", "template_url", "source_url", "texture_path", "model_url", "source_file_url"]) {
    const value = lightweightPublicString(source[key]);
    if (value) output[key] = value;
  }
  if (source.data && typeof source.data === "object" && !Array.isArray(source.data)) {
    output.data = sanitizeMarketplaceDataForClient(source.data);
  }
  return output;
}

function lightweightPublicString(value) {
  const textValue = String(value || "").trim();
  if (!textValue) return "";
  if (textValue.startsWith("data:") && textValue.length > MAX_PUBLIC_AVATAR_INLINE_TEXTURE_CHARS) return "";
  return textValue;
}

function normalizeLikeTargetType(value) {
  const clean = String(value || "").trim().toLowerCase();
  if (clean === "model" || clean === "model_asset" || clean === "model_assets") return "model";
  if (clean === "avatar_item" || clean === "avatar_items" || clean === "item") return "avatar_item";
  if (clean === "map" || clean === "maps" || clean === "game") return "map";
  return "";
}

function collectionForLikeTarget(targetType) {
  if (targetType === "model") return "model_assets";
  if (targetType === "avatar_item") return "avatar_items";
  if (targetType === "map") return "maps";
  return "";
}

async function findAssetLike(userId, targetType, targetId) {
  const rows = await listRows("asset_likes", ["user_id", "target_type", "target_id", "created_at"]);
  return rows.find((row) => row.user_id === userId && row.target_type === targetType && row.target_id === targetId) || null;
}

async function grantInventoryItemToUser(userId, itemId, itemType = "avatar_item") {
  const cleanUserId = String(userId || "").trim();
  const cleanItemId = String(itemId || "").trim();
  const cleanItemType = String(itemType || "avatar_item").trim() || "avatar_item";
  if (!cleanUserId || !cleanItemId) throw new Error("Inventory grant requires a user and item id.");
  const inventory = await upsertRow("user_inventory", {
    user_id: cleanUserId,
    item_id: cleanItemId,
    item_type: cleanItemType,
    created_at: nowIso()
  }, ["user_id", "item_id", "item_type"]);
  const profile = await getProfileByExternalId(cleanUserId);
  if (profile && profile._pb_id) {
    const inventoryItems = Array.isArray(profile.inventory_items) ? [...profile.inventory_items] : [];
    if (!inventoryItems.map((value) => String(value)).includes(cleanItemId)) inventoryItems.push(cleanItemId);
    await updatePbRecord("profiles", profile._pb_id, { inventory_items: inventoryItems, updated_at: nowIso() });
  }
  return inventory;
}

async function getOwnedInventoryItemIds(userId, itemType = "avatar_item") {
  const cleanUserId = String(userId || "").trim();
  if (!cleanUserId) return new Set();
  const rows = await listRows("user_inventory", ["user_id", "item_id", "item_type"]);
  const cleanItemType = String(itemType || "").trim();
  return new Set(rows
    .filter((row) => row.user_id === cleanUserId && (!cleanItemType || row.item_type === cleanItemType))
    .map((row) => String(row.item_id || "").trim())
    .filter(Boolean));
}

async function getLikesCountForTarget(targetType, targetId) {
  const collection = collectionForLikeTarget(targetType);
  if (!collection) return 0;
  const rows = await listRows(collection, ["id", "likes_count"]);
  const row = rows.find((item) => String(item.id || "").trim() === targetId);
  return Number(row?.likes_count || 0);
}

async function incrementLikesCount(targetType, targetId) {
  const collection = collectionForLikeTarget(targetType);
  if (!collection) return 0;
  const rows = await listRows(collection, ["id", "likes_count"]);
  const row = rows.find((item) => String(item.id || "").trim() === targetId);
  if (!row) {
    const error = new Error("Like target was not found.");
    error.status = 404;
    throw error;
  }
  const nextCount = Number(row.likes_count || 0) + 1;
  await updatePbRecord(collection, row._pb_id, { likes_count: nextCount });
  return nextCount;
}

async function incrementMapVisitCount(targetId) {
  const cleanTargetId = String(targetId || "").trim();
  return await withMutationLock(`visit:map:${cleanTargetId}`, async () => {
    const rows = await listRows("maps", ["id", "visits_count"]);
    const row = rows.find((item) => String(item.id || "").trim() === cleanTargetId || String(item._pb_id || "").trim() === cleanTargetId);
    if (!row) {
      const error = new Error("Map was not found.");
      error.status = 404;
      throw error;
    }
    const nextCount = Number(row.visits_count || 0) + 1;
    await updatePbRecord("maps", row._pb_id || row.id, { visits_count: nextCount });
    return nextCount;
  });
}

function conflictValue(payload, key) {
	if (key === "id") return payload.external_id ?? payload.id;
	return payload[key];
}

async function createPbRecord(collection, payload) {
  return await pbFetch(`/api/collections/${collection}/records`, {
    method: "POST",
    admin: true,
    body: toPbRecord(collection, payload)
  });
}

async function updatePbRecord(collection, pbId, payload) {
  return await pbFetch(`/api/collections/${collection}/records/${pbId}`, {
    method: "PATCH",
    admin: true,
    body: toPbRecord(collection, payload)
  });
}

async function pbDeleteRecord(collection, pbId) {
  await pbFetch(`/api/collections/${collection}/records/${pbId}`, { method: "DELETE", admin: true });
}

function sanitizeForStorage(input, collection = "") {
  const output = { ...(input || {}) };
  if (output.id !== undefined) {
    output.external_id = String(output.id);
    delete output.id;
  }
  if (collection === "maps" && typeof output.thumbnail === "string" && output.thumbnail.length > MAX_INLINE_THUMBNAIL_CHARS) {
    console.warn(`[BobuxAPI] Dropping oversized inline map thumbnail (${output.thumbnail.length} chars) for map '${output.external_id || output.name || "unknown"}'.`);
    output.thumbnail = "";
  }
  if (collection === "maps" && output.data && typeof output.data === "object") {
    output.data = sanitizeMapDataForClient(output.data);
  }
  return output;
}

function toPbRecord(collection, payload) {
  const allowed = new Set(collectionFields[collection].map((field) => field.name));
  const output = {};
  for (const [key, value] of Object.entries(sanitizeForStorage(payload, collection))) {
    if (allowed.has(key)) output[key] = value;
  }
  return output;
}

function fromPbRecord(record) {
  const row = { ...record, _pb_id: record.id };
  if (row.external_id) row.id = row.external_id;
  if (!row.created_at && row.created) row.created_at = row.created;
  delete row.external_id;
  delete row.collectionId;
  delete row.collectionName;
  delete row.expand;
  return row;
}

function sanitizeOutputRow(collection, row) {
  if (!row) return row;
  if (collection === "maps") {
    const output = { ...row };
    if (typeof output.thumbnail === "string" && output.thumbnail.startsWith("data:") && output.thumbnail.length > MAX_INLINE_THUMBNAIL_CHARS) {
      output.thumbnail = "";
    }
    if (output.data && typeof output.data === "object") output.data = sanitizeMapDataForClient(output.data);
    return output;
  }
  if (collection === "profiles") return sanitizePublicProfileOutput(row);
  return row;
}

function sanitizeMapDataForClient(mapData) {
  const output = cloneJson(mapData);
  const blobs = output?.mode_asset_blobs;
  if (!blobs || typeof blobs !== "object" || Array.isArray(blobs)) return output;
  const kept = {};
  let skipped = 0;
  for (const [fileName, value] of Object.entries(blobs)) {
    const cleanName = String(fileName || "").trim();
    const encoded = String(value || "");
    if (!cleanName || !encoded) continue;
    if (isAudioAssetName(cleanName) || encoded.length > MAX_INLINE_MAP_ASSET_CHARS) {
      skipped += 1;
      continue;
    }
    kept[cleanName] = encoded;
  }
  if (Object.keys(kept).length > 0) output.mode_asset_blobs = kept;
  else delete output.mode_asset_blobs;
  if (skipped > 0) {
    output.mode_asset_warning = `Skipped ${skipped} heavy inline asset(s); media is loaded separately so the game can start on weak connections.`;
  }
  return output;
}

function cloneJson(value) {
  return value == null ? value : JSON.parse(JSON.stringify(value));
}

function isAudioAssetName(fileName) {
  const ext = path.extname(String(fileName || "").toLowerCase()).replace(".", "");
  return ext === "mp3" || ext === "ogg" || ext === "wav";
}

async function deleteRowsAndStorage(rows) {
  let deleted = 0;
  for (const row of rows) {
    await pbDeleteRecord("maps", row._pb_id);
    if (row.owner_id && row.id) {
      await fs.rm(path.join(STORAGE_DIR, "map-assets", safePathSegment(row.owner_id), safePathSegment(row.id)), { recursive: true, force: true });
    }
    deleted += 1;
  }
  return deleted;
}

async function cleanupTechnicalMapRows() {
  const technicalRows = (await listRows("maps")).filter(isTechnicalCreationRow);
  if (technicalRows.length === 0) return;
  const deleted = await deleteRowsAndStorage(technicalRows);
  console.log(`[BobuxAPI] Removed ${deleted} technical map record(s) from creator listings.`);
}

function parsePrimitive(value) {
  if (value === "true") return true;
  if (value === "false") return false;
  if (!Number.isNaN(Number(value)) && value.trim() !== "") return Number(value);
  return value;
}

function cleanUsername(value) {
  const username = String(value || "Player").trim();
  return username.length >= 3 ? username : `Player${Math.floor(Math.random() * 9999)}`;
}

function nowIso() {
  return new Date().toISOString();
}

function safeObjectPath(value) {
  const clean = String(value || "").replaceAll("\\", "/").split("/").filter((part) => part && part !== "." && part !== "..").join("/");
  if (!clean) throw new Error("Invalid object path");
  return clean;
}

function safePathSegment(value) {
  return String(value || "asset").replace(/[\\/:*?"<>| %#&=+]/g, "_");
}

function sendError(res, error, fallbackStatus = 400) {
  const status = Number(error?.status || fallbackStatus || 400);
  console.error("[BobuxAPI]", status, error?.message || "Request failed", error?.body || "");
  res.status(status >= 400 && status < 600 ? status : 400).json({
    message: error?.message || "Request failed",
    details: error?.body || undefined,
    status
  });
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
