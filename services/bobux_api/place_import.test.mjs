import assert from 'node:assert/strict';
import express from 'express';
import { fileURLToPath } from 'node:url';
import { mountPlaceImport } from './place_import.mjs';
const app=express();
mountPlaceImport(app,async req=>{if(req.headers.authorization!=='Bearer test')throw new Error('auth');},{python:process.platform==='win32'?'python':'python3',converter:fileURLToPath(new URL('../../addons/rbxl_importer/rbxl_converter.py',import.meta.url))});
const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
const url=`http://127.0.0.1:${server.address().port}/api/studio/import-place`;
const xml=`<roblox version="4"><Item class="Workspace" referent="RBX0"><Properties><string name="Name">Workspace</string></Properties><Item class="Part" referent="RBX1"><Properties><string name="Name">Island</string></Properties><Item class="Script" referent="RBX2"><Properties><string name="Name">Weather</string><ProtectedString name="Source">print('storm')</ProtectedString></Properties></Item></Item></Item></roblox>`;
try {
 assert.equal((await fetch(url,{method:'POST',headers:{'Content-Type':'application/octet-stream'},body:xml})).status,401);
 const result=await fetch(url,{method:'POST',headers:{'Content-Type':'application/octet-stream',Authorization:'Bearer test'},body:xml});
 const payload=await result.json();assert.equal(result.status,200,JSON.stringify(payload));
 const instances=Object.values(payload.place.instances);
 assert.ok(instances.some(i=>i.class==='Script'&&JSON.stringify(i).includes("print('storm')")));
 assert.equal(instances.length,3);
 assert.equal((await fetch(url,{method:'POST',headers:{'Content-Type':'application/octet-stream',Authorization:'Bearer test'},body:'invalid'})).status,422);
 console.log('Mobile place import PASS: auth, full hierarchy/scripts, invalid file rejection');
} finally {server.closeAllConnections();server.close();}
