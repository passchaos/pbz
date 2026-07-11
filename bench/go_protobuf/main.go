package main

import (
	"fmt"
	"time"

	"github.com/pbz/bench/personpb"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/encoding/prototext"
	"google.golang.org/protobuf/proto"
)

const benchmarkSamples = 3

type benchResult struct {
	name         string
	iterations   int
	samples      int
	elapsed      time.Duration
	bytesPerIter int
}

func (r benchResult) print() {
	nsPerIter := float64(r.elapsed.Nanoseconds()) / float64(r.iterations)
	opsPerSec := float64(r.iterations) * 1_000_000_000.0 / float64(r.elapsed.Nanoseconds())
	mibPerSec := float64(r.bytesPerIter*r.iterations) * 1_000_000_000.0 / float64(r.elapsed.Nanoseconds()) / (1024.0 * 1024.0)
	fmt.Printf("%s: best of %d x %d iters, %d bytes/iter, %.2f ns/op, %.2f ops/s, %.2f MiB/s\n", r.name, r.samples, r.iterations, r.bytesPerIter, nsPerIter, opsPerSec, mibPerSec)
}

func runTimed(name string, iterations int, bytesPerIter int, f func()) benchResult {
	warmupIterations := iterations / 10
	if warmupIterations < 1 {
		warmupIterations = 1
	}
	if warmupIterations > 1000 {
		warmupIterations = 1000
	}
	for i := 0; i < warmupIterations; i++ {
		f()
	}

	var best time.Duration
	for sample := 0; sample < benchmarkSamples; sample++ {
		start := time.Now()
		for i := 0; i < iterations; i++ {
			f()
		}
		elapsed := time.Since(start)
		if sample == 0 || elapsed < best {
			best = elapsed
		}
	}
	return benchResult{name: name, iterations: iterations, samples: benchmarkSamples, elapsed: best, bytesPerIter: bytesPerIter}
}

func makePacked() *personpb.Packed {
	values := make([]int32, 1024)
	for i := range values {
		values[i] = int32(i % 4096)
	}
	return &personpb.Packed{Values: values}
}

func makeFixedPacked() *personpb.FixedPacked {
	values := make([]uint32, 1024)
	for i := range values {
		values[i] = uint32(i*3 + 1)
	}
	return &personpb.FixedPacked{Values: values}
}

func makeFixed64Packed() *personpb.Fixed64Packed {
	values := make([]uint64, 1024)
	for i := range values {
		values[i] = uint64(i*5 + 1)
	}
	return &personpb.Fixed64Packed{Values: values}
}

func makePerson() *personpb.Person {
	return &personpb.Person{
		Id:     7,
		Name:   "Zig",
		Scores: []int32{10, 20, 30, 40, 50, 60, 70, 80},
		Counts: map[string]int32{"red": 1, "green": 2, "blue": 3},
	}
}

func main() {
	const iterations = 20_000
	person := makePerson()
	bytes, err := proto.Marshal(person)
	if err != nil {
		panic(err)
	}
	jsonBytes, err := protojson.Marshal(person)
	if err != nil {
		panic(err)
	}
	textBytes, err := prototext.Marshal(person)
	if err != nil {
		panic(err)
	}
	packed := makePacked()
	packedBytes, err := proto.Marshal(packed)
	if err != nil {
		panic(err)
	}
	fixedPacked := makeFixedPacked()
	fixedPackedBytes, err := proto.Marshal(fixedPacked)
	if err != nil {
		panic(err)
	}
	fixed64Packed := makeFixed64Packed()
	fixed64PackedBytes, err := proto.Marshal(fixed64Packed)
	if err != nil {
		panic(err)
	}

	fmt.Println("go protobuf benchmark baseline")
	fmt.Printf("payload size: %d\n", len(bytes))
	fmt.Printf("json payload size: %d\n", len(jsonBytes))
	fmt.Printf("text payload size: %d\n", len(textBytes))
	fmt.Printf("packed payload size: %d\n", len(packedBytes))
	fmt.Printf("fixed32 packed payload size: %d\n", len(fixedPackedBytes))
	fmt.Printf("fixed64 packed payload size: %d\n", len(fixed64PackedBytes))

	runTimed("go protobuf binary encode", iterations, len(bytes), func() {
		out, err := proto.Marshal(person)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	buf := make([]byte, 0, len(bytes))
	marshalOptions := proto.MarshalOptions{}
	runTimed("go protobuf binary encode reuse", iterations, len(bytes), func() {
		var err error
		buf, err = marshalOptions.MarshalAppend(buf[:0], person)
		if err != nil {
			panic(err)
		}
	}).print()

	unmarshalOptions := proto.UnmarshalOptions{}
	runTimed("go protobuf binary decode", iterations, len(bytes), func() {
		var decoded personpb.Person
		if err := unmarshalOptions.Unmarshal(bytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf JSON stringify", iterations, len(jsonBytes), func() {
		out, err := protojson.Marshal(person)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	jsonUnmarshalOptions := protojson.UnmarshalOptions{}
	runTimed("go protobuf JSON parse", iterations, len(jsonBytes), func() {
		var decoded personpb.Person
		if err := jsonUnmarshalOptions.Unmarshal(jsonBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf TextFormat format", iterations, len(textBytes), func() {
		out, err := prototext.Marshal(person)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	textUnmarshalOptions := prototext.UnmarshalOptions{}
	runTimed("go protobuf TextFormat parse", iterations, len(textBytes), func() {
		var decoded personpb.Person
		if err := textUnmarshalOptions.Unmarshal(textBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf packed encode", iterations, len(packedBytes), func() {
		out, err := proto.Marshal(packed)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	packedBuf := make([]byte, 0, len(packedBytes))
	runTimed("go protobuf packed encode reuse", iterations, len(packedBytes), func() {
		var err error
		packedBuf, err = marshalOptions.MarshalAppend(packedBuf[:0], packed)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf packed decode", iterations, len(packedBytes), func() {
		var decoded personpb.Packed
		if err := unmarshalOptions.Unmarshal(packedBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf fixed32 packed encode", iterations, len(fixedPackedBytes), func() {
		out, err := proto.Marshal(fixedPacked)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	fixedPackedBuf := make([]byte, 0, len(fixedPackedBytes))
	runTimed("go protobuf fixed32 packed encode reuse", iterations, len(fixedPackedBytes), func() {
		var err error
		fixedPackedBuf, err = marshalOptions.MarshalAppend(fixedPackedBuf[:0], fixedPacked)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf fixed32 packed decode", iterations, len(fixedPackedBytes), func() {
		var decoded personpb.FixedPacked
		if err := unmarshalOptions.Unmarshal(fixedPackedBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf fixed64 packed encode", iterations, len(fixed64PackedBytes), func() {
		out, err := proto.Marshal(fixed64Packed)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	fixed64PackedBuf := make([]byte, 0, len(fixed64PackedBytes))
	runTimed("go protobuf fixed64 packed encode reuse", iterations, len(fixed64PackedBytes), func() {
		var err error
		fixed64PackedBuf, err = marshalOptions.MarshalAppend(fixed64PackedBuf[:0], fixed64Packed)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf fixed64 packed decode", iterations, len(fixed64PackedBytes), func() {
		var decoded personpb.Fixed64Packed
		if err := unmarshalOptions.Unmarshal(fixed64PackedBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()
}
