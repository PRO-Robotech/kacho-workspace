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
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
)

const addendumPath = "internal/repohygiene/subscriptionformshape_test.go"
const addendumBase = "88deb14ca3b7f9c58529d8a3ebc4cb19920fc5d0"
const addendumBaseHash = "ab38d70525b8d9279c63c711e373a312bfe315fc86e498ef5eeea4c2f5dbd959"
const staleLines = "\t\t// Обязательность в этом дереве выражается ОПЦИЕЙ поля, а не ключевым\n\t\t// словом: `required` из proto3 убрано, а опция жива и употребляется.\n"

var generatedPaths = []string{"subscription.pb.go", "subscription_service.pb.go", "subscription_service.pb.gw.go", "subscription_service_grpc.pb.go"}

type parsed struct {
	tokens, tree, directives string
	count, declarations      int
	raw                      map[string][]byte
}

func sha(b []byte) string { h := sha256.Sum256(b); return hex.EncodeToString(h[:]) }
func textExpr(e ast.Expr) (string, error) {
	switch n := e.(type) {
	case *ast.BasicLit:
		if n.Kind == token.STRING {
			return strconv.Unquote(n.Value)
		}
	case *ast.BinaryExpr:
		if n.Op == token.ADD {
			l, err := textExpr(n.X)
			if err != nil {
				return "", err
			}
			r, err := textExpr(n.Y)
			return l + r, err
		}
	}
	return "", fmt.Errorf("unsupported descriptor expression %T", e)
}
func parse(name string, b []byte) (parsed, error) {
	p := parsed{raw: map[string][]byte{}}
	if len(bytes.TrimSpace(b)) == 0 {
		return p, fmt.Errorf("VOID empty source: %s", name)
	}
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, name, b, parser.SkipObjectResolution)
	if err != nil {
		return p, fmt.Errorf("VOID parse: %w", err)
	}
	if len(f.Decls) == 0 {
		return p, fmt.Errorf("VOID no declarations: %s", name)
	}
	p.declarations = len(f.Decls)
	var tokens, directives, tree bytes.Buffer
	var scan scanner.Scanner
	var scanErr error
	scan.Init(fset.AddFile(name+".tokens", -1, len(b)), b, func(_ token.Position, s string) { scanErr = fmt.Errorf("VOID scan: %s", s) }, scanner.ScanComments)
	for {
		_, tok, lit := scan.Scan()
		if tok == token.EOF {
			break
		}
		if tok == token.COMMENT {
			// Directive text remains part of this invariant despite prose being excluded.
			if strings.HasPrefix(lit, "//go:") || strings.HasPrefix(lit, "//line ") || strings.HasPrefix(lit, "/*line ") || strings.HasPrefix(lit, "// +build ") || strings.Contains(lit, "#cgo") {
				fmt.Fprintf(&directives, "%q\n", lit)
			}
			continue
		}
		fmt.Fprintf(&tokens, "%d:%q\n", tok, lit)
		p.count++
	}
	if scanErr != nil {
		return p, scanErr
	}
	if p.count == 0 {
		return p, fmt.Errorf("VOID no tokens")
	}
	if err = ast.Fprint(&tree, nil, f, func(_ string, v reflect.Value) bool { return v.Type() != reflect.TypeOf(token.NoPos) }); err != nil {
		return p, err
	}
	p.tokens, p.tree, p.directives = tokens.String(), tree.String(), directives.String()
	for _, d := range f.Decls {
		g, ok := d.(*ast.GenDecl)
		if !ok || g.Tok != token.CONST {
			continue
		}
		for _, s := range g.Specs {
			v, ok := s.(*ast.ValueSpec)
			if !ok {
				continue
			}
			for i, n := range v.Names {
				if strings.HasSuffix(n.Name, "_rawDesc") {
					if i >= len(v.Values) {
						return p, fmt.Errorf("missing raw descriptor value")
					}
					x, err := textExpr(v.Values[i])
					if err != nil {
						return p, err
					}
					if len(x) == 0 {
						return p, fmt.Errorf("VOID empty raw descriptor")
					}
					p.raw[n.Name] = []byte(x)
				}
			}
		}
	}
	return p, nil
}
func compare(name string, before, after []byte) (parsed, error) {
	a, err := parse(name, before)
	if err != nil {
		return a, err
	}
	b, err := parse(name, after)
	if err != nil {
		return b, err
	}
	if a.tokens != b.tokens {
		return b, fmt.Errorf("REJECT program token difference")
	}
	if a.tree != b.tree {
		return b, fmt.Errorf("REJECT position-free AST difference")
	}
	if a.directives != b.directives {
		return b, fmt.Errorf("REJECT directive difference")
	}
	if !reflect.DeepEqual(a.raw, b.raw) {
		return b, fmt.Errorf("REJECT raw descriptors difference")
	}
	return b, nil
}
func addendum(before, after []byte) (parsed, error) {
	p, err := compare(addendumPath, before, after)
	if err != nil {
		return p, err
	}
	if sha(before) != addendumBaseHash {
		return p, fmt.Errorf("REJECT unexpected baseline bytes")
	}
	if bytes.Count(before, []byte(staleLines)) != 1 {
		return p, fmt.Errorf("REJECT stale lines absent or duplicated")
	}
	want := bytes.Replace(before, []byte(staleLines), nil, 1)
	if !bytes.Equal(want, after) {
		return p, fmt.Errorf("REJECT candidate is not exact deletion of two frozen lines")
	}
	return p, nil
}
func git(repo, rev, path string) ([]byte, error) {
	if repo == "" || rev == "" {
		return nil, fmt.Errorf("VOID missing Git input")
	}
	cmd := exec.Command("git", "-C", repo, "show", rev+":"+path)
	for _, e := range os.Environ() {
		if !strings.HasPrefix(e, "GIT_") {
			cmd.Env = append(cmd.Env, e)
		}
	}
	b, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("VOID Git read %s: %w", rev, err)
	}
	return b, nil
}
func birth(b []byte) error {
	lawful := bytes.Replace(b, []byte(staleLines), nil, 1)
	p, err := addendum(b, lawful)
	if err != nil {
		return fmt.Errorf("lawful deletion: %w", err)
	}
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, addendumPath, lawful, parser.SkipObjectResolution)
	if err != nil {
		return err
	}
	var id *ast.Ident
	for _, d := range f.Decls {
		if x, ok := d.(*ast.FuncDecl); ok {
			id = x.Name
			break
		}
	}
	if id == nil {
		return fmt.Errorf("VOID missing one-token control target")
	}
	pos := fset.Position(id.Pos()).Offset
	defect := append([]byte{}, lawful[:pos]...)
	defect = append(defect, []byte("ChangedBirthFunction")...)
	defect = append(defect, lawful[pos+len(id.Name):]...)
	cases := []struct {
		name     string
		source   []byte
		required string
	}{
		{"one_program_token", defect, "program token difference"},
		{"extra_comment", append(append([]byte{}, lawful...), []byte("\n// extra unapproved prose\n")...), "not exact deletion"},
		{"unchanged_source", b, "not exact deletion"},
		{"empty", nil, "VOID empty source"},
		{"no_declarations", []byte("package repohygiene\n"), "VOID no declarations"},
	}
	fmt.Printf("PASS lawful exact two-comment deletion tokens=%d declarations=%d baseline_sha256=%s candidate_sha256=%s\n", p.count, p.declarations, sha(b), sha(lawful))
	for _, c := range cases {
		_, err := addendum(b, c.source)
		if err == nil || !strings.Contains(err.Error(), c.required) {
			return fmt.Errorf("birth %s wrong outcome: %v", c.name, err)
		}
		fmt.Printf("PASS birth %s => %v\n", c.name, err)
	}
	return nil
}
func run() error {
	mode := flag.String("mode", "", "generated or addendum")
	before := flag.String("before", "", "baseline generated directory")
	after := flag.String("after", "", "candidate generated directory")
	repo := flag.String("repo", "", "Kacho repository")
	candidate := flag.String("candidate", "", "candidate commit")
	born := flag.Bool("birth", false, "run addendum synthetic controls")
	flag.Parse()
	if flag.NArg() != 0 {
		return fmt.Errorf("VOID unexpected arguments")
	}
	switch *mode {
	case "generated":
		if *before == "" || *after == "" {
			return fmt.Errorf("VOID missing directories")
		}
		total, rawCount := 0, 0
		for _, dir := range []string{*before, *after} {
			entries, err := os.ReadDir(dir)
			if err != nil {
				return fmt.Errorf("VOID unread directory: %w", err)
			}
			names := map[string]bool{}
			for _, e := range entries {
				if !e.IsDir() {
					names[e.Name()] = true
				}
			}
			if len(names) != len(generatedPaths) {
				return fmt.Errorf("REJECT generated census %d", len(names))
			}
			for _, path := range generatedPaths {
				if !names[path] {
					return fmt.Errorf("VOID missing generated file %s", path)
				}
			}
		}
		for _, path := range generatedPaths {
			a, err := os.ReadFile(filepath.Join(*before, path))
			if err != nil {
				return err
			}
			b, err := os.ReadFile(filepath.Join(*after, path))
			if err != nil {
				return err
			}
			p, err := compare(path, a, b)
			if err != nil {
				return fmt.Errorf("%s: %w", path, err)
			}
			total += p.count
			rawCount += len(p.raw)
			fmt.Printf("PASS %s tokens=%d declarations=%d bytes_equal=%v before_sha256=%s after_sha256=%s\n", path, p.count, p.declarations, bytes.Equal(a, b), sha(a), sha(b))
			for name, raw := range p.raw {
				fmt.Printf("PASS raw descriptor %s bytes=%d sha256=%s\n", name, len(raw), sha(raw))
			}
		}
		if rawCount != 2 {
			return fmt.Errorf("REJECT raw descriptor census %d expected 2", rawCount)
		}
		fmt.Printf("PASS generated total_files=4 tokens=%d raw_descriptors=%d zero_whitelist=true\n", total, rawCount)
		return nil
	case "addendum":
		b, err := git(*repo, addendumBase, addendumPath)
		if err != nil {
			return err
		}
		if *born {
			if *candidate != "" {
				return fmt.Errorf("VOID ambiguous birth/candidate")
			}
			return birth(b)
		}
		a, err := git(*repo, *candidate, addendumPath)
		if err != nil {
			return err
		}
		p, err := addendum(b, a)
		if err != nil {
			return err
		}
		fmt.Printf("PASS addendum base=%s candidate=%s tokens=%d declarations=%d baseline_sha256=%s candidate_sha256=%s zero_whitelist=true\n", addendumBase, *candidate, p.count, p.declarations, sha(b), sha(a))
		return nil
	default:
		return fmt.Errorf("VOID missing or invalid mode")
	}
}
func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
}
