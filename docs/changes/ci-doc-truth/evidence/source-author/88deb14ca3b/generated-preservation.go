package main

import (
 "bytes"
 "crypto/sha256"
 "encoding/hex"
 "encoding/json"
 "fmt"
 "go/ast"
 "go/parser"
 "go/scanner"
 "go/token"
 "os"
 "path/filepath"
 "reflect"
 "strconv"
 "strings"
)

type parsed struct { tokens, tree string; count int; descriptors map[string]string }
func digest(b []byte) string { h := sha256.Sum256(b); return hex.EncodeToString(h[:]) }
func literal(e ast.Expr) (string, error) {
 switch x := e.(type) {
 case *ast.BasicLit:
  if x.Kind == token.STRING { return strconv.Unquote(x.Value) }
 case *ast.BinaryExpr:
  if x.Op == token.ADD { a, err := literal(x.X); if err != nil { return "", err }; b, err := literal(x.Y); return a+b, err }
 }
 return "", fmt.Errorf("unsupported raw descriptor expression %T", e)
}
func parse(name string, source []byte) (parsed, error) {
 out := parsed{descriptors: map[string]string{}}
 if len(bytes.TrimSpace(source)) == 0 { return out, fmt.Errorf("VOID empty source") }
 fs := token.NewFileSet()
 f, err := parser.ParseFile(fs, name, source, parser.SkipObjectResolution)
 if err != nil { return out, err }
 if len(f.Decls) == 0 { return out, fmt.Errorf("VOID declaration-free source") }
 var tokens, tree bytes.Buffer
 var sc scanner.Scanner
 scanErr := false
 sc.Init(fs.AddFile(name+".tokens", -1, len(source)), source, func(_ token.Position, _ string) { scanErr = true }, scanner.ScanComments)
 for { _, t, s := sc.Scan(); if t == token.EOF { break }; if t == token.COMMENT { continue }; fmt.Fprintf(&tokens, "%d:%q\n", t, s); out.count++ }
 if scanErr || out.count == 0 { return out, fmt.Errorf("VOID invalid tokens") }
 if err := ast.Fprint(&tree, nil, f, func(_ string, v reflect.Value) bool { return v.Type() != reflect.TypeOf(token.NoPos) }); err != nil { return out, err }
 for _, d := range f.Decls {
  g, ok := d.(*ast.GenDecl); if !ok { continue }
  for _, s := range g.Specs {
   v, ok := s.(*ast.ValueSpec); if !ok { continue }
   for i, n := range v.Names { if strings.HasSuffix(n.Name, "_rawDesc") {
    if i >= len(v.Values) { return out, fmt.Errorf("VOID absent raw descriptor") }
    raw, err := literal(v.Values[i]); if err != nil { return out, err }; if len(raw)==0 { return out, fmt.Errorf("VOID empty raw descriptor") }; out.descriptors[n.Name]=raw
   } }
  }
 }
 out.tokens, out.tree = tokens.String(), tree.String()
 return out, nil
}
func compare(name string, a, b []byte) (parsed, error) {
 x, err := parse(name, a); if err != nil { return x, err }; y, err := parse(name, b); if err != nil { return y, err }
 if x.tokens != y.tokens { return y, fmt.Errorf("RED program tokens differ") }
 if x.tree != y.tree { return y, fmt.Errorf("RED AST differs") }
 if !reflect.DeepEqual(x.descriptors, y.descriptors) { return y, fmt.Errorf("RED raw descriptor differs") }
 return y, nil
}
func run() error {
 if len(os.Args)!=3 { return fmt.Errorf("VOID requires baseline and candidate directories") }
 names := []string{"subscription.pb.go", "subscription_service.pb.go", "subscription_service.pb.gw.go", "subscription_service_grpc.pb.go"}
 records := []map[string]any{}
 for i, name := range names {
  a, err := os.ReadFile(filepath.Join(os.Args[1], name)); if err != nil { return err }; b, err := os.ReadFile(filepath.Join(os.Args[2], name)); if err != nil { return err }
  if i==0 {
   lawful := append(append([]byte(nil), a...), []byte("\n// lawful comment twin\n")...); if _, err := compare(name,a,lawful); err != nil { return err }
   needle:=[]byte("package subscription"); if bytes.Count(a,needle)!=1 { return fmt.Errorf("birth control absent") }; defect:=bytes.Replace(a,needle,[]byte("package other"),1)
   if _,err:=compare(name,a,defect); err==nil { return fmt.Errorf("birth defect accepted") }
   for _, empty:=range [][]byte{nil,[]byte("package subscription\n")} { if _,err:=compare(name,a,empty);err==nil{return fmt.Errorf("birth empty accepted")} }
  }
  out,err:=compare(name,a,b);if err!=nil{return fmt.Errorf("%s: %w",name,err)}
  if i==0 && len(out.descriptors)!=1 {return fmt.Errorf("VOID expected one primary raw descriptor")}
  desc:=map[string]any{};for k,v:=range out.descriptors{desc[k]=map[string]any{"bytes":len(v),"sha256":digest([]byte(v))}}
  records=append(records,map[string]any{"file":name,"before_sha256":digest(a),"after_sha256":digest(b),"program_tokens":out.count,"tokens_sha256":digest([]byte(out.tokens)),"ast_sha256":digest([]byte(out.tree)),"raw_descriptors":desc,"tokens_equal":true,"ast_equal":true,"raw_descriptors_equal":true})
 }
 return json.NewEncoder(os.Stdout).Encode(map[string]any{"birth_lawful_pass":true,"birth_program_defect_rejected":true,"birth_empty_rejected":true,"birth_declaration_free_rejected":true,"files":records})
}
func main(){if err:=run();err!=nil{fmt.Fprintln(os.Stderr,err);os.Exit(1)}}
