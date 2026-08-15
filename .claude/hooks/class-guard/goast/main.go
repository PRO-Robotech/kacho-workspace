// Command goast — предикаты класса A (Go) для class-guard.
//
// Почему разбор дерева, а не текст: замер по kacho@5af959db показал, что текстовый
// предикат на TODO дал бы 25 ложных из 25 (в проде 0, в `_test.go`+`.md` — 25), а
// первая выборка текстового предиката по newman дала 3 комментария из 5 попаданий.
// Предикат, не различающий код, литерал и комментарий, «подтверждает» класс, которого
// в коде нет. Поэтому по Go — только go/ast.
//
// Контракт с вызывающим (guard.py):
//   вход  — пути файлов аргументами;
//   выход — JSONL на stdout, по одному объекту в строке:
//             {"kind":"finding", ...}    — находка
//             {"kind":"census",  ...}    — перепись осмотренного (ВСЕГДА, даже при нуле находок)
//             {"kind":"unparsed", ...}   — файл не разобрался (НЕ молчаливый пропуск)
//   код   — 0 всегда, кроме собственной поломки (тогда 3 + текст на stderr).
//
// «Ноль находок» и «ноль прочитанного» различает census: он несёт число разобранных
// файлов, объявлений и комментариев. Гейт без переписи неотличим от гейта, который
// ничего не читал.
package main

import (
	"encoding/json"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"regexp"
	"strings"
)

// ---------------------------------------------------------------------------
// Выходные записи
// ---------------------------------------------------------------------------

type finding struct {
	Kind    string `json:"kind"`
	Class   string `json:"class"`   // A1…A11
	Title   string `json:"title"`   // имя класса
	File    string `json:"file"`    // путь как передан
	Line    int    `json:"line"`    // координата
	Col     int    `json:"col"`     //
	Symbol  string `json:"symbol"`  // что именно найдено
	Why     string `json:"why"`     // почему это дефект
	Fix     string `json:"fix"`     // противоядие
	Section string `json:"section"` // раздел скила ПО ИМЕНИ, не по номеру строки
}

type census struct {
	Kind       string         `json:"kind"`
	Files      int            `json:"files"`
	Parsed     int            `json:"parsed"`
	TestFiles  int            `json:"test_files"` // выведены из корпуса «прод-дерево» — объявленная предпосылка A1…A3, A6…A10
	Decls      int            `json:"decls"`
	Comments   int            `json:"comments"`
	Nodes      int            `json:"nodes"`
	Predicates int            `json:"predicates"`
	Disabled   []string       `json:"disabled"`   // предикаты, у которых не резолвится предпосылка
	Considered map[string]int `json:"considered"` // кандидатов ФОРМЫ дошло до различителя
	Fired      map[string]int `json:"fired"`      // из них признано дефектом
}

// considered/fired — почему это отдельные числа, а не одно.
//
// «Ноль находок» и «ноль прочитанного» неотличимы, пока гейт не назовёт, СКОЛЬКО
// кандидатов своей формы он рассмотрел и скольких оправдал. Пример из этого же
// дерева: A4 (пустой список = «не сужаем») даёт 0 находок на kacho@5af959db — но
// 18 выражений формы `len(X) > 0 && …` рассмотрены и оправданы как безопасное
// индексирование. Первое число доказывает, что корпус читается; второе — что класс
// в дереве закрыт. Без первого второе не факт.
var (
	considered = map[string]int{}
	fired      = map[string]int{}
)

func note(class string) { considered[class]++ }

type unparsed struct {
	Kind string `json:"kind"`
	File string `json:"file"`
	Err  string `json:"err"`
}

var out = json.NewEncoder(os.Stdout)

func emit(v any) { _ = out.Encode(v) }

func emitFinding(f finding) { f.Kind = "finding"; fired[f.Class]++; emit(f) }

// ---------------------------------------------------------------------------
// Конфигурация предикатов, чья предпосылка — словарь имён.
//
// gate-authoring §«Гейт заявляет предпосылку и объём осмотренного»: запрет, стоящий
// на факте о дереве, обязан этот факт объявить. Ниже — все словари, на которых
// держатся предикаты. Пустой словарь означает, что предикат ВЫКЛЮЧЕН, и census
// сообщает об этом явно (иначе выключенный предикат неотличим от молчащего).
// ---------------------------------------------------------------------------

var (
	// A1 — типы, представляющие личность вызывающего.
	identityTypes = map[string]bool{
		"Principal": true, "Identity": true, "Actor": true,
		"Subject": true, "Caller": true, "Tenant": true,
	}
	// A2 — «спросить» и «списать» на общем in-process ресурсе.
	askRe   = regexp.MustCompile(`^(Allow|Check|Has[A-Z_]?\w*|Available|Permit)$`)
	spendRe = regexp.MustCompile(`^(Spend|Take|Consume|Charge|Reserve|Add|Inc|Incr|Increment)$`)
	// A3 — валидаторы страницы.
	pageValidators = map[string]bool{"PageSize": true, "ValidatePagination": true}
	narrowingConv  = map[string]bool{
		"int": true, "int8": true, "int16": true, "int32": true, "int64": true,
		"uint": true, "uint8": true, "uint16": true, "uint32": true, "uint64": true,
		"max": true, "min": true,
	}
	// A6 — имена классификаторов чужого отказа.
	classifierRe = regexp.MustCompile(`(?i)(retry|retri|transient|temporary|temp\b|recoverab)`)
	// A7 — имя границы цикла, объявляющее его циклом повторов.
	retryBoundRe = regexp.MustCompile(`(?i)(retr|attempt|round|redeliver)`)
	// A8 — имена одиночной проверки прав. ПУСТОЙ СПИСОК ВЫКЛЮЧАЕТ ПРЕДИКАТ.
	perObjectCheck = map[string]bool{
		"Check": true, "Allowed": true, "Authorize": true, "IsAllowed": true, "Can": true,
	}
	// A9 — послабления, снимающие проверку.
	bypassIdent = regexp.MustCompile(`(?i)^(trust_?any|allow_?any|skip_?verify|disable_?auth|bypass_?auth|insecure_?any)$`)
	// A10 — отложенная находка. Маркер обязан стоять ПЕРВЫМ токеном комментария:
	// так пишут отложенное дело («// TODO: добавить authz»). Слово TODO в середине
	// фразы — это проза О маркере, а не маркер. Отрицательный близнец в дереве
	// существует: tools/foreignclouds/foreignclouds.go перечисляет TODO как токен,
	// который ищет ДРУГОЙ гейт. Предикат, не различающий эти два, повторил бы ровно
	// тот дефект, который ловит (testing.md §«Гейт на класс» п.4).
	todoRe = regexp.MustCompile(`^\s*(?:/[/*]+|\*)?\s*(TODO|FIXME|XXX)\b`)
	// A11 — дублёр и его параметры, обязанные быть прочитанными.
	doubleRecvRe = regexp.MustCompile(`(?i)(fake|mock|stub|noop|dummy|spy)`)
	contractArgs = map[string]bool{
		"pageToken": true, "pageSize": true, "filter": true,
		"cursor": true, "token": true, "orderBy": true, "limit": true,
	}
	// A7 — признаки ожидания внутри раунда. Регистронезависимо СОЗНАТЕЛЬНО:
	// инъектируемый sleeper живёт полем структуры со строчной буквы (`c.sleep(...)`),
	// и первая редакция этого предиката его не увидела — дала ложную находку на
	// gateway/internal/clients/iam_subject_client.go, где ожидание есть.
	waitCall = regexp.MustCompile(`(?i)^(sleep|after|tick|newtimer|newticker|wait|waitcontext|backoff|pause|delay)$`)
	// A7 — признак того, что раунд повторяет обращение к ЧУЖОМУ, а не пересчитывает
	// своё под конкуренцией. Разница решающая: на конфликте с соседом по своей же
	// строке немедленный пересчёт КОРРЕКТЕН (ждать нечего — слот уже занят), а вот
	// раунд к недоступному соседу без ожидания покрывает доли секунды.
	// Оба близнеца — живые файлы дерева, см. README §«Инъекция».
	// Ключ — КЛАССИФИКАЦИЯ полученного ответа, а не упоминание словаря кодов:
	// `status.Errorf(codes.Internal, …)` СОЗДАЁТ отказ, а не разбирает чужой, и по
	// первой (слишком широкой) редакции давал ложные находки на vpc-аллокаторе и
	// на mac-retry сетевого интерфейса — оба пересчитывают СВОЮ строку.
	peerAnswerRe = regexp.MustCompile(`(status\.Code\(|status\.FromError\(|\.Code\(\)|retryable\(|[iI]sTransient\(|[iI]sRetriable\(|StatusCode)`)
	// A4 — использование списка КАК МНОЖЕСТВА. Безопасное индексирование
	// (`len(v) > 0 && v[0] != ""`) множеством его не делает: это защита от паники,
	// а не сужение. Первая редакция не различала, и 16 из 18 находок были ложными.
	// ПРЕФИКСНОЕ совпадение, а не точное: членство пишут и своей функцией
	// (`containsSAN`, `hasRelation`), и точный список имён превратил бы предикат в
	// проверку одной библиотечной идиомы. Цена — исключение строковых операций
	// (`strings.HasPrefix(s, …)`), у которых первый аргумент тоже совпадает с
	// подлежащим, но подлежащее там СТРОКА, а не множество.
	membershipRe = regexp.MustCompile(`(?i)^(contains|includes|lookup|member|indexof|has)`)
	strOpsPkg    = map[string]bool{"strings": true, "bytes": true}
)

const totalPredicates = 11

// ---------------------------------------------------------------------------

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "goast: не переданы пути файлов")
		os.Exit(3)
	}
	c := census{Kind: "census", Predicates: totalPredicates}
	if len(perObjectCheck) == 0 {
		c.Disabled = append(c.Disabled, "A8:пустой словарь имён проверки")
	}

	fset := token.NewFileSet()
	for _, path := range os.Args[1:] {
		c.Files++
		src, err := os.ReadFile(path)
		if err != nil {
			emit(unparsed{Kind: "unparsed", File: path, Err: err.Error()})
			continue
		}
		f, err := parser.ParseFile(fset, path, src, parser.ParseComments)
		if err != nil {
			// НЕ молчаливый пропуск: вызывающий обязан сказать, что предикаты Go по
			// этому файлу не прогонялись (security.md п.8 — мягкий проход обязан
			// отличать настройку от сбоя; здесь это «сбой входа», и он громкий).
			emit(unparsed{Kind: "unparsed", File: path, Err: err.Error()})
			continue
		}
		c.Parsed++
		isTest := strings.HasSuffix(path, "_test.go") || strings.Contains(path, "/testdata/")
		if isTest {
			// Предпосылка ОБЪЯВЛЯЕТСЯ числом, а не подразумевается: «послабление в
			// прод-дереве» — класс про прод-дерево, и сколько файлов из него выведено,
			// читатель обязан видеть, иначе объём осмотренного завышен молча.
			c.TestFiles++
		}
		ast.Inspect(f, func(n ast.Node) bool {
			if n != nil {
				c.Nodes++
			}
			return true
		})
		for _, d := range f.Decls {
			c.Decls++
			_ = d
		}
		c.Comments += len(f.Comments)

		run(fset, f, path, isTest)
	}
	c.Considered, c.Fired = considered, fired
	emit(c)
}

func run(fset *token.FileSet, f *ast.File, path string, isTest bool) {
	pos := func(p token.Pos) (int, int) {
		q := fset.Position(p)
		return q.Line, q.Column
	}

	// --- A10: отложенная находка В ПОЗИЦИИ КОММЕНТАРИЯ ---------------------
	// Ключ класса: позиция. Строковый литерал "TODO" в фикстуре и слово TODO в
	// доке, ЗАПРЕЩАЮЩЕЙ TODO, сюда не попадают by construction.
	if !isTest {
		for _, cg := range f.Comments {
			for _, cm := range cg.List {
				if strings.Contains(cm.Text, "TODO") || strings.Contains(cm.Text, "FIXME") ||
					strings.Contains(cm.Text, "XXX") {
					note("A10")
				}
				if m := todoRe.FindStringSubmatch(cm.Text); m != nil {
					l, col := pos(cm.Pos())
					emitFinding(finding{
						Class: "A10", Title: "отложенная находка в прод-коде",
						File: path, Line: l, Col: col, Symbol: m[1],
						Why: "закрывает находку объявлением о будущем; в том же PR её закрыть некому",
						Fix: "закрыть в этом же изменении либо завести issue с кодом-артефактом и убрать метку",
						Section: "core ban #11 · verdict-and-landing §«Внесение: expand → migrate → contract»",
					})
				}
			}
		}
	}

	ast.Inspect(f, func(n ast.Node) bool {
		switch node := n.(type) {

		case *ast.FuncDecl:
			if !isTest {
				checkA1(node, path, pos)
				checkA6(node, path, pos)
			}
			checkA4(node, path, pos, fset)
			checkA11(node, path, pos)

		case *ast.IfStmt:
			if !isTest {
				checkA2(node, path, pos, fset)
			}

		case *ast.CallExpr:
			if !isTest {
				checkA3(node, path, pos, fset)
			}

		case *ast.BinaryExpr:
			checkA5(node, path, pos, fset)

		case *ast.ForStmt:
			if !isTest {
				checkA7(node, path, pos, fset)
			}

		case *ast.RangeStmt:
			if !isTest {
				checkA8(node, path, pos, fset, f)
			}

		case *ast.KeyValueExpr:
			// Отметка кандидата стоит на ФОРМЕ и потому берёт и `_test.go`: тестовый
			// файл — это и есть объявленный законный близнец класса, и он в дереве
			// живой (`gateway/cmd/api-gateway/external_isolation_wiring_test.go`).
			// Прежняя редакция отмечала уже ПОСЛЕ отсева тестов, поэтому близнец в
			// переписи не значился и A9 читался как «0 кандидатов» — то есть
			// «ничего не читал» было неотличимо от «класс в дереве закрыт».
			checkA9kv(node, path, pos, isTest)

		case *ast.Ident:
			if bypassIdent.MatchString(node.Name) {
				note("A9")
				if !isTest {
					l, col := pos(node.Pos())
					emitFinding(finding{
						Class: "A9", Title: "послабление вместо secure-эталона",
						File: path, Line: l, Col: col, Symbol: node.Name,
						Why:  "именованный обход проверки живёт в прод-дереве; он всегда доступен и никогда не истекает",
						Fix:  "взять secure-паттерн из values.prod (allow-list SPIFFE) и применить его же в dev",
						Section: "verdict-and-landing §«Внесение: expand → migrate → contract» · security.md §«Production-mode обязателен ВЕЗДЕ»",
					})
				}
			}
		}
		return true
	})
}

// --- A1 -------------------------------------------------------------------
// Запасная личность на пустом контексте: из контекста достают личность, и функция
// НЕ УМЕЕТ сказать «её там не было». Ключ — имя ТИПА результата, а не имя функции.
// Отрицательный близнец 1: (Principal, bool) — признак присутствия есть, молчим.
// Отрицательный близнец 2: (*slog.Logger) — один результат, но не личность, молчим.
func checkA1(fd *ast.FuncDecl, path string, pos func(token.Pos) (int, int)) {
	if fd.Type.Results == nil || len(fd.Type.Results.List) != 1 {
		return
	}
	if fd.Type.Results.List[0].Names != nil && len(fd.Type.Results.List[0].Names) > 1 {
		return
	}
	if !takesContext(fd.Type.Params) {
		return
	}
	note("A1")
	name := baseTypeName(fd.Type.Results.List[0].Type)
	if !identityTypes[name] {
		return
	}
	l, col := pos(fd.Pos())
	emitFinding(finding{
		Class: "A1", Title: "запасная личность на пустом контексте",
		File: path, Line: l, Col: col, Symbol: fd.Name.Name + " → " + name,
		Why: "единственный результат не умеет выразить «личности в контексте не было»; " +
			"вызывающий получает валидный на вид объект и записывает его владельцем",
		Fix:     "вернуть вторым результатом признак присутствия (Principal, bool) либо ошибку; отсутствие — отдельно от значения",
		Section: "code-authoring §«Умолчание, которое становится утверждением» → «Запасная личность на пустом контексте»",
	})
}

// --- A2 -------------------------------------------------------------------
// «Спросить» и «списать» разнесены: между вопросом и списанием помещается
// параллельный вызывающий, и потолок становится rate × параллелизм.
// Отрицательный близнец: `if !lim.Allow(k) { … }` — идиома x/time/rate, где Allow
// САМ списывает. Требование «обе половины на ОДНОМ ресивере» делает его молчащим.
func checkA2(is *ast.IfStmt, path string, pos func(token.Pos) (int, int), fset *token.FileSet) {
	recv, ask := askReceiver(is.Cond)
	if recv == "" {
		return
	}
	note("A2")
	var found string
	var at token.Pos
	ast.Inspect(is.Body, func(n ast.Node) bool {
		ce, ok := n.(*ast.CallExpr)
		if !ok {
			return true
		}
		se, ok := ce.Fun.(*ast.SelectorExpr)
		if !ok || !spendRe.MatchString(se.Sel.Name) {
			return true
		}
		if exprText(fset, se.X) != recv {
			return true
		}
		found = se.Sel.Name
		at = se.Pos()
		return false
	})
	if found == "" {
		return
	}
	l, col := pos(at)
	emitFinding(finding{
		Class: "A2", Title: "«спросить» и «списать» разнесены",
		File: path, Line: l, Col: col, Symbol: recv + "." + ask + " → " + recv + "." + found,
		Why: "между вопросом и списанием проходит параллельный вызывающий; фактический потолок = " +
			"объявленный × число параллельных, а тест без управляемых часов этого не различает",
		Fix:     "одна операция, отвечающая и списывающая (CompareAndSwap / Allow, списывающий сам); проба с управляемыми часами",
		Section: "code-authoring §«Решение и его следствие разнесены» → «Спросить и списать на in-process общем ресурсе»",
	})
}

func askReceiver(cond ast.Expr) (recv, method string) {
	var r, m string
	ast.Inspect(cond, func(n ast.Node) bool {
		ce, ok := n.(*ast.CallExpr)
		if !ok {
			return true
		}
		se, ok := ce.Fun.(*ast.SelectorExpr)
		if !ok || !askRe.MatchString(se.Sel.Name) {
			return true
		}
		if id, ok := se.X.(*ast.Ident); ok {
			r, m = id.Name, se.Sel.Name
			return false
		}
		if sub, ok := se.X.(*ast.SelectorExpr); ok {
			r, m = flatten(sub), se.Sel.Name
			return false
		}
		return true
	})
	return r, m
}

// --- A3 -------------------------------------------------------------------
// Насыщающее сужение типа ВЫШЕ валидатора: приведение уже переполнило значение,
// валидатор видит легальное число и молчит. Отрицательный близнец — голый геттер.
func checkA3(ce *ast.CallExpr, path string, pos func(token.Pos) (int, int), fset *token.FileSet) {
	se, ok := ce.Fun.(*ast.SelectorExpr)
	if !ok || !pageValidators[se.Sel.Name] || len(ce.Args) == 0 {
		return
	}
	note("A3")
	arg, ok := ce.Args[0].(*ast.CallExpr)
	if !ok {
		return
	}
	id, ok := arg.Fun.(*ast.Ident)
	if !ok || !narrowingConv[id.Name] {
		return
	}
	l, col := pos(arg.Pos())
	emitFinding(finding{
		Class: "A3", Title: "насыщающее сужение типа выше валидатора",
		File: path, Line: l, Col: col, Symbol: exprText(fset, ce),
		Why: "приведение выполняется ДО проверки; значение, вышедшее за диапазон, приходит к валидатору " +
			"уже легальным, и отказ, обещанный контрактом, не наступает",
		Fix:     "передавать валидатору исходную ширину; сужать после того, как значение признано допустимым",
		Section: "code-authoring §«Порядок операций внутри кода» → «Насыщающее сужение типа выше валидатора»",
	})
}

// --- A4 -------------------------------------------------------------------
// Пустой список = «не сужаем», а не «запрещаем». Проверка вида
// `len(X) > 0 && !contains(X, v)` при пустом X отвечает «да» каждому.
// Отрицательный близнец: ветка `len(X) == 0 → отказ` где-то в той же функции.
func checkA4(fd *ast.FuncDecl, path string, pos func(token.Pos) (int, int), fset *token.FileSet) {
	if fd.Body == nil {
		return
	}
	type cand struct {
		subject string
		at      token.Pos
		text    string
	}
	var cands []cand
	closed := map[string]bool{}

	ast.Inspect(fd.Body, func(n ast.Node) bool {
		be, ok := n.(*ast.BinaryExpr)
		if !ok {
			return true
		}
		// закрывающая ветка: len(X) == 0 / len(X) < 1 / X == nil
		if s := lenSubjectCmpZero(be, fset); s != "" {
			closed[s] = true
		}
		if be.Op != token.LAND {
			return true
		}
		left, ok := be.X.(*ast.BinaryExpr)
		if !ok || left.Op != token.GTR {
			return true
		}
		s := lenSubject(left.X, fset)
		if s == "" || !isZeroLit(left.Y) {
			return true
		}
		note("A4")
		if !usedAsSet(be.Y, s, fset) {
			return true
		}
		cands = append(cands, cand{subject: s, at: be.Pos(), text: exprText(fset, be)})
		return true
	})

	for _, c := range cands {
		if closed[c.subject] {
			continue
		}
		l, col := pos(c.at)
		txt := c.text
		if len(txt) > 90 {
			txt = txt[:90] + "…"
		}
		emitFinding(finding{
			Class: "A4", Title: "пустой список означает «не сужаем»",
			File: path, Line: l, Col: col, Symbol: txt,
			Why: "сужение выполняется, ТОЛЬКО пока список непуст; на пустом список пропускает всех, " +
				"и внешне это неотличимо от работающего ограничения",
			Fix:     "безусловная ветка «список пуст → отказ» ПЕРЕД сужением; и boot-guard, отказывающий в старте при пустом списке",
			Section: "gate-authoring §«Гейт заявляет предпосылку и объём осмотренного» · security.md §«AuthN+AuthZ ВЕЗДЕ» п.5",
		})
	}
}

// --- A5 -------------------------------------------------------------------
// Guard считает сырой срез: strings.Split НИКОГДА не возвращает срез длины 0,
// поэтому сравнение с нулём провабельно мертво — значение "," его проходит.
func checkA5(be *ast.BinaryExpr, path string, pos func(token.Pos) (int, int), fset *token.FileSet) {
	if be.Op != token.EQL && be.Op != token.LSS && be.Op != token.LEQ {
		return
	}
	var lenArg ast.Expr
	if ce, ok := be.X.(*ast.CallExpr); ok {
		if id, ok := ce.Fun.(*ast.Ident); ok && id.Name == "len" && len(ce.Args) == 1 {
			lenArg = ce.Args[0]
		}
	}
	if lenArg == nil || !isZeroLit(be.Y) {
		return
	}
	note("A5")
	inner, ok := lenArg.(*ast.CallExpr)
	if !ok {
		return
	}
	se, ok := inner.Fun.(*ast.SelectorExpr)
	if !ok || se.Sel.Name != "Split" && se.Sel.Name != "SplitN" && se.Sel.Name != "Fields" {
		return
	}
	if id, ok := se.X.(*ast.Ident); !ok || id.Name != "strings" {
		return
	}
	if se.Sel.Name == "Fields" {
		return // Fields на пустой строке ДАЁТ пустой срез — здесь сравнение живое
	}
	l, col := pos(be.Pos())
	emitFinding(finding{
		Class: "A5", Title: "guard считает сырой срез",
		File: path, Line: l, Col: col, Symbol: exprText(fset, be),
		Why: "strings.Split никогда не возвращает срез длины 0 — сравнение тождественно ложно; " +
			"значение \",\" его проходит, сервис стартует, доверяя всем",
		Fix:     "считать записи, которые ПРИМЕТ транспорт (splitNonEmpty); один предикат на guard и на самоотчёт",
		Section: "gate-authoring §«Гейт заявляет предпосылку и объём осмотренного» · security.md §«AuthN+AuthZ ВЕЗДЕ» п.5",
	})
}

// --- A6 -------------------------------------------------------------------
// Default-ветка классификатора выбирает ПОЛИТИКУ: терминальный `return true`
// означает «всё неопознанное повторяем». Отказ в правах повтором не лечится, и
// строка вечно блокирует голову своей партиции.
func checkA6(fd *ast.FuncDecl, path string, pos func(token.Pos) (int, int)) {
	if fd.Body == nil || len(fd.Body.List) == 0 {
		return
	}
	if fd.Type.Results == nil || len(fd.Type.Results.List) != 1 {
		return
	}
	if baseTypeName(fd.Type.Results.List[0].Type) != "bool" {
		return
	}
	if !classifierRe.MatchString(fd.Name.Name) && !classifierRe.MatchString(recvTypeName(fd)) {
		return
	}
	note("A6")
	last, ok := fd.Body.List[len(fd.Body.List)-1].(*ast.ReturnStmt)
	if !ok || len(last.Results) != 1 {
		return
	}
	id, ok := last.Results[0].(*ast.Ident)
	if !ok || id.Name != "true" {
		return
	}
	l, col := pos(last.Pos())
	emitFinding(finding{
		Class: "A6", Title: "корзина «прочее» выбрана в разрешающую сторону",
		File: path, Line: l, Col: col, Symbol: fd.Name.Name + " → return true",
		Why: "неопознанный чужой отказ классифицируется как временный; отказ в правах повтором " +
			"не проходит никогда, а голова партиции остаётся заблокированной",
		Fix:     "терминальный исход по умолчанию (return false) + явный перечень действительно временных",
		Section: "code-authoring §«Чужой ответ: классификация и бюджет» → «Default-ветка классификатора выбирает ПОЛИТИКУ»",
	})
}

// --- A7 -------------------------------------------------------------------
// Раунды повтора не ждут. Ловится ровно «не ждут» — НЕ «бюджет выведен из
// аргумента о прогрессе» (это суждение, предикатом не берётся).
// Предпосылка предиката объявлена: граница цикла НАЗВАНА по повторам.
func checkA7(fs *ast.ForStmt, path string, pos func(token.Pos) (int, int), fset *token.FileSet) {
	if fs.Cond == nil || fs.Body == nil {
		return
	}
	condText := exprText(fset, fs.Cond)
	if !retryBoundRe.MatchString(condText) {
		return
	}
	note("A7")
	if bodyWaits(fs.Body) {
		return
	}
	// Предпосылка, БЕЗ которой предикат ловит не свой предмет: раунд повторяет
	// обращение к чужому и классифицирует ЕГО ответ. Пересчёт своей строки под
	// конкуренцией (isUniqueViolation / isDeviceCollision) сюда не попадает — там
	// немедленный повтор правилен. Живые близнецы в kacho@5af959db:
	//   (+) gateway/internal/clients/iam_authorize_client.go — status.Code + retryable, ожидания нет;
	//   (−) services/vpc/…/address/alloc_shared.go, services/storage/…/volume_repo.go — конкуренция за свой слот.
	if !peerAnswerRe.MatchString(nodeText(fset, fs.Body)) {
		return
	}
	l, col := pos(fs.Pos())
	emitFinding(finding{
		Class: "A7", Title: "раунды повтора не ждут",
		File: path, Line: l, Col: col, Symbol: "for " + condText,
		Why: "цикл выполняет раунды подряд без задержки: заявленный бюджет покрывает доли секунды " +
			"вместо секунд, и «сдался» читается как отказ предмета, а не как отсутствие ожидания",
		Fix:     "ожидание в каждом раунде (backoff.Wait/ctx-aware таймер); бюджет размерять от cap петли",
		Section: "code-authoring §«Чужой ответ: классификация и бюджет» → «Бюджет повторов — доказательство, а не константа»",
	})
}

func bodyWaits(b *ast.BlockStmt) bool {
	waits := false
	ast.Inspect(b, func(n ast.Node) bool {
		switch v := n.(type) {
		case *ast.UnaryExpr:
			if v.Op == token.ARROW { // <-ch
				waits = true
			}
		case *ast.SelectStmt:
			waits = true
		case *ast.CallExpr:
			if se, ok := v.Fun.(*ast.SelectorExpr); ok && waitCall.MatchString(se.Sel.Name) {
				waits = true
			}
		}
		return !waits
	})
	return waits
}

// --- A8 -------------------------------------------------------------------
// Вопрос на строку вместо вопроса на страницу. Слабейший в наборе: держится на
// СЛОВАРЕ имён (см. perObjectCheck), и у словаря обязан быть свой контроль —
// census печатает его размер, пустой словарь выключает предикат явно.
func checkA8(rs *ast.RangeStmt, path string, pos func(token.Pos) (int, int), fset *token.FileSet, f *ast.File) {
	if len(perObjectCheck) == 0 || rs.Body == nil {
		return
	}
	// Вторая предпосылка, и она не косметическая: СТРАНИЦА существует только там,
	// где есть листание. Цикл по трём отношениям (iam authzguard), по бэкендам
	// health-пробы или по строкам разового посевного гейта страницей не является, и
	// первая редакция предиката дала на них 3 ложных из 5. Живые близнецы:
	//   (−) services/iam/internal/authzguard/scope.go — цикл по MutateRelations;
	//   (−) gateway/internal/health/health.go — цикл по бэкендам.
	fd := enclosingFunc(f, rs.Pos())
	if fd == nil || !strings.Contains(strings.ToLower(fd.Name.Name), "list") {
		return
	}
	note("A8")
	ast.Inspect(rs.Body, func(n ast.Node) bool {
		ce, ok := n.(*ast.CallExpr)
		if !ok || len(ce.Args) == 0 {
			return true
		}
		se, ok := ce.Fun.(*ast.SelectorExpr)
		if !ok || !perObjectCheck[se.Sel.Name] {
			return true
		}
		id, ok := ce.Args[0].(*ast.Ident)
		if !ok || id.Name != "ctx" {
			return true
		}
		l, col := pos(ce.Pos())
		emitFinding(finding{
			Class: "A8", Title: "вопрос на строку вместо вопроса на страницу",
			File: path, Line: l, Col: col, Symbol: exprText(fset, ce.Fun),
			Why: "стоимость растёт с числом строк, а бюджет принадлежит запросу: на полной странице " +
				"проверка не укладывается в срок и даёт отказ на положительном пути",
			Fix:     "партийный вопрос по идентификаторам страницы (≤100), партии не последовательно; сужать страницу ради бюджета — нельзя",
			Section: "code-authoring §«Унификация и стоимость» → «Стоимость страницы принадлежит запросу, а не строке»",
		})
		return false
	})
}

// --- A9 (composite literal) ------------------------------------------------
func checkA9kv(kv *ast.KeyValueExpr, path string, pos func(token.Pos) (int, int), isTest bool) {
	id, ok := kv.Key.(*ast.Ident)
	if !ok || id.Name != "InsecureSkipVerify" {
		return
	}
	note("A9")
	if isTest {
		return // тестовый файл — объявленный законный близнец, не находка
	}
	v, ok := kv.Value.(*ast.Ident)
	if !ok || v.Name != "true" {
		return
	}
	l, col := pos(kv.Pos())
	emitFinding(finding{
		Class: "A9", Title: "послабление вместо secure-эталона",
		File: path, Line: l, Col: col, Symbol: "InsecureSkipVerify: true",
		Why:  "проверка личности собеседника снята в прод-дереве; TLS доказывает шифрование, но не имя",
		Fix:  "secure-паттерн из values.prod (доверие internal-CA + сверка SAN); в dev — тот же, не обход",
		Section: "verdict-and-landing §«Внесение: expand → migrate → contract» · security.md §«Production-mode обязателен ВЕЗДЕ»",
	})
}

// --- A11 ------------------------------------------------------------------
// Дублёр снисходительнее настоящего: объявленный контрактный параметр не читается
// ни разу, поэтому проба, ради которой дублёр написан, не может упасть.
func checkA11(fd *ast.FuncDecl, path string, pos func(token.Pos) (int, int)) {
	if fd.Recv == nil || fd.Body == nil || len(fd.Body.List) == 0 {
		return
	}
	if !doubleRecvRe.MatchString(recvTypeName(fd)) {
		return
	}
	used := map[string]bool{}
	ast.Inspect(fd.Body, func(n ast.Node) bool {
		if id, ok := n.(*ast.Ident); ok {
			used[id.Name] = true
		}
		return true
	})
	for _, p := range fd.Type.Params.List {
		for _, nm := range p.Names {
			if nm.Name == "_" || !contractArgs[nm.Name] {
				continue
			}
			note("A11")
			if used[nm.Name] {
				continue
			}
			l, col := pos(nm.Pos())
			emitFinding(finding{
				Class: "A11", Title: "дублёр снисходительнее настоящего",
				File: path, Line: l, Col: col, Symbol: recvTypeName(fd) + "." + fd.Name.Name + "(" + nm.Name + ")",
				Why: "дублёр принимает параметр контракта и не смотрит на него; проба против такого дублёра " +
					"зелена и при негодном значении — то есть не может упасть",
				Fix:     "дублёр отвечает контрактным отказом на негодный вход, ровно как продукт",
				Section: "gate-authoring §«Фикстура и дублёр»",
			})
		}
	}
}

// ---------------------------------------------------------------------------
// Вспомогательное
// ---------------------------------------------------------------------------

func takesContext(fl *ast.FieldList) bool {
	if fl == nil {
		return false
	}
	for _, p := range fl.List {
		if se, ok := p.Type.(*ast.SelectorExpr); ok {
			if x, ok := se.X.(*ast.Ident); ok && x.Name == "context" && se.Sel.Name == "Context" {
				return true
			}
		}
	}
	return false
}

func baseTypeName(e ast.Expr) string {
	switch v := e.(type) {
	case *ast.Ident:
		return v.Name
	case *ast.StarExpr:
		return baseTypeName(v.X)
	case *ast.SelectorExpr:
		return v.Sel.Name
	}
	return ""
}

func recvTypeName(fd *ast.FuncDecl) string {
	if fd.Recv == nil || len(fd.Recv.List) == 0 {
		return ""
	}
	return baseTypeName(fd.Recv.List[0].Type)
}

func flatten(se *ast.SelectorExpr) string {
	switch x := se.X.(type) {
	case *ast.Ident:
		return x.Name + "." + se.Sel.Name
	case *ast.SelectorExpr:
		return flatten(x) + "." + se.Sel.Name
	}
	return se.Sel.Name
}

func isZeroLit(e ast.Expr) bool {
	bl, ok := e.(*ast.BasicLit)
	return ok && bl.Kind == token.INT && bl.Value == "0"
}

func lenSubject(e ast.Expr, fset *token.FileSet) string {
	ce, ok := e.(*ast.CallExpr)
	if !ok {
		return ""
	}
	id, ok := ce.Fun.(*ast.Ident)
	if !ok || id.Name != "len" || len(ce.Args) != 1 {
		return ""
	}
	return exprText(fset, ce.Args[0])
}

func lenSubjectCmpZero(be *ast.BinaryExpr, fset *token.FileSet) string {
	switch be.Op {
	case token.EQL:
		if s := lenSubject(be.X, fset); s != "" && isZeroLit(be.Y) {
			return s
		}
		if id, ok := be.Y.(*ast.Ident); ok && id.Name == "nil" {
			return exprText(fset, be.X)
		}
	case token.LSS:
		if s := lenSubject(be.X, fset); s != "" {
			if bl, ok := be.Y.(*ast.BasicLit); ok && bl.Value == "1" {
				return s
			}
		}
	}
	return ""
}

func exprText(fset *token.FileSet, e ast.Expr) string { return nodeText(fset, e) }

func nodeText(fset *token.FileSet, n ast.Node) string {
	var sb strings.Builder
	if err := printNode(&sb, fset, n); err != nil {
		return ""
	}
	return strings.Join(strings.Fields(sb.String()), " ")
}

// usedAsSet — читается ли `subject` в выражении КАК МНОЖЕСТВО: членство
// (`slices.Contains(subject, v)`), поиск (`indexOf`), либо индексация НЕ константой
// (map-lookup). Индексация литералом (`subject[0]`) множеством не является — это
// безопасное чтение первого элемента, и оно к классу отношения не имеет.
func usedAsSet(e ast.Expr, subject string, fset *token.FileSet) bool {
	found := false
	ast.Inspect(e, func(n ast.Node) bool {
		if found {
			return false
		}
		switch v := n.(type) {
		case *ast.CallExpr:
			name := ""
			switch fn := v.Fun.(type) {
			case *ast.Ident:
				name = fn.Name
			case *ast.SelectorExpr:
				name = fn.Sel.Name
				if pkg, ok := fn.X.(*ast.Ident); ok && strOpsPkg[pkg.Name] {
					return true // строковая операция: подлежащее — строка, не множество
				}
			}
			if !membershipRe.MatchString(name) {
				return true
			}
			for _, a := range v.Args {
				if exprText(fset, a) == subject {
					found = true
					return false
				}
			}
		case *ast.IndexExpr:
			if exprText(fset, v.X) != subject {
				return true
			}
			if _, isLit := v.Index.(*ast.BasicLit); isLit {
				return true // subject[0] — чтение первого элемента, не членство
			}
			// subject[len(subject)-1] — чтение ПОСЛЕДНЕГО элемента, тоже не членство.
			// Живой близнец: gateway/internal/config/config.go — `len(iss) > 0 &&
			// iss[len(iss)-1] == '/'` (нормализация слеша у issuer'а).
			if strings.Contains(exprText(fset, v.Index), "len("+subject+")") {
				return true
			}
			found = true
			return false
		}
		return true
	})
	return found
}

// enclosingFunc — функция, внутри которой лежит позиция. Нужна предикатам, чья
// предпосылка сформулирована про РОЛЬ места (A8: страница существует только там,
// где есть листание). Поиск по позиции, а не по стеку обхода: дешевле и не зависит
// от порядка визитов.
func enclosingFunc(f *ast.File, p token.Pos) *ast.FuncDecl {
	for _, d := range f.Decls {
		fd, ok := d.(*ast.FuncDecl)
		if !ok {
			continue
		}
		if fd.Pos() <= p && p <= fd.End() {
			return fd
		}
	}
	return nil
}
