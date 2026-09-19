package main

import (
 "fmt"
 "os"
 subscription "github.com/PRO-Robotech/corelib/api/corelib/subscription"
 "google.golang.org/protobuf/proto"
)

func main() {
 event := &subscription.SubscriptionEvent{}
 ref := event.ProtoReflect()
 carrier := ref.Descriptor().Oneofs().ByName("carrier")
 if carrier == nil { fmt.Fprintln(os.Stderr, "carrier descriptor absent"); os.Exit(1) }
 bytes, err := proto.Marshal(event)
 fmt.Printf("branches=%d selected=%t marshal_ok=%t bytes=%d\n", carrier.Fields().Len(), ref.WhichOneof(carrier) != nil, err == nil, len(bytes))
 if carrier.Fields().Len() != 2 || ref.WhichOneof(carrier) != nil || err != nil || len(bytes) != 0 { os.Exit(1) }
}
