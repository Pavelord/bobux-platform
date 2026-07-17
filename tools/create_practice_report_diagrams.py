# -*- coding: utf-8 -*-
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


OUT_DIR = Path("C:/robloxclone/практика/готовые_рисунки_для_отчета")
WIDTH = 1400
HEIGHT = 1040


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        Path("C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf"),
        Path("C:/Windows/Fonts/timesbd.ttf" if bold else "C:/Windows/Fonts/times.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


def rounded_box(draw: ImageDraw.ImageDraw, xy: tuple[int, int, int, int], fill: str, outline: str, title: str, body: str) -> None:
    x1, y1, x2, y2 = xy
    draw.rounded_rectangle(xy, radius=22, fill=fill, outline=outline, width=4)
    draw.text((x1 + 28, y1 + 24), title, font=font(34, True), fill="#111827")
    y = y1 + 78
    for line in body.split("\n"):
        draw.text((x1 + 28, y), line, font=font(24), fill="#374151")
        y += 34


def arrow(draw: ImageDraw.ImageDraw, start: tuple[int, int], end: tuple[int, int], label: str = "") -> None:
    draw.line([start, end], fill="#2563eb", width=5)
    ex, ey = end
    sx, sy = start
    dx = 1 if ex >= sx else -1
    dy = 1 if ey >= sy else -1
    if abs(ex - sx) >= abs(ey - sy):
        points = [(ex, ey), (ex - 22 * dx, ey - 13), (ex - 22 * dx, ey + 13)]
    else:
        points = [(ex, ey), (ex - 13, ey - 22 * dy), (ex + 13, ey - 22 * dy)]
    draw.polygon(points, fill="#2563eb")
    if label:
        mx = int((sx + ex) / 2)
        my = int((sy + ey) / 2)
        bbox = draw.textbbox((0, 0), label, font=font(20, True))
        pad = 8
        draw.rounded_rectangle(
            (mx - (bbox[2] - bbox[0]) // 2 - pad, my - 19, mx + (bbox[2] - bbox[0]) // 2 + pad, my + 19),
            radius=10,
            fill="#eff6ff",
            outline="#bfdbfe",
            width=2,
        )
        draw.text((mx - (bbox[2] - bbox[0]) // 2, my - 13), label, font=font(20, True), fill="#1d4ed8")


def base(title: str) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGB", (WIDTH, HEIGHT), "#f8fafc")
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, WIDTH, 108), fill="#0f172a")
    draw.text((42, 32), title, font=font(38, True), fill="white")
    draw.text((42, 82), "сетевой модуль игровой платформы Bobux", font=font(22), fill="#cbd5e1")
    return image, draw


def make_architecture() -> None:
    image, draw = base("Общая структура сетевого модуля")
    rounded_box(draw, (70, 180, 430, 360), "#dbeafe", "#60a5fa", "Игровой клиент", "Godot / GDScript\nлогин, профиль, каталог\nподключение к режиму")
    rounded_box(draw, (520, 160, 880, 360), "#dcfce7", "#4ade80", "Bobux API", "Node.js / REST\nпроверка запросов\nработа с файлами")
    rounded_box(draw, (970, 180, 1330, 360), "#fef3c7", "#f59e0b", "PocketBase", "пользователи\nкарты и каталог\nфайловое хранилище")
    rounded_box(draw, (70, 560, 430, 760), "#ede9fe", "#a78bfa", "Игровой сервер", "Godot WebSocket\nкомната режима\nсостояние игроков")
    rounded_box(draw, (520, 570, 880, 770), "#fee2e2", "#f87171", "Active servers", "heartbeat комнат\nадрес подключения\nколичество игроков")
    rounded_box(draw, (970, 560, 1330, 760), "#e0f2fe", "#38bdf8", "Администратор", "статистика\nконтроль базы\nпроверка сервера")
    arrow(draw, (430, 260), (520, 260), "HTTP/JSON")
    arrow(draw, (880, 260), (970, 260), "CRUD/API")
    arrow(draw, (250, 560), (250, 360), "WebSocket")
    arrow(draw, (430, 660), (520, 660), "heartbeat")
    arrow(draw, (700, 570), (700, 360), "REST")
    arrow(draw, (1150, 560), (1150, 360), "stats")
    draw.text((72, 858), "Главная идея:", font=font(28, True), fill="#111827")
    draw.text((72, 902), "клиент не пишет критичные данные напрямую в базу, а работает через серверный API.", font=font(25), fill="#374151")
    draw.text((72, 940), "игровые комнаты живут отдельно и регистрируют себя через heartbeat.", font=font(25), fill="#374151")
    image.save(OUT_DIR / "01_architecture_network_module.png")


def make_roles() -> None:
    image, draw = base("Роли пользователей и компонентов")
    center = (500, 360, 900, 610)
    rounded_box(draw, center, "#e0f2fe", "#0284c7", "Сетевой модуль Bobux", "единые аккаунты\nсерверный API\nсинхронизация данных\nигровые комнаты")
    rounded_box(draw, (70, 180, 390, 360), "#dcfce7", "#22c55e", "Игрок", "входит в аккаунт\nвыбирает режим\nиграет на сервере")
    rounded_box(draw, (1010, 180, 1330, 360), "#fef3c7", "#f59e0b", "Создатель", "публикует карты\nсоздает предметы\nуправляет контентом")
    rounded_box(draw, (70, 660, 390, 840), "#fee2e2", "#ef4444", "Администратор", "смотрит статистику\nпроверяет базу\nконтролирует сервер")
    rounded_box(draw, (1010, 660, 1330, 840), "#ede9fe", "#8b5cf6", "Игровой сервер", "держит комнату\nобновляет heartbeat\nпринимает игроков")
    arrow(draw, (390, 270), (500, 420), "auth")
    arrow(draw, (1010, 270), (900, 420), "publish")
    arrow(draw, (390, 750), (500, 550), "stats")
    arrow(draw, (1010, 750), (900, 550), "room")
    draw.text((90, 900), "Разделение ролей показывает, почему проект является сетевым модулем:", font=font(27, True), fill="#111827")
    draw.text((90, 944), "клиент, API, база и игровой сервер выполняют разные задачи.", font=font(25), fill="#374151")
    image.save(OUT_DIR / "02_roles_network_module.png")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    make_architecture()
    make_roles()
    print(OUT_DIR)


if __name__ == "__main__":
    main()
