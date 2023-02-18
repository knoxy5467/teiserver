To get the files run
```bash
# We're not getting them from elsewhere at this stage
```

To build the files run
```bash
# With gRPC
protoc --elixir_out=gen_descriptors=true,plugins=grpc:. lib/teiserver/tachyon/tachyon.proto

# Without gRPC
protoc --elixir_out=gen_descriptors=true:. lib/teiserver/tachyon/tachyon.proto
```