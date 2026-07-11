package main

import (
	"fmt"
	"time"

	"github.com/pbz/bench/personpb"
	"google.golang.org/protobuf/proto"
)

type benchResult struct {
	name         string
	iterations   int
	elapsed      time.Duration
	bytesPerIter int
}

func (r benchResult) print() {
	nsPerIter := float64(r.elapsed.Nanoseconds()) / float64(r.iterations)
	opsPerSec := float64(r.iterations) * 1_000_000_000.0 / float64(r.elapsed.Nanoseconds())
	mibPerSec := float64(r.bytesPerIter*r.iterations) * 1_000_000_000.0 / float64(r.elapsed.Nanoseconds()) / (1024.0 * 1024.0)
	fmt.Printf("%s: %d iters, %d bytes/iter, %.2f ns/op, %.2f ops/s, %.2f MiB/s\n", r.name, r.iterations, r.bytesPerIter, nsPerIter, opsPerSec, mibPerSec)
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

	start := time.Now()
	for i := 0; i < iterations; i++ {
		f()
	}
	return benchResult{name: name, iterations: iterations, elapsed: time.Since(start), bytesPerIter: bytesPerIter}
}

func makePacked() *personpb.Packed {
	values := make([]int32, 1024)
	for i := range values {
		values[i] = int32(i % 4096)
	}
	return &personpb.Packed{Values: values}
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
	packed := makePacked()
	packedBytes, err := proto.Marshal(packed)
	if err != nil {
		panic(err)
	}

	fmt.Println("go protobuf benchmark baseline")
	fmt.Printf("payload size: %d\n", len(bytes))
	fmt.Printf("packed payload size: %d\n", len(packedBytes))

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
}
