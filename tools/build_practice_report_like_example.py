from __future__ import annotations

import json
import math
from copy import deepcopy
from pathlib import Path
from zipfile import ZipFile

from docx import Document
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Inches, Pt, RGBColor
from PIL import Image, ImageDraw, ImageFont


ROOT = Path("C:/robloxclone")
PRACTICE_DIR = ROOT / "практика"
SOURCE_DIR = PRACTICE_DIR / "Учебно-технологическая практика"
TEMPLATE_DOCX = SOURCE_DIR / "Пример отчета УТП.docx"
STATS_PATH = PRACTICE_DIR / "bobux_network_module_stats_2026-07-03.json"
OUT_DOCX = PRACTICE_DIR / "Отчет_УТП_сетевой_модуль_Bobux_по_образцу.docx"
LEGACY_OUT_DOCX = PRACTICE_DIR / "Отчет_УТП_сетевой_модуль_Bobux.docx"
OUT_MD = PRACTICE_DIR / "Отчет_УТП_сетевой_модуль_Bobux_по_образцу.md"
HEADER_IMAGE = PRACTICE_DIR / "example_report_header.png"
FIG_ARCH = PRACTICE_DIR / "report_architecture_template_style.png"
FIG_AUTH = PRACTICE_DIR / "report_auth_flow_template_style.png"
FIG_STATS = PRACTICE_DIR / "report_stats_template_style.png"


def font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    candidates = [
        r"C:\Windows\Fonts\timesbd.ttf" if bold else r"C:\Windows\Fonts\times.ttf",
        r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf",
    ]
    for item in candidates:
        if Path(item).exists():
            return ImageFont.truetype(item, size)
    return ImageFont.load_default()


def load_stats() -> dict:
    if STATS_PATH.exists():
        return json.loads(STATS_PATH.read_text(encoding="utf-8"))
    return {
        "database": {"collection_counts": {}, "pocketbase_data_mb": 0},
        "storage": {"public_storage_mb": 0},
        "accounts": {"auth_users": 0, "profiles": 0, "named_profiles": 0},
        "creation": {
            "maps": 0,
            "map_creators": 0,
            "total_visits": 0,
            "total_likes": 0,
            "model_assets": 0,
            "avatar_items": 0,
            "inventory_records": 0,
        },
        "social": {"friendships": 0},
        "realtime": {"players_online": 0, "active_servers": 0},
    }


def draw_box(draw: ImageDraw.ImageDraw, xy: tuple[int, int, int, int], title: str, lines: list[str], fill: str) -> None:
    x1, y1, x2, y2 = xy
    draw.rounded_rectangle(xy, radius=18, fill=fill, outline="#404040", width=2)
    draw.text((x1 + 18, y1 + 14), title, fill="#111111", font=font(28, True))
    y = y1 + 58
    for line in lines:
        draw.text((x1 + 22, y), line, fill="#111111", font=font(22))
        y += 34


def draw_arrow(draw: ImageDraw.ImageDraw, start: tuple[int, int], end: tuple[int, int], label: str = "") -> None:
    x1, y1 = start
    x2, y2 = end
    draw.line((x1, y1, x2, y2), fill="#333333", width=4)
    angle = math.atan2(y2 - y1, x2 - x1)
    for offset in (2.55, -2.55):
        draw.line(
            (
                x2,
                y2,
                x2 - 20 * math.cos(angle + offset),
                y2 - 20 * math.sin(angle + offset),
            ),
            fill="#333333",
            width=4,
        )
    if label:
        mx, my = (x1 + x2) // 2, (y1 + y2) // 2
        draw.rounded_rectangle((mx - 82, my - 22, mx + 82, my + 22), radius=8, fill="white", outline="#888888")
        draw.text((mx - 70, my - 13), label, fill="#111111", font=font(20))


def build_figures(stats: dict) -> None:
    img = Image.new("RGB", (1500, 850), "white")
    d = ImageDraw.Draw(img)
    d.text((55, 38), "Архитектура сетевого модуля Bobux", fill="#111111", font=font(42, True))
    draw_box(d, (70, 145, 390, 330), "Клиент Godot", ["cloud_api.gd", "client_network.gd", "экран входа, лобби", "каталог, аватар"], "#F2F2F2")
    draw_box(d, (565, 145, 905, 330), "HTTP API", ["Node.js / Express", "проверка запросов", "маршруты /api", "админ-статистика"], "#EAF2F8")
    draw_box(d, (1080, 145, 1430, 330), "PocketBase", ["профили игроков", "карты и предметы", "друзья", "инвентарь"], "#F2F2F2")
    draw_box(d, (565, 500, 905, 690), "Игровой сервер", ["Godot headless", "игровые комнаты", "heartbeat", "синхронизация"], "#F8F4EA")
    draw_box(d, (1080, 500, 1430, 690), "Хранилище файлов", ["превью карт", "ассеты моделей", "картинки одежды", "публичные ссылки"], "#F2F2F2")
    draw_arrow(d, (390, 238), (565, 238), "REST")
    draw_arrow(d, (905, 238), (1080, 238), "PB API")
    draw_arrow(d, (720, 330), (720, 500), "WS")
    draw_arrow(d, (905, 590), (1080, 590), "files")
    img.save(FIG_ARCH)

    img = Image.new("RGB", (1500, 850), "white")
    d = ImageDraw.Draw(img)
    d.text((55, 38), "Сценарий авторизации и загрузки профиля", fill="#111111", font=font(42, True))
    steps = [
        ("1", "Пользователь вводит логин и пароль", "клиент Godot формирует HTTPS-запрос к API"),
        ("2", "API проверяет учетные данные", "сервер обращается к PocketBase и получает auth record"),
        ("3", "Создается или обновляется профиль", "профиль содержит username, avatar_data и публичные поля"),
        ("4", "Клиент получает токен и данные", "после входа загружаются друзья, инвентарь, каталог и карты"),
        ("5", "Игрок подключается к серверу", "игровой сервер получает подтвержденные данные пользователя"),
    ]
    y = 145
    for num, title, desc in steps:
        d.ellipse((70, y, 125, y + 55), fill="#D9EAF7", outline="#333333", width=2)
        d.text((88, y + 10), num, fill="#111111", font=font(28, True))
        d.rounded_rectangle((160, y - 8, 1390, y + 82), radius=14, fill="#F7F7F7", outline="#777777")
        d.text((185, y + 3), title, fill="#111111", font=font(28, True))
        d.text((185, y + 40), desc, fill="#222222", font=font(22))
        if num != "5":
            d.line((98, y + 58, 98, y + 118), fill="#333333", width=3)
        y += 125
    img.save(FIG_AUTH)

    counts = {
        "auth users": stats["accounts"].get("auth_users", 0),
        "profiles": stats["accounts"].get("profiles", 0),
        "maps": stats["creation"].get("maps", 0),
        "inventory": stats["creation"].get("inventory_records", 0),
        "friends": stats["social"].get("friendships", 0),
        "avatar items": stats["creation"].get("avatar_items", 0),
    }
    img = Image.new("RGB", (1500, 850), "white")
    d = ImageDraw.Draw(img)
    d.text((55, 38), "Фактические показатели базы данных", fill="#111111", font=font(42, True))
    max_value = max(counts.values()) or 1
    x0, y0 = 125, 700
    bar_w, gap = 150, 65
    for i, (name, value) in enumerate(counts.items()):
        x = x0 + i * (bar_w + gap)
        h = int((value / max_value) * 450)
        d.rectangle((x, y0 - h, x + bar_w, y0), fill="#6FA8DC", outline="#333333")
        d.text((x, y0 + 22), name, fill="#111111", font=font(20))
        d.text((x + 25, y0 - h - 34), str(value), fill="#111111", font=font(26, True))
    d.line((100, y0, 1400, y0), fill="#333333", width=3)
    d.text(
        (90, 760),
        f"Размер данных PocketBase: {stats['database'].get('pocketbase_data_mb', 0)} МБ; "
        f"файловое хранилище: {stats['storage'].get('public_storage_mb', 0)} МБ",
        fill="#111111",
        font=font(24),
    )
    img.save(FIG_STATS)


def extract_header_image() -> None:
    if HEADER_IMAGE.exists():
        return
    with ZipFile(TEMPLATE_DOCX) as zf:
        for name in ("word/media/image21.jpeg", "word/media/image21.jpg", "word/media/image21.png"):
            if name in zf.namelist():
                HEADER_IMAGE.write_bytes(zf.read(name))
                return


def set_style_font(style, size: float, bold: bool = False) -> None:
    style.font.name = "Times New Roman"
    style._element.rPr.rFonts.set(qn("w:ascii"), "Times New Roman")
    style._element.rPr.rFonts.set(qn("w:hAnsi"), "Times New Roman")
    style._element.rPr.rFonts.set(qn("w:eastAsia"), "Times New Roman")
    style.font.size = Pt(size)
    style.font.bold = bold
    style.font.color.rgb = RGBColor(0, 0, 0)


def configure_styles(doc: Document) -> None:
    for sec in doc.sections:
        sec.page_width = Cm(21)
        sec.page_height = Cm(29.7)
        sec.top_margin = Cm(2)
        sec.bottom_margin = Cm(2)
        sec.left_margin = Cm(3)
        sec.right_margin = Cm(1.5)
        sec.header_distance = Cm(0)
        sec.footer_distance = Cm(1.25)

    normal = doc.styles["Normal"]
    set_style_font(normal, 12)
    normal.paragraph_format.first_line_indent = Cm(1.25)
    normal.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    normal.paragraph_format.line_spacing = 1.5
    normal.paragraph_format.space_after = Pt(0)
    normal.paragraph_format.space_before = Pt(0)

    for name in ("Heading 1", "Heading 2", "Heading 3"):
        if name not in doc.styles:
            continue
        style = doc.styles[name]
        set_style_font(style, 14 if name == "Heading 1" else 12, True)
        style.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER if name == "Heading 1" else WD_ALIGN_PARAGRAPH.JUSTIFY
        style.paragraph_format.first_line_indent = Cm(1.25 if name != "Heading 1" else 0)
        style.paragraph_format.line_spacing = 1.5
        style.paragraph_format.space_before = Pt(0)
        style.paragraph_format.space_after = Pt(6 if name == "Heading 1" else 0)

    if "List Paragraph" in doc.styles:
        style = doc.styles["List Paragraph"]
        set_style_font(style, 12)
        style.paragraph_format.first_line_indent = Cm(1.25)
        style.paragraph_format.left_indent = Cm(0)
        style.paragraph_format.line_spacing = 1.5
        style.paragraph_format.space_after = Pt(0)

    if "toc 1" in doc.styles:
        style = doc.styles["toc 1"]
        set_style_font(style, 12)
        style.paragraph_format.first_line_indent = Cm(0)
        style.paragraph_format.line_spacing = 1.0
        style.paragraph_format.space_after = Pt(0)

    if "Header" in doc.styles:
        set_style_font(doc.styles["Header"], 12)
    if "Footer" in doc.styles:
        set_style_font(doc.styles["Footer"], 12)


def add_page_number(paragraph) -> None:
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = paragraph.add_run()
    fmt_run(run, size=12)
    fld_begin = OxmlElement("w:fldChar")
    fld_begin.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = "PAGE"
    fld_sep = OxmlElement("w:fldChar")
    fld_sep.set(qn("w:fldCharType"), "separate")
    txt = OxmlElement("w:t")
    txt.text = "1"
    fld_end = OxmlElement("w:fldChar")
    fld_end.set(qn("w:fldCharType"), "end")
    run._r.append(fld_begin)
    run._r.append(instr)
    run._r.append(fld_sep)
    run._r.append(txt)
    run._r.append(fld_end)


def configure_header_footer(doc: Document) -> None:
    section = doc.sections[0]
    section.different_first_page_header_footer = False
    header = section.header
    hp = header.paragraphs[0]
    hp.alignment = WD_ALIGN_PARAGRAPH.CENTER
    # The example document contains an unrelated college logo in the header.
    # Keep the header intentionally empty so the Bobux practice report does not
    # inherit the "Международный Восточно-Европейский колледж" branding.
    footer = section.footer
    fp = footer.paragraphs[0]
    add_page_number(fp)


def fmt_run(run, size: float = 12, bold: bool = False) -> None:
    run.font.name = "Times New Roman"
    run._element.rPr.rFonts.set(qn("w:ascii"), "Times New Roman")
    run._element.rPr.rFonts.set(qn("w:hAnsi"), "Times New Roman")
    run._element.rPr.rFonts.set(qn("w:eastAsia"), "Times New Roman")
    run.font.size = Pt(size)
    run.bold = bold
    run.font.color.rgb = RGBColor(0, 0, 0)


def add_plain(doc: Document, text: str = "", *, align=None, first: bool = True, bold: bool = False, size: float = 12):
    p = doc.add_paragraph()
    p.alignment = align if align is not None else WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.first_line_indent = Cm(1.25 if first else 0)
    p.paragraph_format.line_spacing = 1.5
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.space_before = Pt(0)
    if text:
        r = p.add_run(text)
        fmt_run(r, size=size, bold=bold)
    return p


def add_center(doc: Document, text: str, *, size: float = 12, bold: bool = False):
    return add_plain(doc, text, align=WD_ALIGN_PARAGRAPH.CENTER, first=False, bold=bold, size=size)


def add_heading(doc: Document, text: str):
    p = doc.add_paragraph(style="Heading 1")
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.first_line_indent = Cm(0)
    p.paragraph_format.line_spacing = 1.5
    p.paragraph_format.space_after = Pt(6)
    r = p.add_run(text)
    fmt_run(r, size=14, bold=True)
    return p


def add_subheading(doc: Document, text: str):
    p = add_plain(doc, text, bold=True)
    return p


def add_bullet(doc: Document, text: str):
    p = doc.add_paragraph(style="List Paragraph")
    p.paragraph_format.first_line_indent = Cm(1.25)
    p.paragraph_format.left_indent = Cm(0)
    p.paragraph_format.line_spacing = 1.5
    r = p.add_run(text)
    fmt_run(r, size=12)
    return p


def add_table(doc: Document, headers: list[str], rows: list[list[str]]) -> None:
    table = doc.add_table(rows=1, cols=len(headers))
    table.style = "Table Grid"
    table.autofit = True
    for i, h in enumerate(headers):
        cell = table.rows[0].cells[i]
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        r = p.add_run(h)
        fmt_run(r, size=11, bold=True)
    for row in rows:
        cells = table.add_row().cells
        for i, text in enumerate(row):
            cell = cells[i]
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            p = cell.paragraphs[0]
            p.paragraph_format.first_line_indent = Cm(0)
            p.paragraph_format.line_spacing = 1.0
            r = p.add_run(str(text))
            fmt_run(r, size=10.5)
    add_plain(doc, "", first=False)


def add_figure(doc: Document, path: Path, caption: str, width_inches: float = 4.6) -> None:
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run()
    run.add_picture(str(path), width=Inches(width_inches))
    if caption:
        cap = add_center(doc, caption, size=12)
        cap.paragraph_format.line_spacing = 1.0
        cap.paragraph_format.space_after = Pt(0)


def page_break(doc: Document) -> None:
    p = doc.add_paragraph()
    p.add_run().add_break(WD_BREAK.PAGE)


def add_title_page(doc: Document) -> None:
    add_center(doc, "МИНИСТЕРСТВО НАУКИ И ВЫСШЕГО ОБРАЗОВАНИЯРОССИЙСКОЙ ФЕДЕРАЦИИ", bold=True)
    add_center(doc, "ФЕДЕРАЛЬНОЕ ГОСУДАРСТВЕННОЕ АВТОНОМНОЕ ОБРАЗОВАТЕЛЬНОЕ УЧРЕЖДЕНИЕ ВЫСШЕГО ОБРАЗОВАНИЯ", bold=True)
    add_center(doc, "«БАЛТИЙСКИЙ ФЕДЕРАЛЬНЫЙ УНИВЕРСИТЕТ ИМЕНИ ИММАНУИЛА КАНТА»", bold=True)
    for _ in range(5):
        add_plain(doc, "", first=False)
    add_center(doc, "ОТЧЕТ", size=16)
    add_center(doc, "по учебно-технологической практике")
    add_center(doc, "на тему: «Разработка сетевого модуля игровой платформы Bobux»")
    add_center(doc, "студента 1 курса группы [номер группы]")
    add_center(doc, "специальности 01.03.02 Прикладная математика и информатика")
    add_center(doc, "[ФИО студента]")
    for _ in range(2):
        add_plain(doc, "", first=False)
    add_center(doc, "Отметка о защите отчета")
    add_plain(doc, "Отчет защищен с оценкой ____________________", first=False)
    add_plain(doc, "«___»____________ 20____г.", first=False)
    for _ in range(3):
        add_plain(doc, "", first=False)
    add_plain(doc, "Руководитель учебно-технологической практики ____________________ [ФИО руководителя]", first=False)
    add_center(doc, "Калининград 2026")
    page_break(doc)


def add_toc(doc: Document) -> None:
    add_center(doc, "Содержание", size=14, bold=True)
    add_plain(doc, "", first=False)
    entries = [
        ("Введение", "3"),
        ("1. Описание постановки задачи", "5"),
        ("2. Структура ролей пользователей", "7"),
        ("3. Обоснование выбора технологий", "9"),
        ("4. Описание архитектуры сетевого модуля", "11"),
        ("5. Описание программных модулей регистрации и авторизации", "13"),
        ("6. Описание программного модуля пользовательского контента", "15"),
        ("7. Описание программного модуля игровых серверов", "17"),
        ("8. Описание административного модуля статистики", "18"),
        ("9. Тестирование сетевого модуля", "19"),
        ("Заключение", "21"),
        ("Список литературы", "22"),
        ("Приложение А. Основные файлы проекта", "23"),
        ("Приложение Б. Сценарий демонстрации", "24"),
    ]
    entries.append(("Приложение В. План иллюстраций и скриншотов", "23"))
    actual_pages = ["3", "5", "7", "9", "11", "13", "14", "16", "17", "18", "19", "20", "21", "22", "23"]
    entries = [(title, actual_pages[index] if index < len(actual_pages) else page) for index, (title, page) in enumerate(entries)]
    for title, page in entries:
        p = doc.add_paragraph(style="toc 1" if "toc 1" in doc.styles else None)
        p.paragraph_format.first_line_indent = Cm(0)
        p.paragraph_format.line_spacing = 1.0
        r = p.add_run(f"{title}\t{page}")
        fmt_run(r, size=12)
    page_break(doc)


def section(doc: Document, title: str, paragraphs: list[str], *, figure: tuple[Path, str] | None = None, table=None) -> None:
    add_heading(doc, title)
    for item in paragraphs:
        if item.startswith("• "):
            add_bullet(doc, item[2:])
        elif item.startswith("# "):
            add_subheading(doc, item[2:])
        else:
            add_plain(doc, item)
    if table:
        add_table(doc, table[0], table[1])
        add_plain(
            doc,
            "Сведения, приведенные в таблице, используются в сетевом модуле как контрольные точки: по ним можно проверить, какие данные хранятся на сервере, какие операции выполняет клиент и какие результаты должны быть получены при демонстрации проекта.",
        )
        add_plain(
            doc,
            "Такое представление удобно для защиты, поскольку показывает не только текстовое описание, но и связь между требованиями практики, архитектурой проекта и фактической реализацией в исходном коде.",
        )
    if figure:
        add_figure(doc, figure[0], figure[1])
    page_break(doc)


def content(stats: dict) -> list[tuple[str, list[str], tuple[Path, str] | None, tuple[list[str], list[list[str]]] | None]]:
    db_counts = stats["database"].get("collection_counts", {})
    return [
        (
            "Введение",
            [
                "Учебно-технологическая практика была связана с проектированием, реализацией и проверкой сетевого модуля игровой платформы Bobux. Платформа разрабатывается как многопользовательская среда, в которой игроки могут регистрироваться, входить в учетную запись, создавать карты, публиковать игровые предметы, взаимодействовать с друзьями и подключаться к игровым серверам. Центральной частью такой системы является сетевой модуль, обеспечивающий связь между клиентом, сервером приложений, базой данных и игровыми комнатами.",
                "Актуальность выбранной темы определяется тем, что современные игровые платформы фактически являются распределенными информационными системами. Даже если визуальная часть создается в игровом движке, основные данные должны храниться на сервере: учетные записи, профили игроков, список друзей, каталог предметов, инвентарь, карты, статистика посещений и состояние активных серверов. Без устойчивого сетевого слоя такая платформа не может масштабироваться и не может считаться полноценным сервисом.",
                "Целью работы является разработка и документирование сетевого модуля игровой платформы Bobux, который обеспечивает регистрацию и авторизацию пользователей, хранение профилей и пользовательского контента, загрузку данных каталога, работу с социальными связями, обмен сведениями об активных игровых серверах и предоставление административной статистики.",
                "Для достижения цели были поставлены следующие задачи:",
                "• изучить требования учебно-технологической практики к веб-сервису с базой данных, регистрацией, авторизацией, загрузкой изображений, поиском и разграничением прав;",
                "• определить роли пользователей и перечень данных, которые должны храниться на стороне сервера;",
                "• реализовать взаимодействие клиента Godot с серверным API и базой PocketBase;",
                "• обеспечить хранение карт, предметов, файлов и статистики в едином серверном контуре;",
                "• подготовить административную статистику, позволяющую оценивать фактическое состояние проекта;",
                "• проверить работоспособность сетевого модуля на реальных данных и оформить результаты в виде отчета.",
                "Объектом исследования является игровая платформа Bobux как программная система. Предметом исследования является сетевой модуль этой платформы, включающий клиент-серверное взаимодействие, базу данных, файловое хранилище, механизм авторизации, систему пользовательского контента и статистический административный интерфейс.",
                "В ходе практики использовались Godot 4, GDScript, Node.js, Express, PocketBase, HTTP API, WebSocket-соединения, файловое хранилище на VPS, а также инструменты проверки серверного состояния. Итогом работы стал модуль, который можно использовать как основу для дальнейшего расширения игровой платформы.",
            ],
            None,
            None,
        ),
        (
            "1. Описание постановки задачи",
            [
                "Техническое задание на разработку сетевого модуля игровой платформы Bobux",
                "# 1.1. Назначение документа",
                "Настоящее техническое задание определяет требования к сетевому модулю игровой платформы Bobux. Документ описывает назначение системы, роли пользователей, функциональные возможности, состав программных модулей, требования к безопасности, хранению данных и проверке результата.",
                "# 1.2. Цель проекта",
                "Цель проекта состоит в создании серверной части игровой платформы, которая позволяет пользователю зарегистрироваться, пройти авторизацию, получить персональный профиль, создавать и публиковать карты, получать предметы из каталога, управлять аватаром, видеть друзей и подключаться к активным игровым серверам.",
                "# 1.3. Общие требования",
                "Система должна работать по принципу «сервер является главным источником данных». Клиент Godot отображает интерфейс и отправляет запросы, но не считается доверенным источником для важных операций. Все критичные действия, включая вход, сохранение профиля, получение инвентаря, публикацию контента и получение статистики, проходят через серверный API.",
                "Пользователь без авторизации должен иметь возможность открыть клиент, увидеть форму входа и зарегистрировать учетную запись. Авторизованный пользователь получает доступ к профилю, списку карт, каталогу предметов, друзьям, инвентарю, аватару и игровым сессиям. Администратор должен иметь возможность получать статистику по базе данных и состоянию сервисов.",
                "# 1.4. Функциональные требования",
                "Сетевой модуль должен поддерживать регистрацию, вход, загрузку профиля, сохранение данных аватара, публикацию карт, хранение превью и файлов, получение списка карт, работу с друзьями, получение каталога предметов, выдачу предметов пользователю, хранение инвентаря, регистрацию активных игровых серверов и получение административной статистики.",
                "Для соответствия заданию практики в проекте предусмотрены функции работы с базой данных, разграничение доступа для неавторизованного и авторизованного пользователя, загрузка изображений и файлов, создание, редактирование и удаление записей, поиск и вывод информации, а также серверная проверка входящих данных.",
                "# 1.5. Нефункциональные требования",
                "Система должна быть устойчивой к некорректным данным клиента, поддерживать расширение количества коллекций в базе, не блокировать вход пользователя при частичной недоступности второстепенных данных, а также предоставлять понятные ошибки для клиента. При загрузке файлов должны учитываться ограничения размера и допустимые форматы.",
                "Серверный модуль должен быть развернут на VPS, запускаться как отдельный процесс, перезапускаться средствами process manager, работать за HTTP-прокси и иметь отдельные endpoints для проверки состояния. Данные должны храниться централизованно в PocketBase и файловом хранилище, что позволяет переносить клиентские сборки без потери пользовательского состояния.",
            ],
            None,
            None,
        ),
        (
            "2. Структура ролей пользователей",
            [
                "В сетевом модуле выделены три основные роли: неавторизованный посетитель, авторизованный игрок и администратор. Такое деление позволяет разделить права доступа и не раскрывать серверные функции пользователю, который не прошел вход.",
                "Неавторизованный посетитель может открыть клиент и выполнить регистрацию или вход. На этом этапе пользователь не получает доступ к персональным данным, инвентарю, списку друзей и операциям публикации контента. Такой подход снижает риск несанкционированного изменения данных и соответствует требованию разграничения прав.",
                "Авторизованный игрок является основной ролью системы. Он может загружать свой профиль, просматривать карты, получать и надевать предметы, сохранять настройки аватара, работать с друзьями, создавать карты и подключаться к игровым серверам. При этом клиент не изменяет данные напрямую в базе: все операции проходят через API.",
                "Администратор получает доступ к статистике и служебной информации. В рамках практической работы был расширен административный endpoint, который позволяет получить количество учетных записей, профилей, карт, предметов, записей инвентаря, дружеских связей, размер базы PocketBase и размер файлового хранилища.",
                "Отдельно можно выделить служебную роль игрового сервера. Игровой сервер сообщает API о своем состоянии, количестве игроков и доступности комнаты. Для этого используется heartbeat-механизм, который не должен быть доступен обычным пользователям.",
            ],
            None,
            (
                ["Роль", "Доступные функции"],
                [
                    ["Неавторизованный пользователь", "Регистрация, вход, получение публичной информации"],
                    ["Авторизованный игрок", "Профиль, друзья, карты, каталог, инвентарь, аватар, подключение к игровым серверам"],
                    ["Администратор", "Статистика базы данных, контроль сервисов, анализ состояния платформы"],
                    ["Игровой сервер", "Регистрация активной комнаты, heartbeat, передача сведений о сессии"],
                ],
            ),
        ),
        (
            "3. Обоснование выбора технологий",
            [
                "Для клиентской части используется игровой движок Godot 4. Он подходит для проекта, так как позволяет создавать 3D-игру, пользовательский интерфейс, редактор карт и сетевое взаимодействие в единой среде. Клиентская логика написана на GDScript, что упрощает интеграцию с узлами сцены, интерфейсом и игровыми объектами.",
                "Серверный API реализован на Node.js с использованием Express. Выбор этой технологии обусловлен удобной работой с HTTP-запросами, большим количеством библиотек, простотой развертывания на VPS и хорошей совместимостью с JSON-форматом, который используется клиентом Godot.",
                "Для хранения данных используется PocketBase. Это компактная серверная база данных, объединяющая SQLite, REST API, коллекции, пользователей и файловое хранилище. Для учебного проекта PocketBase удобен тем, что позволяет быстро описывать коллекции, хранить записи и связывать их с файлами.",
                "Для обмена данными между клиентом и сервером используются HTTP-запросы. Такой подход подходит для операций входа, загрузки профиля, получения каталога, сохранения аватара, публикации карты и запроса статистики. Для игровых сессий используется отдельный сетевой слой Godot, потому что передача игрового состояния требует более частого обмена событиями.",
                "Для эксплуатации на сервере применяются VPS, Nginx и PM2. Nginx выполняет маршрутизацию публичных запросов, а PM2 поддерживает Node.js API в рабочем состоянии и перезапускает процесс при сбоях. Такой набор технологий соответствует реальному сценарию развертывания веб-сервиса.",
                "Выбранная архитектура оставляет возможность дальнейшего расширения: можно добавлять новые коллекции, новые API-маршруты, отдельные игровые серверы, дополнительные административные отчеты и более сложную систему прав доступа. Это важно, поскольку игровая платформа должна развиваться постепенно.",
            ],
            None,
            (
                ["Компонент", "Используемая технология", "Назначение"],
                [
                    ["Клиент", "Godot 4, GDScript", "Интерфейс игры, лобби, редактор, подключение к серверам"],
                    ["API", "Node.js, Express", "Маршруты авторизации, профилей, каталога и статистики"],
                    ["База данных", "PocketBase", "Хранение пользователей, карт, предметов и социальных связей"],
                    ["Сетевые сессии", "Godot multiplayer", "Игровые комнаты и обмен событиями между игроками"],
                    ["Развертывание", "VPS, Nginx, PM2", "Публичный доступ, проксирование и контроль процессов"],
                ],
            ),
        ),
        (
            "4. Описание архитектуры сетевого модуля",
            [
                "Сетевой модуль Bobux построен по многоуровневой схеме. На первом уровне находится клиент Godot, который отвечает за интерфейс, сбор действий пользователя и отображение данных. На втором уровне расположен серверный API, принимающий запросы и выполняющий проверку данных. На третьем уровне находится база PocketBase и файловое хранилище.",
                "Клиентская часть обращается к серверу через модуль cloud_api.gd. В этом модуле сосредоточены функции входа, регистрации, загрузки профиля, получения друзей, карт, каталога и сохранения аватара. Такое разделение удобно, потому что интерфейс не должен знать детали HTTP-запросов и формат конкретных серверных маршрутов.",
                "Серверная часть реализована в файле services/bobux_api/server.js. Она принимает запросы клиента, проверяет параметры, обращается к PocketBase и возвращает унифицированные JSON-ответы. Серверный слой также содержит обработку ошибок, нормализацию данных и административные функции.",
                "PocketBase используется как основное хранилище. В нем находятся коллекции профилей, карт, активных серверов, моделей, предметов аватара, каталога, инвентаря и дружеских связей. Файлы, связанные с картами и предметами, хранятся отдельно, но доступны через публичные URL.",
                "Игровой сервер является отдельным процессом Godot. Он отвечает за конкретную игровую комнату и взаимодействие игроков внутри нее. API хранит сведения об активных серверах, что позволяет лобби показывать доступные комнаты и подключать игрока к нужному адресу.",
                "Архитектура построена так, чтобы клиент не мог самостоятельно назначить себе предмет, подделать профиль или изменить статистику карты напрямую. Все такие действия должны проходить через сервер, где можно проверить пользователя и корректность операции.",
            ],
            (FIG_ARCH, "Рисунок 1 - Архитектура сетевого модуля игровой платформы Bobux"),
            None,
        ),
        (
            "5. Описание программных модулей регистрации и авторизации",
            [
                "Модуль регистрации и авторизации является входной точкой сетевой системы. Он решает две задачи: подтверждает личность пользователя и связывает игрового клиента с серверным профилем. Без этого этапа невозможно корректно хранить инвентарь, друзей, созданные карты и настройки аватара.",
                "При регистрации клиент передает имя пользователя, адрес электронной почты или иной идентификатор и пароль. Сервер проверяет допустимость данных, создает учетную запись в PocketBase и формирует связанный профиль игрока. Профиль нужен для публичных данных, которые отображаются другим пользователям.",
                "При входе пользователь отправляет учетные данные на API. Сервер обращается к PocketBase, получает auth-запись и возвращает клиенту результат авторизации. После успешного входа клиент последовательно загружает профиль, данные аватара, друзей, инвентарь, каталог и список карт.",
                "Важной особенностью реализации является разделение auth-записи и игрового профиля. Auth-запись отвечает за безопасность входа, а профиль хранит игровые данные: имя, статус, внешний вид, статистику и связи с пользовательским контентом. Такое разделение упрощает дальнейшее развитие проекта.",
                "Для повышения устойчивости входа сетевой модуль должен обрабатывать частичные ошибки. Например, если список друзей временно не загрузился, клиент не должен полностью зависать после авторизации. Основной профиль и токен входа являются критичными, а вторичные данные могут догружаться отдельно.",
                "В рамках подготовки проекта к защите был описан и проверен сценарий загрузки профиля после входа. Он показывает, какие компоненты участвуют в операции и почему сервер остается главным источником данных.",
            ],
            (FIG_AUTH, "Рисунок 2 - Сценарий авторизации и загрузки профиля"),
            None,
        ),
        (
            "6. Описание программного модуля пользовательского контента",
            [
                "Пользовательский контент является важной частью игровой платформы. В Bobux к нему относятся карты, модели, предметы аватара, превью, изображения одежды, записи инвентаря и сведения о публикации. Сетевой модуль отвечает за то, чтобы эти данные сохранялись централизованно и могли быть загружены с любого клиента.",
                "Модуль карт позволяет игроку создать карту в редакторе, сохранить ее на сервере и отобразить в списке доступных режимов. Для каждой карты хранятся название, владелец, статус публикации, счетчики посещений и лайков, дата обновления и путь к превью. Это позволяет строить каталог карт и сортировать их по популярности.",
                "Модуль предметов аватара хранит данные о вещах, которые создаются пользователями. Для каждого предмета сохраняется тип, название, автор, публичность, ссылка на превью и данные, необходимые для применения предмета к персонажу. Такой подход позволяет отделить описание предмета от самого клиента.",
                "Инвентарь связывает пользователя и предмет. Если игрок получил предмет или создал его, в базе появляется запись, по которой клиент понимает, какие вещи доступны данному игроку. Это важно для защиты от ситуации, когда пользователь пытается надеть предмет, которого у него нет.",
                "Файловое хранилище используется для превью, изображений, ассетов карт и иных данных, которые нецелесообразно хранить внутри JSON-записей. Ссылки на файлы сохраняются в коллекциях PocketBase, а клиент получает готовый URL для загрузки.",
                "В задании практики отдельно указаны операции создания, редактирования, удаления и поиска записей. В контексте Bobux эти операции реализуются через карты, предметы, профиль, друзей и каталог. Пользователь создает карту или предмет, редактирует его параметры, может удалить или скрыть запись, а клиент выполняет поиск и фильтрацию по спискам.",
            ],
            None,
            (
                ["Коллекция", "Назначение", "Количество записей"],
                [
                    ["profiles", "Публичные профили игроков", str(db_counts.get("profiles", stats["accounts"].get("profiles", 0)))],
                    ["maps", "Пользовательские карты и режимы", str(db_counts.get("maps", stats["creation"].get("maps", 0)))],
                    ["avatar_items", "Предметы аватара", str(db_counts.get("avatar_items", stats["creation"].get("avatar_items", 0)))],
                    ["user_inventory", "Связь пользователя с предметами", str(db_counts.get("user_inventory", stats["creation"].get("inventory_records", 0)))],
                    ["friendships", "Социальные связи игроков", str(db_counts.get("friendships", stats["social"].get("friendships", 0)))],
                    ["active_servers", "Состояние игровых комнат", str(db_counts.get("active_servers", stats["realtime"].get("active_servers", 0)))],
                ],
            ),
        ),
        (
            "7. Описание программного модуля игровых серверов",
            [
                "Модуль игровых серверов отвечает за связь между лобби и конкретной игровой комнатой. Пользователь в лобби выбирает карту, после чего клиент должен получить адрес сервера, подключиться к нему и передать подтвержденные данные игрока. Если такой модуль отсутствует, платформа превращается только в локальный редактор без полноценного мультиплеера.",
                "В Bobux серверная часть разделяет HTTP API и игровой процесс. API хранит данные и выдает сведения о доступных серверах, а игровой сервер занимается синхронизацией игроков внутри карты. Это снижает нагрузку на API и позволяет масштабировать игровые комнаты отдельно.",
                "Игровой сервер периодически отправляет heartbeat. Такой запрос сообщает, что сервер жив, какая карта запущена, сколько игроков подключено и куда можно подключаться. Если heartbeat перестает приходить, запись сервера может считаться устаревшей и не должна показываться игрокам как доступная.",
                "Клиентский модуль client_network.gd отвечает за подключение к игровому серверу. Он получает адрес, открывает сетевое соединение и синхронизирует игровые сущности. Для пользователя этот процесс выглядит как переход из лобби в выбранный режим.",
                "Принцип «сервер главный» также важен в игровых сессиях. Клиент может отправлять действия, но окончательное состояние игрового мира должно подтверждаться сервером. Такой подход нужен для защиты от подмены позиции, инвентаря, состояния аватара и иных игровых данных.",
                "В дальнейшем модуль игровых серверов может быть расширен системой отдельных комнат, очередями подключения, автоматическим запуском серверов под популярные карты и передачей статистики посещений после завершения игровой сессии.",
            ],
            None,
            None,
        ),
        (
            "8. Описание административного модуля статистики",
            [
                "Административный модуль статистики нужен для контроля состояния игровой платформы. Он позволяет понять, сколько пользователей зарегистрировано, сколько профилей создано, сколько карт и предметов находится в базе, сколько записей хранится в инвентаре и какой объем занимает файловое хранилище.",
                "В рамках работы был расширен endpoint административной статистики. Теперь он возвращает не только количество основных сущностей, но и сведения о размере данных PocketBase, размере публичного хранилища, количестве записей в ключевых коллекциях и состоянии активных серверов.",
                "Такая статистика полезна при защите проекта, потому что показывает, что система не является демонстрационной страницей без данных. В базе уже есть реальные записи пользователей, карт, предметов, инвентаря и социальных связей. Следовательно, сетевой модуль обслуживает живые данные платформы.",
                f"На момент проверки в базе содержалось {stats['accounts'].get('auth_users', 0)} учетных записей авторизации, {stats['accounts'].get('profiles', 0)} профиля игроков, {stats['creation'].get('maps', 0)} карт, {stats['creation'].get('avatar_items', 0)} предмета аватара, {stats['creation'].get('inventory_records', 0)} записей инвентаря и {stats['social'].get('friendships', 0)} дружеских связей.",
                f"Размер данных PocketBase составил около {stats['database'].get('pocketbase_data_mb', 0)} МБ, а размер публичного файлового хранилища составил около {stats['storage'].get('public_storage_mb', 0)} МБ. Эти показатели подтверждают, что модуль работает не только с текстовыми записями, но и с файлами пользовательского контента.",
                "Административная статистика может использоваться для дальнейшего развития проекта: определения популярных карт, анализа роста базы, поиска перегруженных коллекций, контроля активности игровых серверов и подготовки технических отчетов.",
            ],
            None,
            None,
        ),
        (
            "9. Тестирование сетевого модуля",
            [
                "Проверка сетевого модуля выполнялась на нескольких уровнях. На уровне исходного кода проверялся синтаксис серверного файла Node.js. На уровне проекта Godot выполнялась headless-проверка загрузки проекта. На уровне сервера проверялся публичный endpoint состояния API.",
                "Функциональное тестирование включало сценарии входа пользователя, загрузки профиля, получения данных каталога, получения списка карт, сохранения данных аватара, обращения к статистике и проверки маршрутов, связанных с игровыми серверами. Эти сценарии соответствуют основным пользовательским действиям в платформе.",
                "Отдельно проверялась устойчивость при частичных ошибках загрузки. Для сетевой игровой платформы важно, чтобы отсутствие второстепенной информации не приводило к полной остановке клиента. Поэтому данные профиля, друзей, каталога и карт должны загружаться последовательно и с обработкой ошибок.",
                "Для проверки фактического состояния базы был получен JSON-отчет административной статистики. Он был сохранен в папку практики и использован при подготовке отчета. Такой подход делает результаты проверяемыми: преподаватель может видеть не только описание, но и реальные числовые показатели.",
                "По итогам проверки серверный модуль был усилен: административная статистика стала включать размеры базы и файлового хранилища, а также количества записей по основным коллекциям. Это улучшает наблюдаемость проекта и делает сетевой модуль более пригодным для сопровождения.",
            ],
            None,
            (
                ["Проверка", "Результат"],
                [
                    ["Синтаксис Node.js API", "Файл server.js проходит проверку node --check"],
                    ["Проверка проекта Godot", "Проект загружается в headless-режиме без критических ошибок компиляции"],
                    ["Публичный health endpoint", "Сервер возвращает состояние API"],
                    ["Административная статистика", "Получены показатели базы данных и хранилища"],
                    ["Проверка структуры отчета", "Документ собран по шаблону примера УТП"],
                ],
            ),
        ),
        (
            "Заключение",
            [
                "В ходе учебно-технологической практики был разработан и оформлен сетевой модуль игровой платформы Bobux. Модуль объединяет клиент Godot, серверный API, базу данных PocketBase, файловое хранилище и игровой сервер. Он обеспечивает регистрацию, авторизацию, загрузку профиля, работу с пользовательским контентом, каталогом, инвентарем, друзьями и активными игровыми комнатами.",
                "Разработанная архитектура соответствует принципу централизованного хранения данных. Клиент не является главным источником состояния, а обращается к серверу, который проверяет запросы и работает с базой. Это делает систему более надежной и позволяет развивать ее как полноценную игровую платформу.",
                "В проекте выполнены требования, характерные для веб-сервиса с базой данных: реализованы учетные записи, авторизация, вывод информации из базы, загрузка файлов, создание и изменение записей, разграничение доступа и серверная проверка данных. При этом предметная область адаптирована под игровую платформу, а не под стандартный интернет-магазин.",
                "Практическая ценность работы состоит в том, что сетевой модуль уже содержит реальные данные и может быть показан на защите. В базе имеются пользователи, карты, предметы, записи инвентаря и социальные связи. Административная статистика позволяет подтвердить состояние системы количественно.",
                "В дальнейшем проект может быть расширен улучшенным интерфейсом администратора, более подробной системой ролей, очередями игровых серверов, журналом событий, расширенной модерацией пользовательского контента и аналитикой активности игроков.",
            ],
            None,
            None,
        ),
    ]


def add_literature(doc: Document) -> None:
    add_heading(doc, "Список литературы")
    refs = [
        "Документация Godot Engine 4. URL: https://docs.godotengine.org/",
        "Документация PocketBase. URL: https://pocketbase.io/docs/",
        "Документация Node.js. URL: https://nodejs.org/",
        "Документация Express. URL: https://expressjs.com/",
        "MDN Web Docs: HTTP, REST и работа с web API. URL: https://developer.mozilla.org/",
        "Методические указания к выполнению примерного задания по учебно-технологической практике.",
        "Материалы задания на учебно-технологическую практику, выданные преподавателем.",
        "Исходный код проекта Bobux: клиент Godot, серверный API, сетевой модуль и инструменты развертывания.",
    ]
    for i, ref in enumerate(refs, start=1):
        add_plain(doc, f"{i}. {ref}", first=False)
    page_break(doc)


def add_appendix(doc: Document) -> None:
    add_heading(doc, "Приложение А. Основные файлы проекта")
    rows = [
        ["autoload/cloud_api.gd", "Клиентский модуль HTTP-запросов к серверному API"],
        ["autoload/client_network.gd", "Подключение клиента к игровому серверу"],
        ["services/bobux_api/server.js", "Основной серверный API, авторизация, данные и статистика"],
        ["server/server_main.gd", "Headless-игровой сервер и регистрация игровой комнаты"],
        ["tools/deploy_bobux_release.ps1", "Сборка и развертывание релизов"],
        ["практика/bobux_network_module_stats_2026-07-03.json", "Снимок административной статистики базы данных"],
    ]
    add_table(doc, ["Файл", "Назначение"], rows)
    add_plain(
        doc,
        "Данные файлы образуют основу сетевого модуля. Клиентская часть отвечает за запросы и подключение, серверный API управляет данными и безопасностью, а отдельный игровой сервер обеспечивает сетевые игровые сессии.",
    )


def add_appendix_b(doc: Document) -> None:
    page_break(doc)
    add_heading(doc, "Приложение Б. Сценарий демонстрации")
    add_plain(
        doc,
        "Для защиты проекта рекомендуется демонстрировать не весь игровой проект целиком, а именно сетевой модуль как самостоятельный результат практики. Такой подход соответствует согласованной теме и позволяет показать преподавателю конкретную разработанную часть платформы.",
    )
    add_plain(doc, "Демонстрацию можно провести в следующем порядке:", first=True)
    steps = [
        "1. Открыть клиент Bobux и показать форму входа, объяснив, что пользователь не получает доступ к профилю и данным без авторизации.",
        "2. Выполнить вход в учетную запись и показать, что после авторизации клиент загружает профиль, список карт, элементы аватара и связанные пользовательские данные.",
        "3. Открыть раздел карт или каталога и пояснить, что информация приходит из базы данных PocketBase через серверный API, а не хранится локально в клиенте.",
        "4. Показать статистику базы данных из подготовленного JSON-файла или административного endpoint: количество пользователей, профилей, карт, предметов, записей инвентаря и размер хранилища.",
        "5. Пояснить принцип работы игрового сервера: лобби получает сведения об активных комнатах, а игровой сервер отдельно отвечает за синхронизацию игроков в режиме.",
        "6. Завершить демонстрацию схемой архитектуры и подчеркнуть, что сервер является главным источником данных, а клиент только отображает состояние и отправляет запросы.",
    ]
    for step in steps:
        add_plain(doc, step, first=False)
    add_plain(
        doc,
        "Если преподаватель задаст вопрос о роли нейросетевых инструментов, корректная формулировка следующая: нейросетевые агенты использовались как вспомогательный инструмент анализа, документирования и ускорения разработки, однако сетевой модуль оформлен как инженерный результат проекта с проверяемой архитектурой, исходными файлами, серверной базой и фактическими метриками.",
    )


def add_appendix_c(doc: Document) -> None:
    page_break(doc)
    add_heading(doc, "Приложение В. План иллюстраций и скриншотов")
    add_plain(
        doc,
        "В данном приложении перечислены материалы, которые рекомендуется вставить в отчет вместо текстовых пометок или после соответствующих разделов. Скриншоты нужны для подтверждения того, что сетевой модуль действительно реализован в коде, работает в клиентском приложении и связан с серверной базой данных.",
    )
    add_plain(
        doc,
        "Если изображение вставляется в основную часть отчета, под ним следует использовать подпись вида: «Рисунок N - ...». При ручной верстке можно оставить не все изображения, но желательно включить минимум: экран входа, главное меню после авторизации, статистику базы данных, серверные маршруты авторизации, клиентский CloudAPI и WebSocket/heartbeat игрового сервера.",
    )
    rows = [
        ["1", "После введения или в разделе 5", "Окно входа/регистрации Bobux до авторизации пользователя.", "Рисунок 1 - Форма авторизации пользователя в клиенте Bobux."],
        ["2", "Раздел 4 или раздел 9", "Главное меню/лобби после успешного входа: виден профиль, игры или основные вкладки.", "Рисунок 2 - Главное меню платформы после загрузки профиля пользователя."],
        ["3", "Раздел 8", "Административная статистика или PocketBase: коллекции profiles, maps, avatar_items, user_inventory, active_servers.", "Рисунок 3 - Статистика и коллекции базы данных сетевого модуля."],
        ["4", "Раздел 5", "Код C:/robloxclone/services/bobux_api/server.js, строки 147 и 185: signup/login routes.", "Рисунок 4 - Серверные маршруты регистрации и авторизации."],
        ["5", "Раздел 8", "Код C:/robloxclone/services/bobux_api/server.js, строки 127 и 1004: admin stats endpoint и сбор статистики.", "Рисунок 5 - Формирование административной статистики базы данных."],
        ["6", "Раздел 5", "Код C:/robloxclone/autoload/cloud_api.gd, строки 250, 293, 329: регистрация, вход и синхронизация профиля.", "Рисунок 6 - Клиентский сценарий авторизации и синхронизации профиля."],
        ["7", "Раздел 6", "Код C:/robloxclone/services/bobux_api/server.js, строки 413, 471, 493: публикация предметов и загрузка каталога.", "Рисунок 7 - Серверная обработка пользовательского каталога."],
        ["8", "Раздел 6", "Код C:/robloxclone/autoload/cloud_api.gd, строки 395, 453, 1155, 1191, 1207: загрузка карт, ассетов и предметов.", "Рисунок 8 - Клиентский модуль публикации карт и предметов."],
        ["9", "Раздел 7", "Код C:/robloxclone/autoload/client_network.gd, строки 1024, 1329, 1427, 1460: подключение к WebSocket и вход в комнату.", "Рисунок 9 - WebSocket-подключение и подтверждение входа в игровую комнату."],
        ["10", "Раздел 7", "Код C:/robloxclone/server/server_main.gd, строки 10, 227, 330: запуск dedicated server и heartbeat active_servers.", "Рисунок 10 - Heartbeat выделенного игрового сервера."],
        ["11", "Приложение А или раздел 9", "Файл C:/robloxclone/практика/bobux_network_module_stats_2026-07-03.json или результат /api/admin/stats без секретов.", "Рисунок 11 - Фактические показатели базы данных проекта Bobux."],
        ["12", "Раздел 6 или приложение Б", "Каталог, инвентарь или профиль в клиенте, где видна загрузка пользовательских данных с сервера.", "Рисунок 12 - Отображение серверных данных в интерфейсе клиента."],
    ]
    add_table(doc, ["№", "Куда вставить", "Что заскринить", "Подпись под рисунком"], rows)
    add_plain(
        doc,
        "В коде рядом с нужными фрагментами добавлены комментарии PRACTICE SCREENSHOT. Их можно найти поиском по проекту и использовать как ориентир для скриншотов с доказательством реализации.",
    )


def build_markdown(stats: dict) -> None:
    text = f"""# Отчет по учебно-технологической практике

Тема: разработка сетевого модуля игровой платформы Bobux.

Документ Word собран по структуре и оформлению файла-примера `Пример отчета УТП.docx`.

Ключевые показатели базы данных на момент подготовки:

- auth users: {stats['accounts'].get('auth_users', 0)}
- profiles: {stats['accounts'].get('profiles', 0)}
- maps: {stats['creation'].get('maps', 0)}
- avatar items: {stats['creation'].get('avatar_items', 0)}
- inventory records: {stats['creation'].get('inventory_records', 0)}
- friendships: {stats['social'].get('friendships', 0)}
- PocketBase data: {stats['database'].get('pocketbase_data_mb', 0)} MB
- public storage: {stats['storage'].get('public_storage_mb', 0)} MB
"""
    OUT_MD.write_text(text, encoding="utf-8")


def build_docx() -> None:
    stats = load_stats()
    build_figures(stats)
    doc = Document()
    configure_styles(doc)
    configure_header_footer(doc)
    add_title_page(doc)
    add_toc(doc)
    for title, paragraphs, figure, table in content(stats):
        section(doc, title, paragraphs, figure=figure, table=table)
    add_literature(doc)
    add_appendix(doc)
    add_appendix_b(doc)
    add_appendix_c(doc)
    doc.save(OUT_DOCX)
    doc.save(LEGACY_OUT_DOCX)
    build_markdown(stats)
    print(OUT_DOCX)
    print(LEGACY_OUT_DOCX)


if __name__ == "__main__":
    build_docx()
