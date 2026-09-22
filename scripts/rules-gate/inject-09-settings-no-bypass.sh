#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-09 «отслеживаемые настройки не несут
# обхода подтверждений» по трём осям — блок `permissions` вернулся, обход назван
# где угодно в файле, локальные настройки не игнорируются — плюс отказ по
# отсутствию предмета и законные близнецы той же формы.
#
# Файл ПОДКЛЮЧАЕТСЯ (`.`) из `inject.sh` и пользуется его оснасткой.

# ── СТРАЖ ПОДКЛЮЧЕНИЯ ────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — ЧАСТЬ инъекции, а не самостоятельная проба." >&2
    echo "       Она подключается из scripts/rules-gate/inject.sh и пользуется его оснасткой;" >&2
    echo "       самостоятельно писала бы в рабочее дерево. Запускать:" >&2
    echo "       bash scripts/rules-gate/inject.sh" >&2
    exit 2
fi
for _i09_fn in sandbox capture assert_code assert_fixture_changed sandbox_digest; do
    command -v "$_i09_fn" >/dev/null 2>&1 && continue
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — оснастки inject.sh нет: функция" \
         "«$_i09_fn» не определена; часть подключена не оттуда" >&2
    exit 2
done
unset -v _i09_fn

C9=check-09-settings-no-bypass.sh
S=".claude/settings.json"
L=".claude/settings.local.json"

# i09_put <каталог> <ключ> <json-значение> — добавить ключ в настройки песочницы.
i09_put() {
    python3 - "$1/$S" "$2" "$3" <<'PY'
import collections, json, sys
p, key, val = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(p), object_pairs_hook=collections.OrderedDict)
d[key] = json.loads(val)
open(p, 'w', encoding='utf-8').write(json.dumps(d, ensure_ascii=False, indent=2) + '\n')
PY
}

# ── ось A: блок permissions вернулся в отслеживаемые настройки ────────────────
d="$(sandbox i09_perm)"
i09_put "$d" permissions '{"defaultMode": "bypassPermissions"}'
capture "$d" "$C9"
assert_code 1 "ДЕФЕКТ: блок permissions в отслеживаемых настройках — краснеет"

# ── ось B: обход назван ВНЕ своего блока ─────────────────────────────────────
# Предмет — не имя ключа, а наличие обхода в файле, который уедет в клон.
d="$(sandbox i09_word)"
i09_put "$d" statusLine '"echo defaultMode: bypassPermissions"'
capture "$d" "$C9"
assert_code 1 "ДЕФЕКТ: bypassPermissions назван в стороннем ключе — краснеет"

# ── ось C: локальные настройки существуют и НЕ игнорируются ──────────────────
d="$(sandbox i09_local)"; b="$(sandbox_digest "$d")"
printf '{\n  "permissions": {\n    "defaultMode": "bypassPermissions"\n  }\n}\n' > "$d/$L"
if [ -f "$d/.gitignore" ]; then
    grep -v 'settings\.local\.json' "$d/.gitignore" > "$d/.gitignore.new" && mv "$d/.gitignore.new" "$d/.gitignore"
fi
assert_fixture_changed "$d" "$b" "ДЕФЕКТ: локальные настройки есть, строка игнора снята"
capture "$d" "$C9"
assert_code 1 "ДЕФЕКТ: локальные настройки не игнорируются — краснеет"

# ── ось D: атрибуция харнесса — каждое поле одним фактом ─────────────────────
d="$(sandbox i09_attr_gone)"
python3 - "$d/$S" <<'PY'
import collections, json, sys
p = sys.argv[1]
d = json.load(open(p), object_pairs_hook=collections.OrderedDict)
d.pop('attribution', None)
open(p, 'w', encoding='utf-8').write(json.dumps(d, ensure_ascii=False, indent=2) + '\n')
PY
capture "$d" "$C9"
assert_code 1 "ДЕФЕКТ: ключ attribution снят — харнесс ставит атрибуцию по умолчанию — краснеет"

d="$(sandbox i09_attr_commit)"
i09_put "$d" attribution '{"commit": "Co-Authored-By: X", "pr": "", "sessionUrl": false}'
capture "$d" "$C9"
assert_code 1 "ДЕФЕКТ: attribution.commit непуст — краснеет"

d="$(sandbox i09_attr_session)"
i09_put "$d" attribution '{"commit": "", "pr": "", "sessionUrl": true}'
capture "$d" "$C9"
assert_code 1 "ДЕФЕКТ: attribution.sessionUrl = true — краснеет"

d="$(sandbox i09_attr_legacy)"
i09_put "$d" includeCoAuthoredBy 'true'
capture "$d" "$C9"
assert_code 1 "ДЕФЕКТ: устаревший includeCoAuthoredBy = true — краснеет"

# БЛИЗНЕЦ оси D: та же выключенная атрибуция другой записью — порядок полей иной.
d="$(sandbox i09_attr_twin)"; b="$(sandbox_digest "$d")"
i09_put "$d" attribution '{"sessionUrl": false, "pr": "", "commit": ""}'
i09_put "$d" includeCoAuthoredBy 'false'
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: атрибуция выключена, поля в другом порядке, устаревший ключ false"
capture "$d" "$C9"
assert_code 0 "БЛИЗНЕЦ: атрибуция выключена другой записью — молчит"

# ── ось VOID: предмета нет — ОТКАЗ, а не «находок 0» ────────────────────────
d="$(sandbox i09_void)"
rm -f "$d/$S"
capture "$d" "$C9"
assert_code 2 "ДЕФЕКТ: настроек нет — ОТКАЗ по предмету, не зелёный вердикт"

# ── БЛИЗНЕЦ оси A/B: настройки ПРАВЛЕНЫ, но мимо предмета ───────────────────
d="$(sandbox i09_twin_key)"; b="$(sandbox_digest "$d")"
i09_put "$d" cleanupPeriodDays '30'
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: в настройки добавлен посторонний ключ"
capture "$d" "$C9"
assert_code 0 "БЛИЗНЕЦ: правка настроек мимо обхода — молчит"

# ── БЛИЗНЕЦ оси C: те же локальные настройки, но игнор НА МЕСТЕ ──────────────
d="$(sandbox i09_twin_local)"; b="$(sandbox_digest "$d")"
printf '{\n  "permissions": {\n    "defaultMode": "bypassPermissions"\n  }\n}\n' > "$d/$L"
grep -q 'settings\.local\.json' "$d/.gitignore" 2>/dev/null \
    || printf '%s\n' ".claude/settings.local.json" >> "$d/.gitignore"
git -C "$d" add -A > /dev/null 2>&1 || true
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: те же локальные настройки, строка игнора на месте"
capture "$d" "$C9"
assert_code 0 "БЛИЗНЕЦ: обход живёт в игнорируемом файле — молчит"

# ── ось Z: нетронутая копия — молчит ────────────────────────────────────────
d="$(sandbox i09_clean)"
capture "$d" "$C9"
assert_code 0 "БЛИЗНЕЦ: нетронутая копия — молчит"
