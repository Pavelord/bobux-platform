import express from 'express';

// Permanent account ID, never a display-name check or a client admin flag.
export const LEGENDS_EDITOR = 'z9ovqynlv860sgw';
export function mountLegends(app, db, authenticate, listMaps) {
  if (!db) return;
  db.exec(`CREATE TABLE IF NOT EXISTS bobux_legends (
    map_id TEXT PRIMARY KEY, year INTEGER NOT NULL CHECK(year BETWEEN 2006 AND 2100),
    added_by TEXT NOT NULL, added_at INTEGER NOT NULL) STRICT;`);
  app.get('/api/legends', async (_req,res) => {
    try {
      const maps = await listMaps();
      const byId = new Map(maps.filter(m=>m.is_published && String(m.visibility || "public").toLowerCase()!=="private").map(m=>[m.id,m]));
      const games = db.prepare('SELECT * FROM bobux_legends ORDER BY year,added_at').all()
        .filter(row=>byId.has(row.map_id)).map(row=>({...byId.get(row.map_id),year:row.year}));
      res.json({ok:true,games});
    } catch { res.status(503).json({ok:false,error:'Коллекция временно недоступна.'}); }
  });
  app.post('/api/legends', express.json({limit:'2kb'}), async (req,res) => {
    let user;
    try { user = (await authenticate(req))?.record; } catch {}
    if (user?.id!==LEGENDS_EDITOR) return res.status(403).json({ok:false,error:'Нет прав на изменение коллекции.'});
    const id=String(req.body?.map_id||'');
    const year=Number(req.body?.year);
    if (!id || id.length>200 || (!req.body?.remove && (!Number.isInteger(year)||year<2006||year>new Date().getUTCFullYear()))) {
      return res.status(400).json({ok:false,error:'Укажите игру и год её выхода.'});
    }
    try {
      if (req.body?.remove===true) db.prepare('DELETE FROM bobux_legends WHERE map_id=?').run(id);
      else {
        const map=(await listMaps()).find(m=>m.id===id && m.is_published && String(m.visibility || "public").toLowerCase()!=="private");
        if (!map) return res.status(404).json({ok:false,error:'Игра не опубликована.'});
        db.prepare('INSERT INTO bobux_legends VALUES (?,?,?,?) ON CONFLICT(map_id) DO UPDATE SET year=excluded.year').run(id,year,user.id,Date.now());
      }
      res.json({ok:true});
    } catch { res.status(503).json({ok:false,error:'Не удалось сохранить коллекцию.'}); }
  });
}
