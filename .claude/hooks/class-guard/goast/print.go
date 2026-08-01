package main

import (
	"go/ast"
	"go/printer"
	"go/token"
	"io"
)

// printNode печатает узел исходным синтаксисом — нужен, чтобы координата находки
// несла ТЕКСТ найденного, а не только строку. Читатель отчёта должен узнать место
// без открытия файла.
func printNode(w io.Writer, fset *token.FileSet, n ast.Node) error {
	return printer.Fprint(w, fset, n)
}
