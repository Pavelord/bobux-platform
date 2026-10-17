const MAP_CARD_FIELDS = "id,name,owner_id,owner_name,description,thumbnail,cloud_version_id,updated_at,likes_count,visits_count,is_published";

export function normalizeReadQuery(collection, query = {}) {
  const result = { ...query };
  const exactMap = collection === "maps" && String(result.id || "").startsWith("eq.");
  if (collection === "maps" && !exactMap) {
    if (!result.select) result.select = MAP_CARD_FIELDS;
    const limit = Number(result.limit ?? 100);
    result.limit = Number.isFinite(limit) ? Math.min(200, Math.max(0, Math.floor(limit))) : 100;
  }
  return result;
}

export function pageReadRows(rows, query = {}) {
  const rawOffset = Number(query.offset ?? 0);
  const offset = Number.isFinite(rawOffset) ? Math.max(0, Math.floor(rawOffset)) : 0;
  const rawLimit = query.limit === undefined ? rows.length : Number(query.limit);
  const limit = Number.isFinite(rawLimit) ? Math.max(0, Math.floor(rawLimit)) : rows.length;
  return rows.slice(offset, offset + limit);
}
