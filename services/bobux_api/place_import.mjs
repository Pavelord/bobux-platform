import express from "express";
import { mkdtemp, writeFile, readFile, rm, stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
const exec = promisify(execFile);
export function mountPlaceImport(app, authenticate, options = {}) {
  let active = 0;
  const converter = options.converter || process.env.BOBUX_RBXL_CONVERTER || "/opt/bobux-server/addons/rbxl_importer/rbxl_converter.py";
  app.post("/api/studio/import-place", async (req, res, next) => {
    try { await authenticate(req); next(); }
    catch { res.status(401).json({ error: "Войдите в аккаунт для импорта карты." }); }
  }, express.raw({ type: "application/octet-stream", limit: "32mb" }), async (req, res) => {
    if (!Buffer.isBuffer(req.body) || !req.body.length) return res.status(400).json({ error: "Выберите файл .rbxl или .rbxlx." });
    if (active >= 1) return res.status(429).json({ error: "Сервер занят импортом. Повторите через минуту." });
    active++;
    let directory;
    try {
      directory = await mkdtemp(join(tmpdir(), "bobux-import-"));
      const input = join(directory, "place.rbxl"), output = join(directory, "place.json");
      await writeFile(input, req.body);
      await exec(options.python || process.env.BOBUX_PYTHON || "python3", [resolve(options.worker || fileURLToPath(new URL("./convert_place.py", import.meta.url))), converter, input, output], { timeout: 45000, killSignal: "SIGKILL", maxBuffer: 512 * 1024, windowsHide: true });
      if ((await stat(output)).size > 96 * 1024 * 1024) throw new Error("output too large");
      const data = JSON.parse(await readFile(output, "utf8"));
      if (!data.instances || !Array.isArray(data.hierarchy)) throw new Error("invalid place");
      res.set("Cache-Control", "no-store").json({ ok: true, place: data });
    } catch {
      res.status(422).json({ error: "Не удалось преобразовать карту: повреждённый файл или превышен лимит обработки (45 секунд / 96 МБ структуры). Текущая карта сохранена." });
    } finally {
      active--;
      if (directory) await rm(directory, { recursive: true, force: true });
    }
  });
}
