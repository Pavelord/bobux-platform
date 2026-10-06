// A join requests one external map ID. Fetching every map and only then filtering
// makes joining slower as creators publish more places (including huge JSON).
export async function lookupMapRecords(pbFetch, id, fields = []) {
  if (typeof id !== 'string' || !id || id.length > 200) return [];
  const literal = JSON.stringify(id);
  const filter = `(external_id = ${literal} || (external_id = "" && id = ${literal}))`;
  const params = new URLSearchParams({ page:'1', perPage:'500', filter });
  if (fields.length) params.set('fields', fields.join(','));
  const records = [];
  for (let page = 1; ; page++) {
    params.set('page',String(page));
    const response = await pbFetch(`/api/collections/maps/records?${params}`, { admin:true });
    records.push(...response.items || []);
    if (page >= Number(response.totalPages || 1)) return records;
  }
}
