#!/usr/bin/env python3
"""Рендер документа архитектуры в одностраничный HTML.

Источник — markdown; HTML производное. Второго источника не заводится:
правка идёт в .md, страница пересобирается этим скриптом.

Запуск:  python3 scripts/render-doc.py <вход.md> <выход.html>

Печатает объём осмотренного — «ноль» обязано быть отличимо от «не запускали».
"""
import re
import sys

import markdown


CSS = """
:root{--bg:#fbfbfa;--fg:#1c1c1a;--mut:#6b6b64;--line:#e3e2dd;--acc:#7a2f2f;
      --code-bg:#f4f3ef;--warn-bg:#fdf6e7;--warn-br:#c99a2e;--ok-br:#3f7a4a}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{margin:0;background:var(--bg);color:var(--fg);
     font:16px/1.65 -apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif}
.wrap{display:grid;grid-template-columns:290px minmax(0,1fr);gap:0;max-width:1500px;margin:0 auto}
nav{position:sticky;top:0;align-self:start;max-height:100vh;overflow-y:auto;
    padding:28px 18px 60px;border-right:1px solid var(--line);font-size:13.5px}
nav a{display:block;color:var(--mut);text-decoration:none;padding:3px 0;line-height:1.4}
nav a:hover{color:var(--acc)}
nav a.h2{font-weight:600;color:var(--fg);margin-top:11px}
nav a.h3{padding-left:14px;font-size:12.8px}
main{padding:44px 52px 120px;min-width:0}
h1{font-size:31px;line-height:1.25;margin:0 0 6px;letter-spacing:-.4px}
h2{font-size:23px;margin:44px 0 12px;padding-top:14px;border-top:1px solid var(--line);letter-spacing:-.2px}
h3{font-size:18px;margin:28px 0 8px;color:#2c2c28}
h4{font-size:15.5px;margin:20px 0 6px}
p{margin:11px 0}
table{border-collapse:collapse;width:100%;margin:16px 0;font-size:14.2px;display:block;overflow-x:auto}
th,td{border:1px solid var(--line);padding:7px 10px;text-align:left;vertical-align:top}
th{background:#f2f1ec;font-weight:600}
tr:nth-child(even) td{background:#fdfdfc}
code{background:var(--code-bg);padding:1.5px 5px;border-radius:3px;
     font:13px/1.5 ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,monospace}
pre{background:var(--code-bg);border:1px solid var(--line);border-radius:6px;
    padding:14px 16px;overflow-x:auto;margin:14px 0}
pre code{background:none;padding:0;font-size:12.9px;line-height:1.55}
blockquote{margin:16px 0;padding:12px 18px;background:var(--warn-bg);
           border-left:4px solid var(--warn-br);border-radius:0 5px 5px 0}
blockquote p{margin:6px 0}
hr{border:0;border-top:1px solid var(--line);margin:36px 0}
ul,ol{padding-left:26px}
li{margin:5px 0}
strong{font-weight:640}
.meta{color:var(--mut);font-size:14px;margin:0 0 26px;padding-bottom:18px;border-bottom:1px solid var(--line)}
.tag{display:inline-block;background:#eceae3;border-radius:4px;padding:2px 9px;
     font-size:12.5px;color:#55534c;margin-right:7px}
@media(max-width:1000px){.wrap{grid-template-columns:1fr}nav{position:static;max-height:none;
  border-right:0;border-bottom:1px solid var(--line)}main{padding:26px 20px 80px}}
@media print{nav{display:none}.wrap{display:block}main{padding:0}}
"""


def slug(text: str, seen: dict) -> str:
    s = re.sub(r"[^\w\s-]", "", text.lower()).strip()
    s = re.sub(r"[\s]+", "-", s)
    s = s or "s"
    n = seen.get(s, 0)
    seen[s] = n + 1
    return s if n == 0 else f"{s}-{n}"


def main() -> int:
    if len(sys.argv) != 3:
        print("использование: render-doc.py <вход.md> <выход.html>", file=sys.stderr)
        return 2
    src, dst = sys.argv[1], sys.argv[2]

    with open(src, encoding="utf-8") as fh:
        text = fh.read()
    if not text.strip():
        print("ОТКАЗ: источник пуст — рендерить нечего", file=sys.stderr)
        return 1

    html = markdown.markdown(
        text,
        extensions=["tables", "fenced_code", "attr_list", "sane_lists"],
    )

    # Оглавление собирается из ГОТОВОГО html, а не из markdown: иначе заголовок,
    # который расширение не признало заголовком, попал бы в навигацию и вёл в никуда.
    seen: dict = {}
    toc = []

    def anchor(m):
        level, body = m.group(1), m.group(2)
        plain = re.sub(r"<[^>]+>", "", body)
        sid = slug(plain, seen)
        if level in ("2", "3"):
            toc.append((level, sid, plain))
        return f'<h{level} id="{sid}">{body}</h{level}>'

    html = re.sub(r"<h([1-6])>(.*?)</h\1>", anchor, html, flags=re.S)

    nav = "\n".join(
        f'<a class="h{lvl}" href="#{sid}">{txt}</a>' for lvl, sid, txt in toc
    )

    title = "Kachō — квоты и биллинг"
    m = re.search(r"<h1[^>]*>(.*?)</h1>", html, flags=re.S)
    if m:
        title = re.sub(r"<[^>]+>", "", m.group(1))

    page = (
        "<!doctype html>\n"
        "<!-- СГЕНЕРИРОВАНО ИЗ quota-and-billing-2026.md. РУКАМИ НЕ ПРАВИТЬ.\n"
        "     Перегенерация: python3 scripts/render-doc.py <вход.md> <выход.html> -->\n"
        '<html lang="ru"><head><meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width,initial-scale=1">\n'
        f"<title>{title}</title>\n<style>{CSS}</style>\n</head><body>\n"
        f'<div class="wrap"><nav>{nav}</nav><main>{html}</main></div>\n'
        "</body></html>\n"
    )

    with open(dst, "w", encoding="utf-8") as fh:
        fh.write(page)

    print(
        f"отрендерено: строк источника {len(text.splitlines())} · "
        f"пунктов навигации {len(toc)} · байт страницы {len(page)}"
    )
    if not toc:
        print("ОТКАЗ: ноль заголовков — навигация пуста", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
