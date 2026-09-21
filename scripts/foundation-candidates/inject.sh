#!/usr/bin/env bash
# ИНЪЕКЦИЯ набора foundation-candidates.
#
# КЛАСС ДЕФЕКТА, А НЕ ПРЕДИКАТ. Инъекция выводится из того, ЧЕМ проверка может
# ошибиться, а не из того, что она читает. Ошибок у неё ровно две, и они не
# равноценны:
#
#   ЛОЖНО ЗАЧИСЛЕННЫЙ — предмет, который выносить НЕЛЬЗЯ, назван кандидатом.
#     Опаснее: вынос ломает направление зависимостей, а ошибка НЕОБРАТИМА —
#     опубликованный тег фундамента из базы контрольных сумм не отзывается.
#   ЛОЖНО ИСКЛЮЧЁННЫЙ — предмет, который выносить нужно, отсечён молча.
#     Дешевле, но именно им норма превращается в пожелание.
#
# ПАРЫ ОДНОФАКТНЫЕ: дефект и законный близнец отличаются РОВНО ОДНИМ фактом, и
# ожидание у них противоположное. Пара, отличающаяся двумя фактами, доказывает
# только то, что проверка на что-то реагирует.
#
# ОСИ:
#   A  ложно ЗАЧИСЛЕННЫЙ · продуктовый литерал лежит в СИБЛИНГЕ пакета
#   B  ложно ИСКЛЮЧЁННЫЙ · направление как НЕПОДВИЖНАЯ ТОЧКА
#   C  предпосылка · пустой ОБХОД обязан дать 2, а не 0
#   D  ведомость самоистекает · запись без предмета
#   E  храповик · рост числа
#   F  ложно ИСКЛЮЧЁННЫЙ · САМОИМПОРТ: внешний тестовый пакет своего предмета
#   G  ложно ИСКЛЮЧЁННЫЙ · ЦИКЛ из двух предметов
#   H  довод `keep` судится ПО СУЩЕСТВУ, а не по непустоте (две пары)
#
# F и G заведены приёмкой 2026-09-21: ось B проверяла НЕПОДВИЖНУЮ ТОЧКУ только
# нерекурсивным случаем, и обе рекурсии — самоимпорт и цикл — были не покрыты
# вовсе. На прежнем ядре (очередь строилась СНИЗУ, от пустого множества) дефекты
# F и G дают 0 кандидатов вместо ожидаемых и краснеют здесь.
#
# Деревья строятся СИНТЕТИЧЕСКИ в $TMPDIR: живое дерево инъекцией не трогается,
# и вердикт не зависит от того, что сегодня лежит в клонах.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/foundation-inject.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0

# repo <корень> — пустой клон продукта с резолвимым стволом origin/main.
repo() {
    mkdir -p "$1"
    git -C "$1" init -q
    git -C "$1" config user.email i@i; git -C "$1" config user.name i
}
seal() {
    git -C "$1" add -A
    git -C "$1" -c commit.gpgsign=false commit -qm i --allow-empty
    git -C "$1" update-ref refs/remotes/origin/main HEAD
}

# body <имя> — тело, дающее ≥5 нормализованных строк и J=1.0 между копиями.
body() {
    cat <<GO
package $1

func Probe(kind string) (string, bool) {
	switch kind {
	case "one":
		return "ones", true
	case "two":
		return "twos", true
	}
	return "", false
}
GO
}

# other <имя> — тело, НЕ близкое к `body`: J между ними 0.0, поэтому пакет,
# собранный из него, своего предмета с копиями `body` не заводит. Без этого
# «пакет ВНЕ очереди» сам попал бы в очередь, и ось мерила бы два факта.
other() {
    cat <<GO
package $1

func Width(n int) int {
	total := n * 3
	for i := 0; i < n; i++ {
		total -= i
	}
	return total
}
GO
}

# ring <каталог служб> <свой пакет> <партнёр> <служба> — половина ЦИКЛА: пакет,
# импортирующий партнёра по соседству. Две встречные половины и дают цикл.
ring() {
    local d="$1/$2"
    mkdir -p "$d"
    { printf 'package %s\n\nimport "github.com/PRO-Robotech/kacho/services/%s/internal/%s"\n\n' "$2" "$4" "$3"
      body "$2" | tail -n +2
      printf 'var _ = %s.Probe\n' "$3"; } > "$d/$2.go"
}

# build <корень> — общий каркас: три клона и обе ведомости.
build() {
    local r="$1"
    mkdir -p "$r/docs"
    for p in kacho kaname corelib; do repo "$r/project/$p"; done
    printf 'pairs: []\n' > "$r/docs/crossrepo-pairs.yaml"
}

ledger() {  # ledger <корень> <subjects> <files> <actionable> [строки решений]
    { printf 'ceiling:\n  subjects: %s\n  files: %s\n  actionable: %s\n' "$2" "$3" "$4"
      printf 'decisions:%s\n' "${5:-" []"}"; } > "$1/docs/foundation-candidates.yaml"
}

run() {  # run <корень> <проверка> → печатает код
    # Клоны берутся ТОЛЬКО из синтетического корня: живые переменные окружения
    # снимаются, иначе инъекция мерила бы настоящие стволы и молчала бы о своём
    # дефекте.
    env -u KACHO_HOME_KACHO -u KACHO_HOME_KANAME -u KACHO_HOME_CORELIB \
        DOCS_GATE_ROOT="$1" RELICENSE_BUSL_DECIDED=1 RELICENSE_AGPL_DECIDED=1 \
        python3 "$HERE/$2" >/dev/null 2>&1
    echo $?
}

expect() {  # expect <ось> <что за вход> <ожидаемый код> <полученный код>
    if [ "$3" = "$4" ]; then
        printf '  [OK]   %-3s %-46s код %s\n' "$1" "$2" "$4"; pass=$((pass + 1))
    else
        printf '  [ПРОВАЛ] %-3s %-44s ожидался %s, получен %s\n' "$1" "$2" "$3" "$4" >&2
        fail=$((fail + 1))
    fi
}

echo "── ОСЬ A · ложно ЗАЧИСЛЕННЫЙ: продуктовый литерал в СИБЛИНГЕ пакета"
echo "   Один факт: несёт ли СОСЕД по каталогу имя схемы продукта. Пофайловая"
echo "   единица зачислила бы обе стороны — она соседа не читает вовсе."
for side in defect twin; do
    r="$WORK/A-$side"; build "$r"
    for svc in alpha beta; do
        d="$r/project/kacho/services/$svc/internal/repo"; mkdir -p "$d"
        body repo > "$d/probe.go"
        # Сиблинг РАЗНЫЙ у двух служб — иначе парой становится он сам, и ось A
        # мерила бы два предмета вместо одного.
        { printf 'package repo\n\nimport "github.com/jackc/pgx/v5"\n\n'
          printf 'type Store struct{ p *pgx.Conn }\n'
          [ "$side" = defect ] && printf 'const schema = "kacho_registry"\n'
          printf 'func (s *Store) Ping%s() bool { return s.p != nil }\n' "$svc"
          printf 'func (s *Store) Name%s() string { return "%s" }\n' "$svc" "$svc"
          printf 'func (s *Store) Kind%s() int { return len("%s") }\n' "$svc" "$svc"
          printf 'func (s *Store) Bit%s() bool { return s.Kind%s() > 0 }\n' "$svc" "$svc"
        } > "$d/store.go"
    done
    seal "$r/project/kacho"; for p in kaname corelib; do seal "$r/project/$p"; done
    if [ "$side" = defect ]; then
        # ДЕФЕКТ: литерал схемы у соседа → выносить нельзя → кандидатов 0,
        # ведомость пуста, храповик сходится.
        ledger "$r" 1 2 0
        expect A "дефект: схема PG у соседа — НЕ кандидат" 0 "$(run "$r" check-01-every-candidate-carries-a-decision.py)"
        expect A "дефект: храповик знает actionable=0" 0 "$(run "$r" check-02-second-home-count-does-not-grow.py)"
    else
        # БЛИЗНЕЦ: тот же пакет без литерала → кандидат → решения нет → находка.
        ledger "$r" 1 2 1
        expect A "близнец: соседа без литерала — КАНДИДАТ" 1 "$(run "$r" check-01-every-candidate-carries-a-decision.py)"
    fi
done

echo "── ОСЬ B · ложно ИСКЛЮЧЁННЫЙ: направление как НЕПОДВИЖНАЯ ТОЧКА"
echo "   Один факт: стоит ли ИМПОРТИРУЕМЫЙ пакет сам в очереди выноса."
for side in defect twin; do
    r="$WORK/B-$side"; build "$r"
    for svc in alpha beta; do
        d="$r/project/kacho/services/$svc/internal/lane"; mkdir -p "$d"
        { printf 'package lane\n\nimport "github.com/PRO-Robotech/kacho/pkg/refusal"\n\n'
          body lane | tail -n +2; printf 'var _ = refusal.Lane\n'; } > "$d/lane.go"
    done
    d="$r/project/kacho/pkg/refusal"; mkdir -p "$d"; body refusal > "$d/lane.go"
    if [ "$side" = defect ]; then
        # ДЕФЕКТ: у `pkg/refusal` ЕСТЬ вторая прописка (копия в kaname), значит
        # он сам в очереди — импорт его НЕ отсекает, обе копии lane — кандидат.
        d="$r/project/kaname/internal/shared"; mkdir -p "$d"; body shared > "$d/refusal.go"
    fi
    for p in kacho kaname corelib; do seal "$r/project/$p"; done
    if [ "$side" = defect ]; then
        ledger "$r" 2 4 2
        expect B "дефект: импортируемое само в очереди — КАНДИДАТ" 1 "$(run "$r" check-01-every-candidate-carries-a-decision.py)"
    else
        ledger "$r" 1 2 0
        expect B "близнец: импортируемое вне очереди — отсечён" 0 "$(run "$r" check-01-every-candidate-carries-a-decision.py)"
        expect B "близнец: храповик знает actionable=0" 0 "$(run "$r" check-02-second-home-count-does-not-grow.py)"
    fi
done

echo "── ОСЬ C · ПРЕДПОСЫЛКА: падать обязан пустой ОБХОД, а не пустой ПЕРЕЧЕНЬ"
echo "   Первая редакция роняла гейт на пустом перечне кандидатов — то есть"
echo "   на ЦЕЛИ; пустой обход при этом не судился ничем."
r="$WORK/C-defect"; build "$r"; for p in kacho kaname corelib; do seal "$r/project/$p"; done
ledger "$r" 0 0 0
expect C "дефект: обход пуст (0 файлов) — код 2" 2 "$(run "$r" check-01-every-candidate-carries-a-decision.py)"
expect C "дефект: обход пуст — храповик тоже 2" 2 "$(run "$r" check-02-second-home-count-does-not-grow.py)"
expect C "дефект: обход пуст — измеритель тоже 2" 2 "$(run "$r" list-candidates.py)"
r="$WORK/C-twin"; build "$r"
for svc in alpha beta; do
    d="$r/project/kacho/services/$svc/internal/lane"; mkdir -p "$d"; body lane > "$d/lane.go"
done
for p in kacho kaname corelib; do seal "$r/project/$p"; done
ledger "$r" 1 2 1 '
  - package: kacho:services/alpha/internal/lane
    decision: keep
    why: "синтетика инъекции"
    class: 2-политика
    evidence: kacho:services/alpha/internal/lane/lane.go'
expect C "близнец: обход НЕ пуст, перечень пуст — код 0" 0 "$(run "$r" check-02-second-home-count-does-not-grow.py)"

echo "── ОСЬ D · ВЕДОМОСТЬ САМОИСТЕКАЕТ: запись, которой нечего решать"
echo "   Один факт: есть ли у названного пакета вторая прописка в стволах."
r="$WORK/D-defect"; build "$r"
for svc in alpha beta; do
    d="$r/project/kacho/services/$svc/internal/lane"; mkdir -p "$d"; body lane > "$d/lane.go"
done
for p in kacho kaname corelib; do seal "$r/project/$p"; done
ledger "$r" 1 2 1 '
  - package: kacho:services/alpha/internal/lane
    decision: keep
    why: "синтетика инъекции"
    class: 2-политика
    evidence: kacho:services/alpha/internal/lane/lane.go
  - package: kacho:services/gamma/internal/gone
    decision: move
    issue: "#1"'
expect D "дефект: запись без предмета — находка" 1 "$(run "$r" check-01-every-candidate-carries-a-decision.py)"
r="$WORK/D-twin"; build "$r"
for svc in alpha beta; do
    d="$r/project/kacho/services/$svc/internal/lane"; mkdir -p "$d"; body lane > "$d/lane.go"
done
for p in kacho kaname corelib; do seal "$r/project/$p"; done
ledger "$r" 1 2 1 '
  - package: kacho:services/alpha/internal/lane
    decision: keep
    why: "синтетика инъекции"
    class: 2-политика
    evidence: kacho:services/alpha/internal/lane/lane.go'
expect D "близнец: у записи предмет есть — молчит" 0 "$(run "$r" check-01-every-candidate-carries-a-decision.py)"

echo "── ОСЬ E · ХРАПОВИК: рост числа копий"
echo "   Один факт: третья служба с той же копией. Счёт ПРЕДМЕТОВ от неё не"
echo "   меняется — меняется счёт ФАЙЛОВ, и ровно ради этого события заведено"
echo "   второе число."
for side in defect twin; do
    r="$WORK/E-$side"; build "$r"
    svcs="alpha beta"; [ "$side" = defect ] && svcs="alpha beta gamma"
    for svc in $svcs; do
        d="$r/project/kacho/services/$svc/internal/lane"; mkdir -p "$d"; body lane > "$d/lane.go"
    done
    for p in kacho kaname corelib; do seal "$r/project/$p"; done
    ledger "$r" 1 2 1
    if [ "$side" = defect ]; then
        expect E "дефект: ТРЕТЬЯ прописка при files=2 — находка" 1 "$(run "$r" check-02-second-home-count-does-not-grow.py)"
    else
        expect E "близнец: две прописки при files=2 — молчит" 0 "$(run "$r" check-02-second-home-count-does-not-grow.py)"
    fi
done

echo "── ОСЬ F · САМОИМПОРТ: внешний тестовый пакет своего же предмета"
echo "   Один факт: КУДА показывает импорт соседнего тестового файла — на СВОЙ"
echo "   ЖЕ пакет или на пакет ВНЕ очереди. Полярность в факт не входит."
echo "   На очереди, строящейся СНИЗУ, дефект отсекался в первом круге и в"
echo "   очередь не попадал никогда: попасть в неё можно только пережив отсев,"
echo "   а пережить отсев — только уже стоя в ней."
for side in defect twin; do
    r="$WORK/F-$side"; build "$r"
    # Пакет ВНЕ очереди: одна прописка, значит предметом он не является.
    d="$r/project/kacho/pkg/outside"; mkdir -p "$d"; other outside > "$d/outside.go"
    for svc in alpha beta; do
        d="$r/project/kacho/services/$svc/internal/lane"; mkdir -p "$d"
        body lane > "$d/lane.go"
        # Сосед короче MIN_LINES — в сравнение он не попадает и своего предмета
        # не заводит, но импорты КАТАЛОГА пополняет (единица отсева — пакет).
        if [ "$side" = defect ]; then
            printf 'package lane_test\n\nimport _ "github.com/PRO-Robotech/kacho/services/%s/internal/lane"\n' "$svc" > "$d/probe_test.go"
        else
            printf 'package lane_test\n\nimport _ "github.com/PRO-Robotech/kacho/pkg/outside"\n' > "$d/probe_test.go"
        fi
    done
    for p in kacho kaname corelib; do seal "$r/project/$p"; done
    if [ "$side" = defect ]; then
        # Самоимпорт направления не ограничивает: судья едет вместе с предметом,
        # и ссылка после выноса указывает на новый адрес ТОГО ЖЕ пакета.
        ledger "$r" 1 2 1
        expect F "дефект: сосед импортирует СВОЙ предмет — КАНДИДАТ" 1 "$(run "$r" check-01-every-candidate-carries-a-decision.py)"
        expect F "дефект: храповик видит actionable=1" 0 "$(run "$r" check-02-second-home-count-does-not-grow.py)"
    else
        ledger "$r" 1 2 0
        expect F "близнец: сосед импортирует ВНЕ очереди — отсечён" 0 "$(run "$r" check-01-every-candidate-carries-a-decision.py)"
        expect F "близнец: храповик видит actionable=0" 0 "$(run "$r" check-02-second-home-count-does-not-grow.py)"
    fi
done

echo "── ОСЬ G · ЦИКЛ из двух предметов, импортирующих друг друга"
echo "   Один факт: есть ли ВТОРАЯ ПРОПИСКА у партнёра по импорту. Есть — цикл,"
echo "   ребро после выноса внутреннее, уезжают оба одним изменением; нет —"
echo "   импорт указывает ВНЕ очереди и отсекает по существу."
echo "   Снизу цикл недостижим: в первом круге отсекаются ОБА, очередь пуста и"
echo "   больше не меняется."
for side in defect twin; do
    r="$WORK/G-$side"; build "$r"
    for svc in alpha beta; do
        ring "$r/project/kacho/services/$svc/internal" one two "$svc"
        ring "$r/project/kacho/services/$svc/internal" two one "$svc"
    done
    # ЕДИНСТВЕННЫЙ различающийся факт: у близнеца второй копии `two` нет, и
    # предметом он не становится. Исходники при этом побайтово те же.
    [ "$side" = twin ] && rm -rf "$r/project/kacho/services/beta/internal/two"
    for p in kacho kaname corelib; do seal "$r/project/$p"; done
    if [ "$side" = defect ]; then
        ledger "$r" 2 4 2
        expect G "дефект: цикл двух предметов — ОБА кандидаты" 1 "$(run "$r" check-01-every-candidate-carries-a-decision.py)"
        expect G "дефект: храповик видит actionable=2" 0 "$(run "$r" check-02-second-home-count-does-not-grow.py)"
    else
        ledger "$r" 1 2 0
        expect G "близнец: партнёр без второй прописки — отсечён" 0 "$(run "$r" check-01-every-candidate-carries-a-decision.py)"
        expect G "близнец: храповик видит actionable=0" 0 "$(run "$r" check-02-second-home-count-does-not-grow.py)"
    fi
done

echo "── ОСЬ H · ДОВОД keep СУДИТСЯ ПО СУЩЕСТВУ, а не по непустоте"
echo "   Фраза why на ВСЕХ ЧЕТЫРЁХ сторонах одна и та же — та самая, которую"
echo "   норма называет запретной. Это и есть предмет оси: прежняя редакция"
echo "   судила НЕПУСТОТУ и зеленела на ней. Текст на вердикт больше не влияет"
echo "   вовсе — красное и зелёное приходят от машинного факта."
lane_pair() {  # lane_pair <корень> — пара копий, дающая ровно одного кандидата
    for svc in alpha beta; do
        d="$1/project/kacho/services/$svc/internal/lane"; mkdir -p "$d"
        body lane > "$d/lane.go"
    done
    for p in kacho kaname corelib; do seal "$1/project/$p"; done
}
echo "   H1 · один факт: резолвится ли координата довода в файл ЭТОГО пакета."
for side in defect twin; do
    r="$WORK/H1-$side"; build "$r"; lane_pair "$r"
    ev="kacho:services/alpha/internal/lane/lane.go"
    [ "$side" = defect ] && ev="kacho:services/alpha/internal/lane/nothing.go"
    ledger "$r" 1 2 1 "
  - package: kacho:services/alpha/internal/lane
    decision: keep
    why: \"по усмотрению\"
    class: 2-политика
    evidence: $ev"
    if [ "$side" = defect ]; then
        expect H1 "дефект: координата не резолвится — находка" 1 "$(run "$r" check-01-every-candidate-carries-a-decision.py)"
    else
        expect H1 "близнец: координата в файле предмета — молчит" 0 "$(run "$r" check-01-every-candidate-carries-a-decision.py)"
    fi
done
echo "   H2 · один факт: назван ли класс из ЗАКРЫТОГО словаря восьми."
for side in defect twin; do
    r="$WORK/H2-$side"; build "$r"; lane_pair "$r"
    cls="2-политика"
    [ "$side" = defect ] && cls="9-если-оправдано"
    ledger "$r" 1 2 1 "
  - package: kacho:services/alpha/internal/lane
    decision: keep
    why: \"по усмотрению\"
    class: $cls
    evidence: kacho:services/alpha/internal/lane/lane.go"
    if [ "$side" = defect ]; then
        expect H2 "дефект: девятый класс вне словаря — находка" 1 "$(run "$r" check-01-every-candidate-carries-a-decision.py)"
    else
        expect H2 "близнец: класс из восьми — молчит" 0 "$(run "$r" check-01-every-candidate-carries-a-decision.py)"
    fi
done

echo
echo "inject foundation-candidates: сошлось $pass, разошлось $fail"
[ "$fail" -eq 0 ] || exit 1
[ "$pass" -gt 0 ] || { echo "инъекция не исполнила ни одной пары" >&2; exit 1; }
exit 0
