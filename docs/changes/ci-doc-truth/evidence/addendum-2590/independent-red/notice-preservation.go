// Независимый одноразовый verifier #2590. Product source он только читает.
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"go/ast"
	"go/parser"
	"go/scanner"
	"go/token"
	"io"
	"os"
	"reflect"
	"sort"
	"strconv"
	"strings"
)

const contractSHA = "cd4732af9c4c939a715d8c17f6bccd25fadb495ebc854d10f1dd151e52668903"

type contract struct {
	BaselineSHA  string `json:"baseline_file_sha256"`
	CandidateSHA string `json:"expected_candidate_file_sha256"`
	Region       struct {
		Start int    `json:"start_byte_zero_based"`
		End   int    `json:"end_byte_exclusive"`
		Old   string `json:"old_bytes_utf8"`
		New   string `json:"new_bytes_utf8"`
	} `json:"allowed_region"`
}

type parsed struct {
	Tokens, AST, Directives             []byte
	Count, Declarations, DirectiveCount int
	Tests                               []string
}

type result struct {
	Status                string   `json:"status"`
	Code                  string   `json:"code"`
	ContractSHA           string   `json:"contract_sha256"`
	BaselineSHA           string   `json:"baseline_sha256"`
	CandidateSHA          string   `json:"candidate_sha256"`
	BaselineTokens        int      `json:"baseline_tokens"`
	CandidateTokens       int      `json:"candidate_tokens"`
	BaselineDeclarations  int      `json:"baseline_declarations"`
	CandidateDeclarations int      `json:"candidate_declarations"`
	BaselineDirectives    int      `json:"baseline_directives"`
	CandidateDirectives   int      `json:"candidate_directives"`
	TokensEqual           bool     `json:"tokens_equal"`
	ASTEqual              bool     `json:"position_free_ast_equal"`
	DirectivesEqual       bool     `json:"directives_equal"`
	PrefixEqual           bool     `json:"prefix_equal"`
	SuffixEqual           bool     `json:"suffix_equal"`
	LiteralReplacement    bool     `json:"literal_replacement"`
	BaselineTests         []string `json:"baseline_tests"`
	CandidateTests        []string `json:"candidate_tests"`
	BaselineTokensSHA     string   `json:"baseline_tokens_sha256"`
	CandidateTokensSHA    string   `json:"candidate_tokens_sha256"`
	BaselineASTSHA        string   `json:"baseline_ast_sha256"`
	CandidateASTSHA       string   `json:"candidate_ast_sha256"`
}

func digest(b []byte) string {
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

func parse(b []byte) (parsed, string) {
	p := parsed{Tests: []string{}}
	if len(bytes.TrimSpace(b)) == 0 {
		return p, "EMPTY_INPUT"
	}
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, "notice_test.go", b, parser.SkipObjectResolution)
	if err != nil {
		return p, "PARSE_FAILED"
	}
	p.Declarations = len(f.Decls)
	if p.Declarations == 0 {
		return p, "NO_DECLARATIONS"
	}
	for _, declaration := range f.Decls {
		if f, ok := declaration.(*ast.FuncDecl); ok && strings.HasPrefix(f.Name.Name, "Test") {
			p.Tests = append(p.Tests, f.Name.Name)
		}
	}
	sort.Strings(p.Tests)
	var tokenBytes, directiveBytes, tree bytes.Buffer
	var s scanner.Scanner
	badScan := false
	s.Init(token.NewFileSet().AddFile("notice.tokens", -1, len(b)), b,
		func(token.Position, string) { badScan = true }, scanner.ScanComments)
	for {
		_, tok, lit := s.Scan()
		if tok == token.EOF {
			break
		}
		if tok == token.COMMENT {
			if strings.HasPrefix(lit, "//go:") || strings.HasPrefix(lit, "//line ") ||
				strings.HasPrefix(lit, "/*line ") || strings.HasPrefix(lit, "// +build ") ||
				strings.Contains(lit, "#cgo") {
				directiveBytes.WriteString(strconv.Quote(lit))
				directiveBytes.WriteByte('\n')
				p.DirectiveCount++
			}
			continue
		}
		tokenBytes.WriteString(strconv.Itoa(int(tok)))
		tokenBytes.WriteByte(':')
		tokenBytes.WriteString(strconv.Quote(lit))
		tokenBytes.WriteByte('\n')
		p.Count++
	}
	if badScan || p.Count == 0 {
		return p, "SCAN_FAILED"
	}
	// Единственная фильтрация — физические позиции; AST-поля программы не исключаются.
	if err := ast.Fprint(&tree, nil, f, func(_ string, value reflect.Value) bool {
		return value.Type() != reflect.TypeOf(token.NoPos)
	}); err != nil {
		return p, "AST_FAILED"
	}
	p.Tokens, p.AST, p.Directives = tokenBytes.Bytes(), tree.Bytes(), directiveBytes.Bytes()
	return p, ""
}

func run(args []string) result {
	r := result{Status: "NOT_EXECUTED", Code: "INVALID_ARGUMENT", BaselineTests: []string{}, CandidateTests: []string{}}
	flags := flag.NewFlagSet("notice-preservation", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	contractPath := flags.String("contract", "", "frozen baseline contract")
	baselinePath := flags.String("baseline", "", "baseline file")
	candidatePath := flags.String("candidate", "", "candidate file")
	if flags.Parse(args) != nil || flags.NArg() != 0 || *contractPath == "" || *baselinePath == "" || *candidatePath == "" {
		return r
	}
	cbytes, err := os.ReadFile(*contractPath)
	if err != nil {
		r.Code = "CONTRACT_UNREADABLE"
		return r
	}
	r.ContractSHA = digest(cbytes)
	if r.ContractSHA != contractSHA {
		r.Code = "CONTRACT_MISMATCH"
		return r
	}
	var c contract
	if json.Unmarshal(cbytes, &c) != nil {
		r.Code = "CONTRACT_INVALID"
		return r
	}
	before, err := os.ReadFile(*baselinePath)
	if err != nil {
		r.Code = "BASELINE_UNREADABLE"
		return r
	}
	r.BaselineSHA = digest(before)
	if r.BaselineSHA != c.BaselineSHA {
		r.Code = "BASELINE_MISMATCH"
		return r
	}
	after, err := os.ReadFile(*candidatePath)
	if err != nil {
		r.Code = "CANDIDATE_UNREADABLE"
		return r
	}
	r.CandidateSHA = digest(after)
	a, code := parse(before)
	if code != "" {
		r.Code = "BASELINE_" + code
		return r
	}
	b, code := parse(after)
	r.BaselineTokens, r.CandidateTokens = a.Count, b.Count
	r.BaselineDeclarations, r.CandidateDeclarations = a.Declarations, b.Declarations
	r.BaselineTests, r.CandidateTests = a.Tests, b.Tests
	if code != "" {
		r.Code = "CANDIDATE_" + code
		return r
	}
	r.BaselineDirectives, r.CandidateDirectives = a.DirectiveCount, b.DirectiveCount
	r.TokensEqual, r.ASTEqual, r.DirectivesEqual = bytes.Equal(a.Tokens, b.Tokens), bytes.Equal(a.AST, b.AST), bytes.Equal(a.Directives, b.Directives)
	r.BaselineTokensSHA, r.CandidateTokensSHA = digest(a.Tokens), digest(b.Tokens)
	r.BaselineASTSHA, r.CandidateASTSHA = digest(a.AST), digest(b.AST)
	s, e := c.Region.Start, c.Region.End
	if s < 0 || e <= s || e > len(before) || !bytes.Equal(before[s:e], []byte(c.Region.Old)) {
		r.Code = "REGION_MISMATCH"
		return r
	}
	want := append(append(append([]byte{}, before[:s]...), []byte(c.Region.New)...), before[e:]...)
	if digest(want) != c.CandidateSHA {
		r.Code = "EXPECTED_CANDIDATE_MISMATCH"
		return r
	}
	r.PrefixEqual = len(after) >= s && bytes.Equal(before[:s], after[:s])
	suffixStart := s + len([]byte(c.Region.New))
	r.SuffixEqual = len(after) >= suffixStart && bytes.Equal(before[e:], after[suffixStart:])
	r.LiteralReplacement = bytes.Equal(want, after)
	r.Status = "FAIL"
	switch {
	case !r.TokensEqual:
		r.Code = "PROGRAM_TOKEN_CHANGED"
	case !r.ASTEqual:
		r.Code = "AST_CHANGED"
	case !r.DirectivesEqual:
		r.Code = "DIRECTIVE_CHANGED"
	case !r.LiteralReplacement:
		r.Code = "NOT_EXACT_REPLACEMENT"
	default:
		r.Status, r.Code = "PASS", "EXACT_REPLACEMENT_PRESERVED"
	}
	return r
}

func main() {
	r := run(os.Args[1:])
	if err := json.NewEncoder(os.Stdout).Encode(r); err != nil {
		os.Exit(3)
	}
	switch r.Status {
	case "PASS":
		os.Exit(0)
	case "FAIL":
		os.Exit(1)
	default:
		os.Exit(3)
	}
}
