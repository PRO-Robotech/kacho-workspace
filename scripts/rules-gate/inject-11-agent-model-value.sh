#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-11 «`model:` агента — только
# псевдоним из перечня нормы, лёгкая модель — только у ci-watcher» — опечатка
# псевдонима, ЛЮБОЙ полный идентификатор (в том числе с опечаткой в семействе),
# пустое значение, `model:x` без пробела, `haiku` у другого агента и снятое поле
# у ci-watcher краснеют; законные близнецы (каждый псевдоним, с окном [1m] и в
# любом регистре, кавычки, блочный скаляр, `model:` в теле) молчат; агентов нет —
# отказ по предмету.
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
assert_code 1 "ДЕФЕКТ: model: haiku-4.5 (не псевдоним и не claude-<семейство>-<версия>) — краснеет"

# ── ДЕФЕКТ: поле объявлено пустым ───────────────────────────────────────────
d="$(sandbox i11_empty)"
i11_set "$d" "model:"
capture "$d" "$C11"
assert_code 1 "ДЕФЕКТ: model: без значения — краснеет"
assert_says "пустым" "ДЕФЕКТ: находка называет пустое значение причиной"

# ── ДЕФЕКТЫ: полный идентификатор — запрещён нормой в любой форме; первые три —
#    опечатка в семействе, которую распознаватель формы id пропускал два круга.
for _i11_v in claude-haikuu-4-5 claude-sonet-4-5 claude-opsu-4-5 claude-haiko \
              claude-haiku-4-5 claude-haiku-4-5-20251001 us.anthropic.claude-haiku-4-5 \
              claude-mythos-5 claude-3-5-haiku; do
    d="$(sandbox "i11_badid_${_i11_v//[^a-zA-Z0-9]/_}")"
    i11_set "$d" "model: $_i11_v"
    capture "$d" "$C11"
    assert_code 1 "ДЕФЕКТ: model: $_i11_v — полный идентификатор, краснеет"
    assert_says "$_i11_v" "ДЕФЕКТ: находка называет значение $_i11_v"
done
unset -v _i11_v

# ── ДЕФЕКТ (D2): лёгкая модель снята у ci-watcher — норма объявлена, не исполняется
d="$(sandbox i11_light_removed)"; b="$(sandbox_digest "$d")"
i11_set "$d" ""
assert_fixture_changed "$d" "$b" "ДЕФЕКТ: у ci-watcher снято поле model:"
capture "$d" "$C11"
assert_code 1 "ДЕФЕКТ: у ci-watcher нет model: haiku — краснеет"
assert_says "ci-watcher" "ДЕФЕКТ: находка называет агента"

d="$(sandbox i11_light_other)"
i11_set "$d" "model: sonnet"
capture "$d" "$C11"
assert_code 1 "ДЕФЕКТ: у ci-watcher model: sonnet вместо лёгкой — краснеет"

# ── ДЕФЕКТ (D2): лёгкая модель у агента вне перечня владельца ───────────────
d="$(sandbox i11_light_stranger)"; b="$(sandbox_digest "$d")"
sed -i '0,/^name:/s//model: haiku\nname:/' "$d/.claude/agents/git-operator.md"
assert_fixture_changed "$d" "$b" "ДЕФЕКТ: git-operator получил model: haiku"
capture "$d" "$C11"
assert_code 1 "ДЕФЕКТ: model: haiku у git-operator — краснеет"
assert_says "git-operator" "ДЕФЕКТ: находка называет агента вне перечня"

# ── БЛИЗНЕЦ: тяжёлая модель у агента вне перечня — законно ──────────────────
d="$(sandbox i11_twin_heavy_other)"
sed -i '0,/^name:/s//model: Opus\nname:/' "$d/.claude/agents/git-operator.md"
capture "$d" "$C11"
assert_code 0 "БЛИЗНЕЦ: model: Opus у git-operator — молчит"

# ── ДЕФЕКТ: `default` — слово выбора модели, но не псевдоним агента ─────────
d="$(sandbox i11_default)"
i11_set "$d" "model: default"
capture "$d" "$C11"
assert_code 1 "ДЕФЕКТ: model: default (резолвер агента отдаёт строку как есть) — краснеет"

# ── ДЕФЕКТ: нет пробела после двоеточия — это не поле YAML ──────────────────
d="$(sandbox i11_nospace)"
i11_set "$d" "model:haiku"
capture "$d" "$C11"
assert_code 1 "ДЕФЕКТ: model:haiku без пробела — краснеет"
assert_says "нет пробела" "ДЕФЕКТ: находка называет отсутствие пробела причиной"

# ── БЛИЗНЕЦЫ: каждый псевдоним перечня, с окном [1m] и в другом регистре ────
#    (у ci-watcher — лёгкая; прочие псевдонимы ставятся git-operator'у).
for _i11_v in haiku 'haiku[1m]' Haiku 'HAIKU[1M]'; do
    d="$(sandbox "i11_twin_${_i11_v//[^a-zA-Z0-9]/_}")"
    i11_set "$d" "model: $_i11_v"
    capture "$d" "$C11"
    assert_code 0 "БЛИЗНЕЦ: model: $_i11_v у ci-watcher — молчит"
done
for _i11_v in sonnet opus fable best opusplan inherit \
              'sonnet[1m]' 'opus[1m]' 'fable[1m]' OPUS Inherit; do
    d="$(sandbox "i11_twin_go_${_i11_v//[^a-zA-Z0-9]/_}")"
    sed -i "0,/^name:/s//model: $_i11_v\nname:/" "$d/.claude/agents/git-operator.md"
    capture "$d" "$C11"
    assert_code 0 "БЛИЗНЕЦ: model: $_i11_v у git-operator — молчит"
done
unset -v _i11_v

# ── БЛИЗНЕЦЫ: блочный скаляр — значение в строке продолжения ────────────────
for _i11_v in '>-' '|' '>'; do
    d="$(sandbox "i11_twin_block_${_i11_v//[^a-zA-Z0-9]/_}x")"
    i11_set "$d" "model: $_i11_v
  haiku"
    capture "$d" "$C11"
    assert_code 0 "БЛИЗНЕЦ: model: $_i11_v + строка «haiku» — молчит"
done
unset -v _i11_v
d="$(sandbox i11_block_typo)"
i11_set "$d" "model: >-
  haiko"
capture "$d" "$C11"
assert_code 1 "ДЕФЕКТ: model: >- + «haiko» — опечатка в блочном скаляре краснеет"
assert_says "haiko" "ДЕФЕКТ: находка называет значение из строки продолжения"

# ── БЛИЗНЕЦ: значение в кавычках ────────────────────────────────────────────
d="$(sandbox i11_twin_quoted)"
i11_set "$d" 'model: "haiku"'
capture "$d" "$C11"
assert_code 0 'БЛИЗНЕЦ: model: "haiku" в кавычках — молчит'

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

# ── нетронутая копия — молчит (у 31 агента вне перечня лёгкой модели поля ──
#    model: нет: отсутствие поля законно) ───────────────────────────────────────────────
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
