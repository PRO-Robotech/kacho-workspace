#!/usr/bin/env bash
# Доказательство class-guard ИНЪЕКЦИЕЙ, в обе стороны — по каждому предикату.
#
# Запрет чего-то стоит, только если проверен с двух сторон:
#   (+) верни дефект  → гейт КРАСНЕЕТ и НАЗЫВАЕТ координату;
#   (−) поставь рядом ЗАКОННУЮ конструкцию той же формы → гейт МОЛЧИТ.
# Без (−) гейт ловит форму, а не существо, и первый же ложный срабат его отключит.
#
# Вход обеих сторон — НАСТОЯЩИЕ фрагменты дерева (см. столбец «близнец» в README),
# а не выдуманные строки: выдуманный вход доказывает только то, что регулярное
# выражение совпадает само с собой.
#
# Запуск: bash .claude/hooks/class-guard/prove.sh    (код 0 — все пары сошлись)
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/class-guard.sh"
# Корень воркспейса: prove.sh лежит в .claude/hooks/class-guard/, то есть на ТРИ
# уровня ниже. Первая редакция поднималась на два и указывала в `.claude` — все пять
# проб по дереву честно отчитались «НЕ ВЫПОЛНИЛОСЬ», а не зазеленели на несуществующем
# входе; третья категория для того и заведена.
WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# Живое дерево продукта. В воркспейсе оно лежит под project/kacho; в самом репозитории
# продукта — куда оснастка раскатывается и откуда её тоже запускают — корень репозитория
# И ЕСТЬ дерево. Пришитый `project/kacho` делал пять проб по живому дереву невыполнимыми
# ровно там, где они нужнее всего: в standalone-клоне (проверено исполнением — 5 из 65
# проб не выполнялись). Признак выбирается по наличию предмета, а не по имени каталога.
if [ -d "$WS/project/kacho/services" ]; then
  TREE="$WS/project/kacho"
elif [ -d "$WS/services" ]; then
  TREE="$WS"                      # оснастка раскатана в сам репозиторий продукта
else
  TREE="$WS/project/kacho"        # предмета нет — пробы честно отчитаются «НЕ ВЫПОЛНИЛОСЬ»
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0; CASES=0; NOTRUN=0

run() { # run <tool> <path> → stderr гейта
  printf '{"tool_name":"%s","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "$2" "$TMP" \
    | bash "$HOOK" 2>&1 || true
}

# Третья категория исхода — «не выполнилось» — НЕ вычитается из вердикта и не
# засчитывается ни в одну из двух других. Первая редакция этого харнесса читала
# упавший гейт как «дефект прошёл», то есть сливала сломанный инструмент с
# отрицательным ответом — ровно тот класс, который сам гейт и ловит.
broken() { grep -q "CLASS-GUARD СЛОМАН" <<<"$1"; }

expect_fires() { # expect_fires <класс> <tool> <path> <подпись>
  CASES=$((CASES+1))
  local out; out="$(run "$2" "$3")"
  if broken "$out"; then
    echo "  ⨯ (+) $1 $4 — ГЕЙТ СЛОМАН, проба не выполнилась"; FAIL=$((FAIL+1)); return
  fi
  if grep -q "\[$1\]" <<<"$out"; then
    if grep -qE "где: .*:[0-9]+" <<<"$out"; then
      echo "  ✔ (+) $1 $4 — краснеет и называет координату"; PASS=$((PASS+1))
    else
      echo "  ✘ (+) $1 $4 — сработал, но БЕЗ координаты"; FAIL=$((FAIL+1))
    fi
  else
    echo "  ✘ (+) $1 $4 — НЕ сработал (дефект прошёл)"; FAIL=$((FAIL+1))
  fi
}

expect_silent() { # expect_silent <класс> <tool> <path> <подпись>
  CASES=$((CASES+1))
  local out; out="$(run "$2" "$3")"
  if broken "$out"; then
    echo "  ⨯ (−) $1 $4 — ГЕЙТ СЛОМАН, проба не выполнилась"; FAIL=$((FAIL+1)); return
  fi
  if grep -q "\[$1\]" <<<"$out"; then
    echo "  ✘ (−) $1 $4 — ЛОЖНОЕ срабатывание на законной конструкции"; FAIL=$((FAIL+1))
  else
    echo "  ✔ (−) $1 $4 — молчит"; PASS=$((PASS+1))
  fi
}

w() { mkdir -p "$(dirname "$TMP/$1")"; cat > "$TMP/$1"; echo "$TMP/$1"; }

echo "== A. Go (разбор дерева) =="

P=$(w a1.go <<'EOF'
package p

import "context"

type Principal struct{ ID string }

func SystemPrincipal() Principal { return Principal{ID: "system"} }

// (+) единственный результат — «не было личности» выразить нечем
func PrincipalFromContext(ctx context.Context) Principal {
	if v, ok := ctx.Value(1).(Principal); ok {
		return v
	}
	return SystemPrincipal()
}
EOF
); expect_fires A1 Write "$P" "личность одним результатом"

P=$(w a1n.go <<'EOF'
package p

import (
	"context"
	"log/slog"
)

type Principal struct{ ID string }

// (−) близнец 1: признак присутствия есть
func PrincipalFromContextOK(ctx context.Context) (Principal, bool) {
	v, ok := ctx.Value(1).(Principal)
	return v, ok
}

// (−) близнец 2: один результат, но НЕ личность
func LoggerFromCtx(ctx context.Context) *slog.Logger { return slog.Default() }
EOF
); expect_silent A1 Write "$P" "пара (Principal,bool) и логгер"

P=$(w a2.go <<'EOF'
package p

type lim struct{}

func (l *lim) Allow(k string) bool { return true }
func (l *lim) Spend(k string, n int) {}

func handle(l *lim, k string) {
	// (+) спросили и списали раздельно
	if l.Allow(k) {
		l.Spend(k, 1)
	}
}
EOF
); expect_fires A2 Write "$P" "Allow → Spend на одном ресивере"

P=$(w a2n.go <<'EOF'
package p

import "errors"

type lim struct{}

func (l *lim) Allow(k string) bool { return true }

// (−) идиома x/time/rate: Allow списывает САМ
func handle(l *lim, k string) error {
	if !l.Allow(k) {
		return errors.New("limit")
	}
	return nil
}
EOF
); expect_silent A2 Write "$P" "Allow, списывающий сам"

P=$(w a3.go <<'EOF'
package p

type req struct{}

func (r *req) GetPageSize() int64 { return 0 }

var corevalidate struct{ PageSize func(int32) error }

func h(r *req) error { return corevalidate.PageSize(int32(r.GetPageSize())) } // (+)
EOF
); expect_fires A3 Write "$P" "сужение выше валидатора"

P=$(w a3n.go <<'EOF'
package p

type req struct{}

func (r *req) GetPageSize() int32 { return 0 }

var corevalidate struct{ PageSize func(int32) error }

func h(r *req) error { return corevalidate.PageSize(r.GetPageSize()) } // (−) голый геттер
EOF
); expect_silent A3 Write "$P" "валидатор видит исходную ширину"

P=$(w a4.go <<'EOF'
package p

import "slices"

// (+) сужение работает, только пока список непуст
func trusted(allowed []string, san string) bool {
	if len(allowed) > 0 && !slices.Contains(allowed, san) {
		return false
	}
	return true
}
EOF
); expect_fires A4 Write "$P" "пустой список пропускает всех"

P=$(w a4n.go <<'EOF'
package p

import "slices"

// (−) близнец 1: безусловная ветка «список пуст → отказ»
func trusted(allowed []string, san string) bool {
	if len(allowed) == 0 {
		return false
	}
	if len(allowed) > 0 && !slices.Contains(allowed, san) {
		return false
	}
	return true
}

// (−) близнец 2 (живой, gateway/internal/config/config.go): чтение последнего
// элемента, а не членство
func normalise(iss string) string {
	if len(iss) > 0 && iss[len(iss)-1] == '/' {
		return iss[:len(iss)-1]
	}
	return iss
}

// (−) близнец 3 (живой, gateway/internal/middleware/request_id.go): чтение первого
func first(vals []string) string {
	if len(vals) > 0 && vals[0] != "" {
		return vals[0]
	}
	return ""
}
EOF
); expect_silent A4 Write "$P" "закрытая ветка и безопасное индексирование"

P=$(w a5.go <<'EOF'
package p

import (
	"errors"
	"strings"
)

func validate(sans string) error {
	if len(strings.Split(sans, ",")) == 0 { // (+) провабельно мёртвый guard
		return errors.New("empty")
	}
	return nil
}
EOF
); expect_fires A5 Write "$P" "len(strings.Split(...)) == 0"

P=$(w a5n.go <<'EOF'
package p

import (
	"errors"
	"strings"
)

func splitNonEmpty(s, sep string) []string {
	var out []string
	for _, p := range strings.Split(s, sep) {
		if strings.TrimSpace(p) != "" {
			out = append(out, p)
		}
	}
	return out
}

func validate(sans string) error {
	if len(splitNonEmpty(sans, ",")) == 0 { // (−) считает то, что примет транспорт
		return errors.New("empty")
	}
	if len(strings.Fields(sans)) == 0 { // (−) Fields ДАЁТ пустой срез — сравнение живое
		return errors.New("empty")
	}
	return nil
}
EOF
); expect_silent A5 Write "$P" "splitNonEmpty и strings.Fields"

P=$(w a6.go <<'EOF'
package p

func isTransient(code int) bool {
	switch code {
	case 400, 403:
		return false
	}
	return true // (+) корзина «прочее» в разрешающую сторону
}
EOF
); expect_fires A6 Write "$P" "терминальный return true"

P=$(w a6n.go <<'EOF'
package p

func isTransient(code int) bool {
	switch code {
	case 503, 504:
		return true
	}
	return false // (−) fail-closed направление
}
EOF
); expect_silent A6 Write "$P" "терминальный return false"

P=$(w a7.go <<'EOF'
package p

import (
	"context"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type c struct{ maxRetries int }
type stub interface{ Check(context.Context) error }

func (x *c) call(ctx context.Context, s stub) error {
	var last error
	for attempt := 0; attempt <= x.maxRetries; attempt++ { // (+) раундов нет ожидания
		err := s.Check(ctx)
		if err == nil {
			return nil
		}
		last = err
		if status.Code(err) == codes.Unavailable {
			continue
		}
		return err
	}
	return last
}
EOF
); expect_fires A7 Write "$P" "раунды к чужому без ожидания"

P=$(w a7n.go <<'EOF'
package p

import (
	"context"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type c struct {
	maxRetries int
	sleep      func(time.Duration)
	backoff    time.Duration
}
type stub interface{ Check(context.Context) error }

// (−) близнец 1 (живой, gateway/internal/clients/iam_subject_client.go):
// инъектируемый sleeper полем структуры
func (x *c) call(ctx context.Context, s stub) error {
	for attempt := 0; attempt < x.maxRetries; attempt++ {
		x.sleep(x.backoff)
		if err := s.Check(ctx); err == nil {
			return nil
		} else if status.Code(err) != codes.Unavailable {
			return err
		}
	}
	return nil
}

// (−) близнец 2 (живой, services/vpc/…/address/alloc_shared.go): пересчёт СВОЕЙ
// строки под конкуренцией — ждать нечего, слот уже занят соседом
func alloc(attempts int, try func() error, isConflict func(error) bool) error {
	for attempt := 0; attempt < attempts; attempt++ {
		if err := try(); err != nil {
			if isConflict(err) {
				continue
			}
			return err
		}
		return nil
	}
	return nil
}
EOF
); expect_silent A7 Write "$P" "инъектируемый sleeper и конкуренция за свой слот"

P=$(w a8.go <<'EOF'
package p

import "context"

type item struct{ ID string }
type authz interface {
	Check(ctx context.Context, id string) (bool, error)
}
type uc struct{ authz authz }

func (u *uc) ListThings(ctx context.Context, items []item) []item {
	var out []item
	for _, it := range items { // (+) вопрос на КАЖДУЮ строку
		if ok, _ := u.authz.Check(ctx, it.ID); ok {
			out = append(out, it)
		}
	}
	return out
}
EOF
); expect_fires A8 Write "$P" "per-object Check внутри листания"

P=$(w a8n.go <<'EOF'
package p

import "context"

type item struct{ ID string }
type authz interface {
	Check(ctx context.Context, id string) (bool, error)
	BatchCheck(ctx context.Context, ids []string) (map[string]bool, error)
}
type uc struct{ authz authz }

// (−) близнец 1: партийный вопрос по идентификаторам страницы
func (u *uc) ListThings(ctx context.Context, items []item) []item {
	ids := make([]string, 0, len(items))
	for _, it := range items {
		ids = append(ids, it.ID)
	}
	allowed, _ := u.authz.BatchCheck(ctx, ids)
	var out []item
	for _, it := range items {
		if allowed[it.ID] {
			out = append(out, it)
		}
	}
	return out
}

// (−) близнец 2 (живой, services/iam/internal/authzguard/scope.go): цикл по трём
// ОТНОШЕНИЯМ, а не по странице объектов — страницы здесь нет вовсе
func (u *uc) authorize(ctx context.Context, rels []string, object string) bool {
	for _, rel := range rels {
		if ok, _ := u.authz.Check(ctx, rel+"@"+object); ok {
			return true
		}
	}
	return false
}
EOF
); expect_silent A8 Write "$P" "партийный вопрос и цикл по отношениям"

P=$(w a9.go <<'EOF'
package p

import "crypto/tls"

func cfg() *tls.Config { return &tls.Config{InsecureSkipVerify: true} } // (+)
EOF
); expect_fires A9 Write "$P" "InsecureSkipVerify: true"

P=$(w a9n_test.go <<'EOF'
package p

import (
	"crypto/tls"
	"testing"
)

// (−) тот же литерал в in-process фикстуре — здесь он законен
func TestX(t *testing.T) { _ = &tls.Config{InsecureSkipVerify: true} }
EOF
); expect_silent A9 Write "$P" "тот же литерал в _test.go"

P=$(w a10.go <<'EOF'
package p

// TODO: добавить authz на этот путь
func h() {} // (+)
EOF
); expect_fires A10 Write "$P" "маркер первым токеном комментария"

P=$(w a10n.go <<'EOF'
package p

// Этот гейт читает ТОЛЬКО комментарии Go, и его предмет — процессный шум:
// идентификаторы трекера, маркеры фаз, TODO. Слово названо, дела не отложено.
const marker = "TODO" // (−) строковый литерал, не позиция комментария

func h() { _ = marker }
EOF
); expect_silent A10 Write "$P" "проза о маркере и строковый литерал"

P=$(w a11.go <<'EOF'
package p

import "context"

type thing struct{ ID string }
type fakeRepo struct{ items []thing }

// (+) объявленный параметр контракта не читается ни разу
func (f *fakeRepo) List(ctx context.Context, pageToken string, pageSize int32) ([]thing, error) {
	return f.items, nil
}
EOF
); expect_fires A11 Write "$P" "дублёр не смотрит на pageToken"

P=$(w a11n.go <<'EOF'
package p

import (
	"context"
	"errors"
)

type thing struct{ ID string }
type fakeRepo struct{ items []thing }

// (−) дублёр отвечает контрактным отказом ровно как продукт
func (f *fakeRepo) List(ctx context.Context, pageToken string, pageSize int32) ([]thing, error) {
	if pageToken != "" && pageToken != "valid" {
		return nil, errors.New("invalid page token")
	}
	if pageSize < 0 || pageSize > 1000 {
		return nil, errors.New("invalid page size")
	}
	return f.items, nil
}
EOF
); expect_silent A11 Write "$P" "дублёр отвергает негодный курсор"

echo "== B. shell / Makefile =="

P=$(w b1.sh <<'SH'
#!/usr/bin/env bash
go test ./... | tee out.log
echo GREEN
exit 0
SH
); expect_fires B1 Write "$P" "вердикт через конвейер без pipefail"

P=$(w b1n.sh <<'SH'
#!/usr/bin/env bash
set -o pipefail
go test ./... | tee out.log
exit "${PIPESTATUS[0]}"
SH
); expect_silent B1 Write "$P" "pipefail + PIPESTATUS"

P=$(w b2.sh <<'SH'
#!/usr/bin/env bash
go test ./... || true
SH
); expect_fires B2 Write "$P" "|| true на команде-вердикте"

P=$(w b2n.sh <<'SH'
#!/usr/bin/env bash
rm -f /tmp/scratch || true
go test ./...
SH
); expect_silent B2 Write "$P" "|| true на уборке"

P=$(w b3.sh <<'SH'
#!/usr/bin/env bash
set -o pipefail
go test ./... | tail -50
SH
); expect_fires B3 Write "$P" "tail на выводе прогона"

P=$(w b3n.sh <<'SH'
#!/usr/bin/env bash
set -o pipefail
go test ./... > o.log 2>&1
grep -E '^--- FAIL|^FAIL' o.log
SH
); expect_silent B3 Write "$P" "греп по содержанию в файл"

P=$(w gate-b4.sh <<'SH'
#!/usr/bin/env bash
for f in *.go; do
  probe "$f"
done
echo OK
exit 0
SH
); expect_fires B4 Write "$P" "перечисление без переписи"

P=$(w gate-b4n.sh <<'SH'
#!/usr/bin/env bash
count=0
for f in $(git ls-files '*.go'); do
  probe "$f"; count=$((count+1))
done
[ "$count" -gt 0 ] || { echo "нечего проверять — предпосылка не резолвится"; exit 2; }
echo "OK: рассмотрено $count"
SH
); expect_silent B4 Write "$P" "счётчик рассмотренного и отказ на пустом"

# ── B5: обе стороны — ДОСЛОВНЫЕ фрагменты дерева ──────────────────────────────
#
# Прежняя пара была разошедшейся с реальностью: отрицательный близнец читал ТОЛЬКО
# адрес движка и `current-context` не звал вовсе, тогда как весь живой код зовёт ОБА —
# имя первым отсевом ради внятного совета оператору, адрес для решения. Фикстуре не
# хватало сопутствующего элемента, который у настоящих данных есть, поэтому предикат
# был доказан на входе, какого в дереве не бывает, и советовал снять ВЕРНУЮ проверку
# в четырёх местах из шести.
#
# Теперь (+) — дословный `deploy/scripts/remeasure-provider-listener-tls.sh` (авторитета
# нет), (−) — дословный `deploy/scripts/inject-admin-hop-defects.sh` (имя И адрес).
P=$(w b5.sh <<'SH'
#!/usr/bin/env bash
command -v kubectl >/dev/null 2>&1 || { echo "FATAL: нужен kubectl"; exit 2; }
ctx="$(kubectl config current-context 2>/dev/null)"
[ "$ctx" = kind-kacho ] || { echo "ABORT: контекст '$ctx' — не kind-kacho"; exit 2; }
SH
); expect_fires B5 Write "$P" "kacho@5af959db remeasure-provider-listener-tls.sh — только имя"

P=$(w b5n.sh <<'SH'
#!/usr/bin/env bash
# ── ЦЕЛЬ ПИНИТСЯ ПО КЛАСТЕРУ, А НЕ ПО ИМЕНИ КОНТЕКСТА ───────────────────────
ctx="$(kubectl config current-context 2>/dev/null)"
[ "$ctx" = kind-kacho ] || invalid "активный контекст '$ctx' — не kind-kacho"
want_srv="$(kind get kubeconfig --name kacho 2>/dev/null | sed -n 's/^ *server: *//p' | head -1)"
have_srv="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)"
[ -n "$want_srv" ] || invalid "kind не знает кластера 'kacho' — сверить apiserver НЕ С ЧЕМ"
[ "$want_srv" = "$have_srv" ] || invalid "контекст называется kind-kacho, но ведёт в другой кластер"
SH
); expect_silent B5 Write "$P" "kacho@5af959db inject-admin-hop-defects.sh — имя И адрес"

P=$(w b6.sh <<'SH'
#!/usr/bin/env bash
test "$(kubectl get cm kacho-storage -o jsonpath='{.data.AUTH_MODE}')" = production
SH
); expect_fires B6 Write "$P" "посадка из ConfigMap"

P=$(w b6n.sh <<'SH'
#!/usr/bin/env bash
kubectl logs deploy/kacho-storage | grep -q 'auth_mode=production'
psql -tAc "select ssl from pg_stat_ssl" | grep -q t
SH
); expect_silent B6 Write "$P" "лог процесса и pg_stat_ssl"

P=$(w check-b7.sh <<'SH'
#!/usr/bin/env bash
for f in $(find . -name '*.go'); do probe "$f"; done
SH
); expect_fires B7 Write "$P" "состав дерева с диска"

P=$(w check-b7n.sh <<'SH'
#!/usr/bin/env bash
for f in $(git ls-files '*.go'); do probe "$f"; done
recent=$(find "$PROJ" -name '*.go' -mmin -60 | wc -l)
SH
); expect_silent B7 Write "$P" "git ls-files и find по времени правки"

P=$(w check-b8.sh <<'SH'
#!/usr/bin/env bash
grep -q 'authzIntr.Unary()' --include='*.go' -r . || fail
SH
); expect_fires B8 Write "$P" "греп кодового токена по *.go"

P=$(w check-b8n.sh <<'SH'
#!/usr/bin/env bash
go run ./tools/authzgate ./... || fail
grep -rn 'yandex' --include='*.md' docs/ && fail
SH
); expect_silent B8 Write "$P" "разбор инструментом; греп вне кода"

P=$(w b9.sh <<'SH'
#!/usr/bin/env bash
until ! pgrep -f "newman run"; do sleep 5; done
SH
); expect_fires B9 Write "$P" "ожидание по шаблону процесса"

P=$(w b9n.sh <<'SH'
#!/usr/bin/env bash
newman run x.json & PID=$!
while kill -0 "$PID" 2>/dev/null; do sleep 5; done
SH
); expect_silent B9 Write "$P" "ожидание по захваченному PID"

P=$(w b10.sh <<'SH'
#!/usr/bin/env bash
cd project/kacho && make build && cd ../..
SH
); expect_fires B10 Write "$P" "уход и возврат в одной цепочке"

P=$(w b10n.sh <<'SH'
#!/usr/bin/env bash
(cd project/kacho && make build)
make -C project/kacho build
SH
); expect_silent B10 Write "$P" "подоболочка и make -C"

P=$(w b11.sh <<'SH'
#!/usr/bin/env bash
git commit -m "fix: `foo` больше не ломается"
SH
); expect_fires B11 Write "$P" "обратные кавычки в -m"

P=$(w b11n.sh <<'SH'
#!/usr/bin/env bash
git commit -F - <<'MSG'
fix: `foo` больше не ломается
MSG
SH
); expect_silent B11 Write "$P" "heredoc вместо -m"

P=$(w b12.sh <<'SH'
#!/usr/bin/env bash
git stash
make build
git stash pop
SH
); expect_fires B12 Write "$P" "снятие без охраны"

P=$(w b12n.sh <<'SH'
#!/usr/bin/env bash
S=0
if ! git diff --quiet; then git stash push -m work; S=1; fi
make build
[ "$S" = 1 ] && git stash pop
SH
); expect_silent B12 Write "$P" "снятие только когда есть что снимать"

P=$(w b13.sh <<'SH'
#!/usr/bin/env bash
seed_env
git add -A
git commit -m "seed"
SH
); expect_fires B13 Write "$P" "коммит всего дерева из посева"

P=$(w b13n.sh <<'SH'
#!/usr/bin/env bash
seed_env
git add tests/newman/env/a.json tests/newman/env/b.json
git commit -m "seed"
SH
); expect_silent B13 Write "$P" "названные пути"

P=$(w b14.sh <<'SH'
#!/usr/bin/env bash
sleep 300
check_ready
SH
); expect_fires B14 Write "$P" "фиксированное ожидание 300s"

P=$(w b14n.sh <<'SH'
#!/usr/bin/env bash
for i in $(seq 1 60); do check_ready && break; sleep 5; done
SH
); expect_silent B14 Write "$P" "ожидание предиката"

P=$(w check-b15.sh <<'SH'
#!/usr/bin/env bash
go test -short ./... || exit 1
SH
); expect_fires B15 Write "$P" "-short в гейте"

P=$(w dev-helper.sh <<'SH'
#!/usr/bin/env bash
go test -short ./internal/...
SH
); expect_silent B15 Write "$P" "-short в локальном ускорителе"

echo "== C. newman =="

P=$(w c1.py <<'PY'
POLL = [
    "const j = pm.response.json();",
    "if (!j.done) { pm.execution.setNextRequest(pm.info.requestName); return; }",
]
PY
); expect_fires C1 Write "$P" "опрос без занятого ожидания"

P=$(w c1n.py <<'PY'
POLL_OK = [
    "const j = pm.response.json();",
    "if (!j.done) {",
    "  const _x = Date.now(); while (Date.now() - _x < 400) void 0;",
    "  pm.execution.setNextRequest(pm.info.requestName); return;",
    "}",
]
# (−) близнец 2 (живой, iam-authz-grant-check-propagation): курсорный обход —
# следующий раунд идёт с новым токеном, прогресс гарантирован, ждать нечего
PAGE = [
    "if (rows.length === 0 && j.nextPageToken && _pg < 25) {",
    "  pm.environment.set('tok', j.nextPageToken);",
    "  pm.execution.setNextRequest(pm.info.requestName); return;",
    "}",
]
# (−) близнец 3: константа-иголка генератора, не исполняемый код
_SELF_RETRY_CALL = "pm.execution.setNextRequest(pm.info.requestName)"
PY
); expect_silent C1 Write "$P" "занятое ожидание, курсор, иголка"

echo "== D. YAML =="

P=$(w d1.yaml <<'YML'
spec:
  env: first
  env: second
YML
); expect_fires D1 Write "$P" "дубль ключа в одном маппинге"

P=$(w d1n.yaml <<'YML'
spec:
  containers:
    - name: a
      env: first
    - name: b
      env: second
YML
); expect_silent D1 Write "$P" "тот же ключ в разных элементах списка"

P=$(w d2.yaml <<'YML'
image: kacho-vpc:latest
YML
); expect_fires D2 Write "$P" "движущийся тег"

P=$(w d2n.yaml <<'YML'
image: kacho-vpc:1.4.2
other: kacho-iam@sha256:0123456789abcdef
YML
); expect_silent D2 Write "$P" "прибитая версия и digest"

echo "== E. markdown =="

P=$(w e1.md <<'MD'
Подробности — security.md:120.
MD
); expect_fires E1 Write "$P" "ссылка на норму номером строки"

P=$(w e1n.md <<'MD'
Подробности — security.md §«Hardening-инварианты» п.8.
Координата дефекта: services/nlb/internal/apps/kacho/api/target/add_targets.go:214.

```sh
echo "security.md:120"
```
MD
); expect_silent E1 Write "$P" "имя раздела, координата кода, пример в блоке"

echo "== F. TypeScript =="

P=$(w f1.ts <<'TS'
export async function load() {
  await fetchPolicy().catch(() => {});
}
TS
); expect_fires F1 Write "$P" "отказ проглочен целиком"

P=$(w f1n.ts <<'TS'
export async function load() {
  await fetchPolicy().catch((e) => {
    report(e);
    throw e;
  });
  // .catch(() => {}) здесь только в комментарии — защиты это не снимает
}
TS
); expect_silent F1 Write "$P" "отказ доложен и переброшен; форма в комментарии"

echo "== G. событие инструмента =="

P=$(w migrations/0007_x.sql <<'SQL'
-- +goose Up
ALTER TABLE t ADD COLUMN c text;
SQL
); expect_fires G1 Edit "$P" "Edit по применённой миграции"
# Прежняя редакция звала пробу по НЕСУЩЕСТВУЮЩЕМУ пути (файл создавался строкой ниже),
# и гейт выходил на `os.path.exists` — то есть проба ничего не проверяла и всё равно
# засчитывалась в «сошлось». «Не выполнилось», зачтённое за «прошло», — ровно тот класс,
# который этот харнесс объявляет третьей категорией.
cp "$TMP/migrations/0007_x.sql" "$TMP/migrations/0012_y.sql"
expect_silent G1 Write "$TMP/migrations/0012_y.sql" "Write новой миграции"

# ══ Живое дерево: спрашивается СВОЙСТВО стража, а не расклад чужого дерева ══
#
# Синтетическая пара доказывает, что предикат различает две конструкции. Она НЕ
# доказывает, что страж читает НАСТОЯЩИЕ файлы продукта, — ради этого раздел и
# существует. Но закреплять за каждым файлом ОБЪЯВЛЕННЫЙ исход нельзя: так проба
# пиннит СОСТОЯНИЕ чужого дерева, а состояние меняется теми, кто про эту пробу не
# знает. 2026-08-11 продукт ПОЧИНИЛ один из двух названных здесь дефектов — рядом с
# именем контекста появилась сверка адреса apiserver'а, — и проба отчиталась «страж
# не отверг того, ради чего написан». Починка соседа читалась как поломка стража:
# ствол воркспейса простоял красным пять прогонов, и ни один PR в это время не был
# судим.
#
# Спрашивается теперь СВОЙСТВО, выводимое из дерева на каждом прогоне:
#   • кандидаты B5 НАХОДЯТСЯ, а не перечисляются (форма + перепись самого стража);
#   • молчание кандидата обязано быть ОБЪЯСНЕНО: авторитет в файле есть, и снятие
#     авторитета из копии — инъекция в НАСТОЯЩИЙ файл — обязано покраснеть;
#   • срабатывание кандидата обязано НАЗЫВАТЬ координату.
# Свойство переживает и починку дефекта, и появление нового: починенный файл просто
# переходит в другую полосу и продолжает проверяться с той стороны.
#
# Сама форма-триггер берётся ИЗ РЕАЛИЗАЦИИ (`text_predicates.B5_TRIGGER`), а не
# выписывается сюда: выписанный литерал был бы вторым кодеком, разошёлся бы с первым
# молча — и разошёлся бы там, где расхождение не видно (обе стороны отвечают
# «кандидатов нет»).
B5_TRIGGER="$(python3 - "$WS/.claude/hooks/class-guard" <<'PY'
import sys

sys.path.insert(0, sys.argv[1])
import text_predicates as tp  # noqa: E402

print(tp.B5_TRIGGER)
PY
)"

b5_trigger_files() { # b5_trigger_files <корень> → пути (от корня) с формой B5
  local root="$1"
  [ -d "$root" ] || return 0
  [ -n "$B5_TRIGGER" ] || return 0
  if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$root" grep -l -- "$B5_TRIGGER" 2>/dev/null | sort
  else
    (cd "$root" && grep -rl --exclude-dir=.git -- "$B5_TRIGGER" . 2>/dev/null \
      | sed 's|^\./||' | sort)
  fi
}

# Авторитет снимается ТОЙ ЖЕ регуляркой, которой его ищет предикат: списывать её
# сюда значило бы завести второй кодек, который разойдётся с первым молча — и
# разойдётся ровно там, где расхождение не видно (обе стороны отвечают «снято»).
b5_strip_authority() { # b5_strip_authority <исходник> <назначение> → сколько строк снято
  python3 - "$WS/.claude/hooks/class-guard" "$1" "$2" <<'PY'
import pathlib
import sys

sys.path.insert(0, sys.argv[1])
import text_predicates as tp  # noqa: E402

src, dst = pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
kept, removed = [], 0
for line in src.read_text(encoding="utf-8", errors="replace").splitlines():
    if tp._CLUSTER_IDENTITY.search(line):
        removed += 1
    else:
        kept.append(line)
dst.write_text("\n".join(kept) + "\n", encoding="utf-8")
print(removed)
PY
}

# Раздел вынесен в функцию РАДИ ИНЪЕКЦИИ В ОБЕ СТОРОНЫ: его же прогоняют по корню,
# где предмета нет, и требуют оттуда «НЕ ВЫПОЛНИЛОСЬ», а не тишины. Иначе раздел,
# потерявший вход, отчитывался бы нулём находок неотличимо от нуля прочитанного.
# Печатает машинные строки `PASS|FAIL|NOTRUN|CENSUS <текст>`; счётчики ведёт вызывающий.
b5_live_tree() { # b5_live_tree <корень> <каталог под копии>
  local root="$1" work="$2" rel out inj removed seen=0 cand=0 silent=0 fires=0 i=0
  # Предпосылка раздела проверяется самим разделом: без формы-триггера из реализации
  # он нашёл бы ноль кандидатов и был бы неотличим от чистого дерева.
  if [ -z "$B5_TRIGGER" ]; then
    echo "NOTRUN B5: форма-триггер не извлеклась из text_predicates.B5_TRIGGER — искать нечем"
    echo "CENSUS осмотрено файлов 0, кандидатов B5 0, молчат как есть 0, краснеют как есть 0"
    return
  fi
  local files; files="$(b5_trigger_files "$root")"
  if [ -z "$files" ]; then
    echo "NOTRUN B5 по живому дереву: в '$root' нет ни одного файла с формой B5 — читать нечего"
    echo "CENSUS осмотрено файлов 0, кандидатов B5 0, молчат как есть 0, краснеют как есть 0"
    return
  fi
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    seen=$((seen + 1))
    out="$(run Write "$root/$rel")"
    if broken "$out"; then
      echo "NOTRUN B5 $rel: ГЕЙТ СЛОМАН на настоящем файле"
      continue
    fi
    # Кандидат — по переписи САМОГО стража, а не по нашему грепу: форма может лежать
    # в комментарии или теле heredoc, которые предикат не читает by construction.
    grep -qE 'B5:[0-9]+' <<<"$out" || continue
    cand=$((cand + 1))
    i=$((i + 1))
    mkdir -p "$work/$i"
    # ИМЯ файла сохраняется: роль (Makefile / .sh) читается по нему, и копия под
    # другим именем ушла бы мимо предикатов — проба зазеленела бы вхолостую.
    inj="$work/$i/$(basename "$rel")"
    removed="$(b5_strip_authority "$root/$rel" "$inj")"
    if grep -q "\[B5\]" <<<"$out"; then
      fires=$((fires + 1))
      if grep -qE "где: .*:[0-9]+" <<<"$out"; then
        echo "PASS (+) B5 $rel — краснеет на живом файле и называет координату"
      else
        echo "FAIL (+) B5 $rel — сработал на живом файле, но БЕЗ координаты"
      fi
      continue
    fi
    silent=$((silent + 1))
    if [ "${removed:-0}" -gt 0 ]; then
      echo "PASS (−) B5 $rel — молчит, и молчание объяснено: авторитетных строк $removed"
    else
      echo "FAIL (−) B5 $rel — молчит, а авторитета в файле НЕТ: молчание ничем не объяснено"
    fi
    out="$(run Write "$inj")"
    if broken "$out"; then
      echo "NOTRUN B5 $rel: ГЕЙТ СЛОМАН на копии без авторитета"
    elif grep -q "\[B5\]" <<<"$out" && grep -qE "где: .*:[0-9]+" <<<"$out"; then
      echo "PASS (+) B5 $rel без авторитета — инъекция в НАСТОЯЩИЙ файл краснеет и называет координату"
    else
      echo "FAIL (+) B5 $rel без авторитета — инъекция в НАСТОЯЩИЙ файл НЕ сработала"
    fi
  done <<< "$files"
  [ "$cand" -gt 0 ] || echo "NOTRUN B5: страж не признал кандидатом ни один файл формы — предмета нет"
  [ "$silent" -gt 0 ] || echo "NOTRUN B5: в дереве не осталось ни одного законного близнеца — сторона (−) без предмета"
  echo "CENSUS осмотрено файлов $seen, кандидатов B5 $cand, молчат как есть $silent, краснеют как есть $fires"
}

echo "== живое дерево (kacho): свойство стража, а не расклад дерева =="
mkdir -p "$TMP/b5-live" "$TMP/b5-void"
B5_LIVE="$(b5_live_tree "$TREE" "$TMP/b5-live")"
while IFS= read -r line; do
  case "$line" in
    PASS\ *)   PASS=$((PASS + 1));   CASES=$((CASES + 1)); echo "  ✔ ${line#PASS }" ;;
    FAIL\ *)   FAIL=$((FAIL + 1));   CASES=$((CASES + 1)); echo "  ✘ ${line#FAIL }" ;;
    NOTRUN\ *) NOTRUN=$((NOTRUN + 1));                     echo "  ⋯ НЕ ВЫПОЛНИЛОСЬ: ${line#NOTRUN }" ;;
    CENSUS\ *)                                             echo "  ⊞ перепись: ${line#CENSUS }" ;;
  esac
done <<< "$B5_LIVE"

# Инъекция в сам раздел, в обе стороны: корень без предмета обязан дать «НЕ
# ВЫПОЛНИЛОСЬ» и НИ ОДНОГО «сошлось», живой корень — наоборот. Без этой пары раздел,
# оставшийся без входа, молчал бы неотличимо от раздела, у которого всё сошлось.
B5_VOID="$(b5_live_tree "$TMP/b5-void" "$TMP/b5-void")"
CASES=$((CASES + 1))
if grep -q '^NOTRUN ' <<<"$B5_VOID" && ! grep -q '^PASS ' <<<"$B5_VOID"; then
  echo "  ✔ раздел без предмета отчитывается «НЕ ВЫПОЛНИЛОСЬ», а не тишиной"; PASS=$((PASS + 1))
else
  echo "  ✘ раздел без предмета неотличим от раздела, где всё сошлось"; FAIL=$((FAIL + 1))
fi
CASES=$((CASES + 1))
if grep -q '^PASS ' <<<"$B5_LIVE" && ! grep -q '^NOTRUN ' <<<"$B5_LIVE"; then
  echo "  ✔ на живом дереве тот же раздел даёт сошедшиеся пробы и ни одного «не выполнилось»"; PASS=$((PASS + 1))
else
  echo "  ✘ на живом дереве раздел не дал ни одной сошедшейся пробы либо потерял вход"; FAIL=$((FAIL + 1))
fi

# ══ Знаменатель переписи выведен из реализации, а не записан рукой ══
#
# Проверяется НЕ равенство двум литералам (это бы просто перенесло рукопись сюда), а
# совпадение множеств: идентификаторы классов, которые реализация действительно
# эмитит, против того, что объявляет `PREDICATES_BY_ROLE`.
echo "== самоописание =="
CASES=$((CASES+1))
if out="$(cd "$WS" && python3 - <<'PY' 2>&1
import re, sys
from pathlib import Path
H = Path(".claude/hooks/class-guard")
sys.path.insert(0, str(H))
import guard
go, py, gp = (H/"goast"/"main.go").read_text(), (H/"text_predicates.py").read_text(), (H/"guard.py").read_text()
impl = (set(re.findall(r'Class:\s*"([A-G]\d+)"', go)) | set(re.findall(r'note\("([A-G]\d+)"\)', go))
        | set(re.findall(r'Finding\(\s*\n?\s*"([A-G]\d+)"', py)) | set(re.findall(r'note\("([A-G]\d+)"\)', py))
        | set(re.findall(r'tp\.Finding\(\s*\n?\s*"([A-G]\d+)"', gp)))
if not impl:
    print("ПУСТО: из исходников не извлечён НИ ОДИН идентификатор класса — предпосылка гейта не резолвится")
    sys.exit(1)
diff = impl ^ set(guard.ALL_CLASSES)
print(f"классов в реализации {len(impl)}, объявлено {guard.TOTAL_PREDICATES}, расхождение {sorted(diff) or 'нет'}")
sys.exit(1 if diff else 0)
PY
)"; then
  echo "  ✔ знаменатель выведен из реализации — $out"; PASS=$((PASS+1))
else
  echo "  ✘ знаменатель разошёлся с реализацией — $out"; FAIL=$((FAIL+1))
fi

echo
echo "══ проб: $CASES · сошлось: $PASS · разошлось: $FAIL · НЕ ВЫПОЛНИЛОСЬ: $NOTRUN ══"
# «Не выполнилось» не вычитается из первых двух и не вычитается из вердикта: проба,
# которой не дали входа, ничего не доказала. Она названа числом отдельно.
[ "$FAIL" -eq 0 ] || exit 1
[ "$NOTRUN" -eq 0 ] || { echo "  (часть проб осталась без входа — вердикт неполон)"; exit 3; }
