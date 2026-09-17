package main

import (
	"bytes"
	"crypto/sha256"
	"fmt"
	"os"

	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/descriptorpb"
)

func run() error {
	if len(os.Args) != 3 {
		return fmt.Errorf("VOID need two descriptor paths")
	}
	var previous []byte
	for _, path := range os.Args[1:] {
		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if len(b) == 0 {
			return fmt.Errorf("VOID empty descriptor set")
		}
		if previous != nil && !bytes.Equal(previous, b) {
			return fmt.Errorf("REJECT descriptor bytes differ")
		}
		previous = b
		var set descriptorpb.FileDescriptorSet
		if err = proto.Unmarshal(b, &set); err != nil {
			return err
		}
		if len(set.File) == 0 {
			return fmt.Errorf("VOID no file descriptors")
		}
		wanted := map[string]bool{"corelib/subscription/subscription.proto": false, "corelib/subscription/subscription_service.proto": false}
		for _, f := range set.File {
			if f.SourceCodeInfo != nil {
				return fmt.Errorf("REJECT source info remains")
			}
			if _, ok := wanted[f.GetName()]; ok {
				if wanted[f.GetName()] {
					return fmt.Errorf("REJECT duplicate contract descriptor")
				}
				wanted[f.GetName()] = true
				fmt.Printf("PASS file=%s messages=%d enums=%d services=%d source_info_absent=true\n", f.GetName(), len(f.MessageType), len(f.EnumType), len(f.Service))
			}
		}
		for n, present := range wanted {
			if !present {
				return fmt.Errorf("VOID contract descriptor missing: %s", n)
			}
		}
		fmt.Printf("PASS path=%s descriptor_files=%d bytes=%d sha256=%x\n", path, len(set.File), len(b), sha256.Sum256(b))
	}
	return nil
}
func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
}
