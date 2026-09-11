import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';
import express from '../services/bobux_api/node_modules/express/index.js';
import { SocialStore, mountSocial } from '../services/bobux_api/social_store.mjs';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const store = new SocialStore(':memory:');
store.send('bob','alice','Привет! Построим карту?','initial');
const app = express();
mountSocial(app,store,{
  authenticate: async req => {
    if (req.get('Authorization') !== 'Bearer alice') throw new Error('unauthorized');
    return {record:{id:'alice',email:'alice@example.invalid'}};
  },
  areFriends: async (a,b)=>a==='alice' && b==='bob',
  isPublicMap: async id=>id==='map1'
});
app.post('/api/rest/v1/rpc/get_friends_list',(_req,res)=>res.json([{id:'bob',username:'Bob'}]));
const server = app.listen(0,'127.0.0.1');
await new Promise(resolve=>server.once('listening',resolve));
try {
  const executable = process.env.GODOT_BIN || resolve(root,'.codex-tools/godot-4.7/Godot_v4.7-stable_win64_console.exe');
  const child = spawn(executable,['--headless','--path',root,'--script','tools/validate_messages_flow.gd','--',String(server.address().port)],{cwd:root,windowsHide:true});
  let output='';
  child.stdout.on('data',data=>{output+=data;process.stdout.write(data);});
  child.stderr.on('data',data=>{output+=data;process.stderr.write(data);});
  const timeout=setTimeout(()=>child.kill(),40000);
  const code=await new Promise(resolve=>{child.on('error',()=>resolve(1));child.on('exit',resolve);});
  clearTimeout(timeout);
  if(code!==0 || /SCRIPT ERROR|Parse Error|ERROR:/.test(output) || !output.includes('[messages_flow] PASS')) process.exitCode=1;
  if(store.history('alice','bob').messages.length!==2 || store.history('alice','eve').messages.length!==0) process.exitCode=1;
} finally {
  await new Promise(resolve=>server.close(resolve));
  store.close();
}
