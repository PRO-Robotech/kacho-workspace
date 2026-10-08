#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-11 «поле `model:` агента несёт
# значение, которое харнесс примет» — недопустимый псевдоним и пустое значение
# краснеют; законные близнецы той же формы (каждый псевдоним, полный
# идентификатор, кавычки, отсутствие поля, `model:` в теле, а не во frontmatter)
# молчат; агентов нет — отказ по предмету.
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
for _i11_fn in sandbox capture assert_code assert_says assert_fixture_changed sandbox_digest; do
    command -v "$_i11_fn" >/dev/null 2>&1 && continue
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — оснастки inject.sh нет: функция" \
         "«$_i11_fn» не определена; часть подключена не оттуда" >&2
    exit 2
done
unset -v _i11_fn

C11=check-11-agent-model-value.sh
# Перепись части: утверждений до и после неё — «часть прошла» отличимо от
# «часть ничего не утверждала».
_i11_before=$((pass + fail))
# Настоящий вход — живое определение агента из дерева, а не синтетика: правка
# ложится туда же, куда её кладёт исполнитель (ws#975 поставил поле именно сюда).
A11=".claude/agents/ci-watcher.md"

# i11_set <каталог> <строка model: целиком | ""> — заменить либо снять поле
# `model:` во frontmatter агента песочницы; без поля — вставить после `name:`.
i11_set() {
    python3 - "$1/$A11" "$2" <<'PY'
import sys
p, want = sys.argv[1], sys.argv[2]
lines = open(p, encoding="utf-8").read().split("\n")
end = lines.index("---", 1)
fm = [l for l in lines[1:end] if not l.startswith("model:")]
if want:
    at = next(i for i, l in enumerate(fm) if l.startswith("name:")) + 1
    fm.insert(at, want)
open(p, "w", encoding="utf-8").write("\n".join([lines[0]] + fm + lines[end:]))
PY
}

# ── ДЕФЕКТ: псевдоним, которого харнесс не знает ────────────────────────────
d="$(sandbox i11_bad_alias)"; b="$(sandbox_digest "$d")"
i11_set "$d" "model: haiko"
assert_fixture_changed "$d" "$b" "ДЕФЕКТ: в model: агента опечатка псевдонима"
capture "$d" "$C11"
assert_code 1 "ДЕФЕКТ: model: haiko — краснеет"
assert_says "ci-watcher.md" "ДЕФЕКТ: находка называет файл агента"
assert_says "haiko" "ДЕФЕКТ: находка называет недопустимое значение"

# ── ДЕФЕКТ: псевдоним с версией — форма, похожая на законную ────────────────
d="$(sandbox i11_alias_ver)"
i11_set "$d" "model: haiku-4.5"
capture "$d" "$C11"
assert_code 1 "ДЕФЕКТ: model: haiku-4.5 (не псевдоним и не claude-…) — краснеет"

# ── ДЕФЕКТ: поле объявлено пустым ───────────────────────────────────────────
d="$(sandbox i11_empty)"
i11_set "$d" "model:"
capture "$d" "$C11"
assert_code 1 "ДЕФЕКТ: model: без значения — краснеет"
assert_says "пустым" "ДЕФЕКТ: находка называет пустое значение причиной"

# ── ДЕФЕКТ: регистр — харнесс сверяет псевдоним как есть ────────────────────
d="$(sandbox i11_case)"
i11_set "$d" "model: Haiku"
capture "$d" "$C11"
assert_code 1 "ДЕФЕКТ: model: Haiku (не тот регистр) — краснеет"

# ── БЛИЗНЕЦЫ: каждый законный псевдоним ─────────────────────────────────────
for _i11_v in sonnet opus haiku fable inherit; do
    d="$(sandbox "i11_twin_$_i11_v")"
    i11_set "$d" "model: $_i11_v"
    capture "$d" "$C11"
    assert_code 0 "БЛИЗНЕЦ: model: $_i11_v — молчит"
done
unset -v _i11_v

# ── БЛИЗНЕЦ: полный идентификатор модели, с окном и без ─────────────────────
d="$(sandbox i11_twin_full)"
i11_set "$d" "model: claude-fable-5"
capture "$d" "$C11"
assert_code 0 "БЛИЗНЕЦ: model: claude-fable-5 (полный идентификатор) — молчит"
d="$(sandbox i11_twin_full1m)"
i11_set "$d" "model: claude-opus-5-5[1m]"
capture "$d" "$C11"
assert_code 0 "БЛИЗНЕЦ: model: claude-opus-5-5[1m] — молчит"

# ── БЛИЗНЕЦ: значение в кавычках ────────────────────────────────────────────
d="$(sandbox i11_twin_quoted)"
i11_set "$d" 'model: "haiku"'
capture "$d" "$C11"
assert_code 0 'БЛИЗНЕЦ: model: "haiku" в кавычках — молчит'

# ── БЛИЗНЕЦ: поля нет вовсе — законно ───────────────────────────────────────
d="$(sandbox i11_twin_absent)"
i11_set "$d" ""
capture "$d" "$C11"
assert_code 0 "БЛИЗНЕЦ: поля model: нет — агент берёт модель по умолчанию, молчит"

# ── БЛИЗНЕЦ: `model:` с чужим значением в ТЕЛЕ агента, а не во frontmatter ──
d="$(sandbox i11_twin_body)"; b="$(sandbox_digest "$d")"
printf '\nmodel: haiko\n' >> "$d/$A11"
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: строка model: haiko дописана в тело агента"
capture "$d" "$C11"
assert_code 0 "БЛИЗНЕЦ: model: в теле — не поле frontmatter, молчит"

# ── ОТКАЗ: агентов нет — судить не у кого ───────────────────────────────────
d="$(sandbox i11_void)"
rm -f "$d"/.claude/agents/*.md
capture "$d" "$C11"
assert_code 2 "ДЕФЕКТ: агентов нет — ОТКАЗ по предмету, не зелёный вердикт"

# ── нетронутая копия — молчит ───────────────────────────────────────────────
d="$(sandbox i11_clean)"
capture "$d" "$C11"
assert_code 0 "БЛИЗНЕЦ: нетронутая копия — молчит"

_i11_n=$((pass + fail - _i11_before))
echo "  [CENSUS] часть inject-11: утверждений о $C11 — $_i11_n"
if [ "$_i11_n" -eq 0 ]; then
    echo "  [FAIL] часть inject-11 не прогнала ни одного утверждения — это не доказательство" >&2
    fail=$((fail + 1))
fi
unset -v _i11_before _i11_n
