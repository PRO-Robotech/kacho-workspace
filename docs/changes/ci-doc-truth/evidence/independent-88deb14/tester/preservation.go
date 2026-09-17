package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"flag"
	"fmt"
	"go/ast"
	"go/parser"
	"go/scanner"
	"go/token"
	"os"
	"os/exec"
	"reflect"
	"strconv"
	"strings"
)

var paths = []string{
	"internal/repohygiene/grpcmountparity_test.go",
	"internal/repohygiene/catalogreachability_test.go",
	"internal/repohygiene/subscriptionformshape_injection_test.go",
	"internal/repohygiene/subscriptionformshape.go",
}
var oldReasons = []string{
	"носитель нагрузки не выражен ветвлением `${carrier}`. Запретить прозой значение, которое допускает собственный тип, невозможно: без ветвления пустая нагрузка остаётся представимой, и подписчик прочтёт её как «у предмета не осталось полей»",
	"ветвление носителя несёт %d ветв(ей), а обязано ровно две: состояние ЛИБО признак, что состояния нет. Одна ветвь возвращает представимость пустой нагрузки, третья — заводит исход, о котором подписчику не сказано, что с ним делать",
}
var newReasons = []string{
	"носитель нагрузки не выражен ветвлением `${carrier}`. Форма обязана объявлять выбор: состояние ЛИБО признак, что состояния нет. Заполненность конкретного сообщения этот анализатор не проверяет",
	"ветвление носителя несёт %d ветв(ей), а обязано ровно две: состояние ЛИБО признак, что состояния нет. Здесь проверяется число объявленных ветвей, а не заполненность конкретного сообщения",
}

type form struct {
	tokens, tree  string
	count, leaves int
}

func fail(format string, args ...any) error { return fmt.Errorf(format, args...) }
func textExpression(x ast.Expr, dynamic bool) (string, []*ast.BasicLit, error) {
	switch n := x.(type) {
	case *ast.BasicLit:
		if n.Kind != token.STRING {
			return "", nil, fail("non-string leaf %s", n.Kind)
		}
		s, e := strconv.Unquote(n.Value)
		return s, []*ast.BasicLit{n}, e
	case *ast.BinaryExpr:
		if n.Op != token.ADD {
			return "", nil, fail("non-concatenation operator %s", n.Op)
		}
		l, ll, e := textExpression(n.X, dynamic)
		if e != nil {
			return "", nil, e
		}
		r, rr, e := textExpression(n.Y, dynamic)
		return l + r, append(ll, rr...), e
	case *ast.SelectorExpr:
		id, ok := n.X.(*ast.Ident)
		if dynamic && ok && id.Name == "e" && n.Sel.Name == "CarrierOneof" {
			return "${carrier}", nil, nil
		}
	}
	return "", nil, fail("unapproved expression node %T", x)
}
func parse(name string, source []byte) (form, error) {
	var out form
	if len(bytes.TrimSpace(source)) == 0 {
		return out, fail("VOID %s: empty source", name)
	}
	fs := token.NewFileSet()
	f, e := parser.ParseFile(fs, name, source, parser.SkipObjectResolution)
	if e != nil {
		return out, fail("VOID %s parse: %v", name, e)
	}
	if len(f.Decls) == 0 {
		return out, fail("VOID %s: no declarations", name)
	}
	normalized := map[int]string{}
	if name == paths[3] {
		var fn *ast.FuncDecl
		for _, d := range f.Decls {
			if x, ok := d.(*ast.FuncDecl); ok && x.Name.Name == "AuditSubscriptionFormShape" {
				if fn != nil {
					return out, fail("duplicate analyzer")
				}
				fn = x
			}
		}
		if fn == nil {
			return out, fail("VOID missing analyzer")
		}
		var calls []*ast.CallExpr
		ast.Inspect(fn, func(n ast.Node) bool {
			c, ok := n.(*ast.CallExpr)
			if !ok {
				return true
			}
			id, ok := c.Fun.(*ast.Ident)
			if !ok || id.Name != "add" || len(c.Args) < 1 {
				return true
			}
			kind, ok := c.Args[0].(*ast.BasicLit)
			if !ok {
				return true
			}
			v, _ := strconv.Unquote(kind.Value)
			if v == "carrier-not-a-choice" {
				calls = append(calls, c)
			}
			return true
		})
		if len(calls) != 2 {
			return out, fail("expected exactly two carrier diagnostic calls; got %d", len(calls))
		}
		for i, c := range calls {
			if len(c.Args) != 3 {
				return out, fail("call %d args changed", i)
			}
			sel, ok := c.Args[1].(*ast.SelectorExpr)
			if !ok {
				return out, fail("call %d coordinate changed", i)
			}
			id, ok := sel.X.(*ast.Ident)
			if !ok || id.Name != "event" || sel.Sel.Name != "Line" {
				return out, fail("call %d coordinate changed", i)
			}
			expr := c.Args[2]
			if i == 1 {
				fm, ok := expr.(*ast.CallExpr)
				if !ok || len(fm.Args) != 2 {
					return out, fail("formatter shape changed")
				}
				sel, ok := fm.Fun.(*ast.SelectorExpr)
				if !ok {
					return out, fail("formatter changed")
				}
				id, ok := sel.X.(*ast.Ident)
				if !ok || id.Name != "fmt" || sel.Sel.Name != "Sprintf" {
					return out, fail("formatter changed")
				}
				ln, ok := fm.Args[1].(*ast.CallExpr)
				if !ok || len(ln.Args) != 1 {
					return out, fail("dynamic count changed")
				}
				id, ok = ln.Fun.(*ast.Ident)
				if !ok || id.Name != "len" {
					return out, fail("dynamic count changed")
				}
				id, ok = ln.Args[0].(*ast.Ident)
				if !ok || id.Name != "branches" {
					return out, fail("dynamic count argument changed")
				}
				expr = fm.Args[0]
			}
			result, literals, e := textExpression(expr, i == 0)
			if e != nil {
				return out, e
			}
			if result != oldReasons[i] && result != newReasons[i] {
				return out, fail("unapproved Reason %d: %q", i, result)
			}
			expectedLeaves := 5
			if i == 1 {
				expectedLeaves = 4
			}
			if len(literals) != expectedLeaves {
				return out, fail("Reason %d string-leaf count changed: %d", i, len(literals))
			}
			for j, lit := range literals {
				marker := strconv.Quote(fmt.Sprintf("<approved-reason-%d-leaf-%d>", i, j))
				normalized[fs.Position(lit.Pos()).Offset] = marker
				lit.Value = marker
				out.leaves++
			}
		}
	}
	var scan scanner.Scanner
	scanErr := false
	scan.Init(fs.AddFile(name+".tokens", -1, len(source)), source, func(_ token.Position, msg string) { scanErr = true }, scanner.ScanComments)
	var tokens bytes.Buffer
	for {
		pos, tok, lit := scan.Scan()
		if tok == token.EOF {
			break
		}
		if tok == token.COMMENT {
			continue
		}
		if value, ok := normalized[fs.Position(pos).Offset]; ok {
			if tok != token.STRING {
				return out, fail("normalization position is not string")
			}
			lit = value
		}
		fmt.Fprintf(&tokens, "%d:%q\n", tok, lit)
		out.count++
	}
	if scanErr {
		return out, fail("VOID scan error")
	}
	if out.count == 0 {
		return out, fail("VOID no program tokens")
	}
	var tree bytes.Buffer
	if e := ast.Fprint(&tree, nil, f, func(name string, v reflect.Value) bool { return v.Type() != reflect.TypeOf(token.NoPos) }); e != nil {
		return out, e
	}
	out.tokens = tokens.String()
	out.tree = tree.String()
	return out, nil
}
func digest(s []byte) string { x := sha256.Sum256(s); return hex.EncodeToString(x[:]) }
func compare(name string, before, after []byte) (form, error) {
	a, e := parse(name, before)
	if e != nil {
		return a, e
	}
	b, e := parse(name, after)
	if e != nil {
		return b, e
	}
	if a.tokens != b.tokens {
		return b, fail("RED %s: program tokens differ", name)
	}
	if a.tree != b.tree {
		return b, fail("RED %s: position-free AST differs", name)
	}
	return b, nil
}
func git(repo string, args ...string) ([]byte, error) {
	cmd := exec.Command("git", append([]string{"-C", repo}, args...)...)
	for _, v := range os.Environ() {
		if !strings.HasPrefix(v, "GIT_") {
			cmd.Env = append(cmd.Env, v)
		}
	}
	b, e := cmd.Output()
	if e != nil {
		return nil, fail("VOID git %v: %v", args, e)
	}
	return b, nil
}
func birth(base map[string][]byte) error {
	name := paths[3]
	original := base[name]
	lawful := append(append([]byte(nil), original...), []byte("\n// lawful comment-only twin\n")...)
	if _, e := compare(name, original, lawful); e != nil {
		return fail("birth lawful failed: %v", e)
	}
	fmt.Println("BIRTH lawful-comment-only PASS")
	for _, tc := range []struct{ name, from, to string }{
		{"one-program-token", "if len(branches) != 2 {", "if len(branches) != 3 {"},
		{"unapproved-reason", "Запретить ", "Подменить "},
		{"dynamic-leaf", "+e.CarrierOneof+", "+e.StartOneof+"},
		{"kind-leaf", "\"carrier-not-a-choice\"", "\"carrier-other\""},
	} {
		if !bytes.Contains(original, []byte(tc.from)) {
			return fail("birth fixture missing: %s", tc.name)
		}
		mutated := bytes.Replace(original, []byte(tc.from), []byte(tc.to), 1)
		if _, e := compare(name, original, mutated); e == nil {
			return fail("birth %s silently accepted", tc.name)
		} else {
			fmt.Printf("BIRTH %s rejected: %v\n", tc.name, e)
		}
	}
	for _, tc := range []struct {
		name  string
		bytes []byte
	}{{"empty", nil}, {"declaration-free", []byte("package repohygiene\n")}} {
		if _, e := compare(name, original, tc.bytes); e == nil {
			return fail("birth %s silently accepted", tc.name)
		} else {
			fmt.Printf("BIRTH %s rejected: %v\n", tc.name, e)
		}
	}
	return nil
}
func main() {
	repo := flag.String("repo", "", "repository")
	base := flag.String("base", "", "base commit")
	candidate := flag.String("candidate", "", "candidate commit")
	birthOnly := flag.Bool("birth", false, "exercise verifier controls only")
	flag.Parse()
	if *repo == "" || *base == "" || (!*birthOnly && *candidate == "") {
		fmt.Fprintln(os.Stderr, "VOID: repo/base and candidate or birth required")
		os.Exit(2)
	}
	if _, e := git(*repo, "rev-parse", "--verify", *base+"^{commit}"); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(2)
	}
	inputs := map[string][]byte{}
	for _, name := range paths {
		b, e := git(*repo, "show", *base+":"+name)
		if e != nil {
			fmt.Fprintln(os.Stderr, e)
			os.Exit(2)
		}
		inputs[name] = b
	}
	if *birthOnly {
		if e := birth(inputs); e != nil {
			fmt.Fprintln(os.Stderr, e)
			os.Exit(1)
		}
		return
	}
	if _, e := git(*repo, "rev-parse", "--verify", *candidate+"^{commit}"); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(2)
	}
	total := 0
	for _, name := range paths {
		b, e := git(*repo, "show", *candidate+":"+name)
		if e != nil {
			fmt.Fprintln(os.Stderr, e)
			os.Exit(2)
		}
		f, e := compare(name, inputs[name], b)
		if e != nil {
			fmt.Fprintln(os.Stderr, e)
			os.Exit(1)
		}
		total += f.count
		fmt.Printf("PASS %s tokens=%d approved_string_leaves=%d before_sha256=%s after_sha256=%s\n", name, f.count, f.leaves, digest(inputs[name]), digest(b))
	}
	fmt.Printf("PASS files=%d program_tokens=%d base=%s candidate=%s\n", len(paths), total, *base, *candidate)
}
