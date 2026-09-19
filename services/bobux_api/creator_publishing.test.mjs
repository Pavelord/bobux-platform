import assert from 'node:assert/strict';
import { BobloxWallet } from './boblox_wallet.mjs';
import { BobloxCommerce } from './boblox_commerce.mjs';
import { CreatorPublishing } from './creator_publishing.mjs';
let time = Date.UTC(2026,8,19);
const wallet = new BobloxWallet(':memory:');
const commerce = new BobloxCommerce(wallet,{now:()=>time});
const publisher = new CreatorPublishing(commerce), rows = new Map();
wallet.apply({userId:'alice',amount:500,operationId:'test:fund:alice',reason:'test'});
const publish=(id,extra={})=>{
 const userId=extra.userId||'alice', price=extra.price??10, category=extra.category||'shirt', visibility=extra.visibility||'public';
 return publisher.publish({userId,itemId:id,category,visibility,price,acceptedFee:5,
 lookup:async()=>rows.get(id),save:async()=>{const row={id,owner_id:userId,category,visibility,price_robux:price};rows.set(id,row);return row;},...extra});
};
await Promise.all([publish('shirt1'),publish('shirt1')]);
assert.equal(wallet.read('alice').balance,500);
assert.equal(publisher.benefits('alice').usage.clothing,1);
await assert.rejects(publish('shirt1',{userId:'bob'}),/автор/);
await assert.rejects(publish('shirt1',{category:'model',price:20}),/типа/);
for(let i=2;i<=5;i++)await publish('shirt'+i);
assert.equal(wallet.read('alice').balance,500);
await assert.rejects(publish('unconfirmed',{acceptedFee:0}),/Подтвердите/);
await publish('extra');assert.equal(wallet.read('alice').balance,495);
await publish('draft',{visibility:'private',price:1});
await assert.rejects(publish('draft',{price:1}),/Минимальная/);
await assert.rejects(publish('broken',{save:async()=>{throw new Error('PB failed');}}),/PB failed/);
assert.equal(wallet.read('alice').balance,495);
await publish('broken');assert.equal(wallet.read('alice').balance,490);
await publish('gift',{price:0});
await assert.rejects(publish('gift2',{price:0}),/бесплатных товаров/);
await assert.rejects(publish('shirt1',{price:0}),/бесплатных товаров/);
// Deleting/hiding a free listing does not replenish its quota.
rows.delete('gift');await assert.rejects(publish('gift2',{price:0}),/бесплатных товаров/);
// Recreate same item safely, without charging again.
const before=wallet.read('alice').balance;await publish('gift',{price:0});assert.equal(wallet.read('alice').balance,before);
// Cross-account same-ID races must not overwrite the first author.
const race=await Promise.allSettled([publish('race',{userId:'bob'}),publish('race',{userId:'carol'})]);
assert.equal(race.filter(r=>r.status==='fulfilled').length,1);assert.equal(rows.get('race').owner_id,'bob');
// An uncertain write keeps its reservation through retry without duplicate debit.
let lookupCount=0;await assert.rejects(publish('uncertain',{lookup:async()=>{if(++lookupCount>1)throw Error('offline');},save:async()=>{throw Error('timeout');}}),/Проверяем/);
const held=wallet.read('alice').balance;await publish('uncertain',{acceptedFee:0});assert.equal(wallet.read('alice').balance,held);
while(publisher.benefits('alice').usage.clothing<25)await publish('fill'+publisher.benefits('alice').usage.clothing);
await assert.rejects(publish('over-limit'),/предел/);
await publish('shirt1'); // Editing still works at quota.
time=Date.UTC(2026,9,1);await publish('next-month');assert.equal(publisher.benefits('alice').usage.clothing,1);
await publish('gift2',{price:0});
commerce.grantFounder('alice','Alice');commerce.claimFounder('alice');
assert.equal(publisher.benefits('alice').rules.items_limit,100);
const beforeTbc=wallet.read('alice').balance;await publish('free-tbc');assert.equal(wallet.read('alice').balance,beforeTbc);
await assert.rejects(publish('invalid',{price:NaN}),/Цена/);
wallet.close();console.log('Creator publishing PASS: free allowances, paid extras, quotas, concurrent ownership, free-item quotas, refunds, retries, UTC reset, TBC');
