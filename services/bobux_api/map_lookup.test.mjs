import assert from 'node:assert/strict';
import { lookupMapRecords } from './map_lookup.mjs';
for (const id of ['z9ovqynlv860sgw_baseplate 108','name " || true || "', 'карта № 1']) {
  let calls=0;
  const rows=await lookupMapRecords(async (url,options)=>{
    calls++;
    const query=new URL(url,'http://test').searchParams;
    assert.equal(query.get('filter'),`(external_id = ${JSON.stringify(id)} || (external_id = "" && id = ${JSON.stringify(id)}))`);
    assert.equal(query.get('fields'),'id,external_id,data');
    assert.equal(options.admin,true);
    return {items:[{id:'internal',external_id:id}],totalPages:1};
  },id,['id','external_id','data']);
  assert.equal(calls,1);
  assert.equal(rows[0].external_id,id);
}
console.log('[map-lookup] PASS: one filtered request; whitespace, Unicode and escaped quotes');
