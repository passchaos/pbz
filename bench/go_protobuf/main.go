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

func makeSFixedPacked() *personpb.SFixedPacked {
	values := make([]int32, 1024)
	for i := range values {
		magnitude := int32(i*7 + 1)
		if i&1 == 0 {
			values[i] = magnitude
		} else {
			values[i] = -magnitude
		}
	}
	return &personpb.SFixedPacked{Values: values}
}

func makeSFixed64Packed() *personpb.SFixed64Packed {
	values := make([]int64, 1024)
	for i := range values {
		magnitude := (int64(i) << 20) + int64(i)*11 + 1
		if i&1 == 0 {
			values[i] = magnitude
		} else {
			values[i] = -magnitude
		}
	}
	return &personpb.SFixed64Packed{Values: values}
}

func makeFloatPacked() *personpb.FloatPacked {
	values := make([]float32, 1024)
	for i := range values {
		values[i] = float32(i)*0.25 + 1.0
	}
	return &personpb.FloatPacked{Values: values}
}

func makeDoublePacked() *personpb.DoublePacked {
	values := make([]float64, 1024)
	for i := range values {
		values[i] = float64(i)*0.5 + 1.0
	}
	return &personpb.DoublePacked{Values: values}
}

func makeUInt64Packed() *personpb.UInt64Packed {
	values := make([]uint64, 1024)
	for i := range values {
		values[i] = (uint64(i) << 21) + uint64(i)*17 + 1
	}
	return &personpb.UInt64Packed{Values: values}
}

func makeUInt32Packed() *personpb.UInt32Packed {
	values := make([]uint32, 1024)
	for i := range values {
		values[i] = uint32((i << 12) + i*3 + 1)
	}
	return &personpb.UInt32Packed{Values: values}
}

func makeInt64Packed() *personpb.Int64Packed {
	values := make([]int64, 1024)
	for i := range values {
		magnitude := (int64(i) << 20) + int64(i)*7 + 1
		if i&1 == 0 {
			values[i] = magnitude
		} else {
			values[i] = -magnitude
		}
	}
	return &personpb.Int64Packed{Values: values}
}

func makeSInt32Packed() *personpb.SInt32Packed {
	values := make([]int32, 1024)
	for i := range values {
		magnitude := int32(i*5 + 1)
		if i&1 == 0 {
			values[i] = magnitude
		} else {
			values[i] = -magnitude
		}
	}
	return &personpb.SInt32Packed{Values: values}
}

func makeSInt64Packed() *personpb.SInt64Packed {
	values := make([]int64, 1024)
	for i := range values {
		magnitude := (int64(i) << 20) + int64(i)*13 + 1
		if i&1 == 0 {
			values[i] = magnitude
		} else {
			values[i] = -magnitude
		}
	}
	return &personpb.SInt64Packed{Values: values}
}

func makeBoolPacked() *personpb.BoolPacked {
	values := make([]bool, 1024)
	for i := range values {
		values[i] = i%3 != 0
	}
	return &personpb.BoolPacked{Values: values}
}

func makeEnumPacked() *personpb.EnumPacked {
	values := make([]personpb.BenchKind, 1024)
	for i := range values {
		values[i] = personpb.BenchKind(i % 3)
	}
	return &personpb.EnumPacked{Values: values}
}

func makeLargeMap() *personpb.LargeMap {
	counts := make(map[string]int32, 1024)
	for i := 0; i < 1024; i++ {
		counts[fmt.Sprintf("key-%04d", i)] = int32((i % 4096) + 1)
	}
	return &personpb.LargeMap{Counts: counts}
}

func makePerson() *personpb.Person {
	return &personpb.Person{
		Id:     7,
		Name:   "Zig",
		Scores: []int32{10, 20, 30, 40, 50, 60, 70, 80},
		Counts: map[string]int32{"red": 1, "green": 2, "blue": 3},
	}
}

func makeScalarMix() *personpb.ScalarMix {
	return &personpb.ScalarMix{Active: true, Count: 12345, Total: 9876543210, Delta: -321, BigDelta: -9876543, Checksum: 0xdeadbeef, Token: 0x0102030405060708, SignedFixed: -123456, SignedBigFixed: -9876543210, Ratio: 1.25, Score: 9.5, Kind: personpb.BenchKind_BENCH_KIND_BETA, Flags: []bool{true, false, true, true, false, true, false, false}, Ids: []uint64{1, 127, 128, 16384, 1048576, 9876543210}}
}

func makeTextBytes() *personpb.TextBytes {
	return &personpb.TextBytes{
		Title:   "ASCII title for protobuf",
		Payload: []byte("0123456789abcdef0123456789abcdef"),
		Tags:    []string{"alpha", "beta", "gamma", "delta"},
		Chunks:  [][]byte{[]byte("chunk-one"), []byte("chunk-two"), []byte("chunk-three"), []byte("chunk-four")},
	}
}

func makeLargeBytes() *personpb.LargeBytes {
	payload := make([]byte, 64*1024)
	for i := range payload {
		payload[i] = byte((i*31 + 7) & 0xff)
	}
	chunks := make([][]byte, 16)
	for chunkIndex := range chunks {
		chunk := make([]byte, 4*1024)
		for i := range chunk {
			chunk[i] = byte((chunkIndex*17 + i*13 + 3) & 0xff)
		}
		chunks[chunkIndex] = chunk
	}
	return &personpb.LargeBytes{Payload: payload, Chunks: chunks}
}

func presenceChild(id int32, label string) *personpb.PresenceMix_Child {
	return &personpb.PresenceMix_Child{Id: id, Label: label}
}

func makePresenceMix() *personpb.PresenceMix {
	count := int32(0)
	note := ""
	return &personpb.PresenceMix{
		Count: &count,
		Note:  &note,
		Raw:   []byte("presence-raw"),
		Child: presenceChild(7, "child"),
		Pick:  &personpb.PresenceMix_Nested{Nested: presenceChild(11, "nested")},
	}
}

func audit(actor string, atUnix int64) *personpb.Complex_Audit {
	return &personpb.Complex_Audit{Actor: actor, AtUnix: atUnix}
}

func makeComplex() *personpb.Complex {
	return &personpb.Complex{
		Id:      42,
		Audit:   audit("tester", 12345),
		History: []*personpb.Complex_Audit{audit("creator", 12345), audit("reviewer", 67890)},
		Audits: map[string]*personpb.Complex_Audit{
			"latest":  audit("reviewer", 67890),
			"created": audit("creator", 12345),
		},
		Subject: &personpb.Complex_AuditSubject{AuditSubject: audit("subject", 777)},
	}
}

func main() {
	const iterations = 20_000
	person := makePerson()
	scalarmix := makeScalarMix()
	textbytes := makeTextBytes()
	largebytes := makeLargeBytes()
	presencemix := makePresenceMix()
	complex := makeComplex()
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
	scalarmixBytes, err := proto.Marshal(scalarmix)
	if err != nil {
		panic(err)
	}
	textbytesBytes, err := proto.Marshal(textbytes)
	if err != nil {
		panic(err)
	}
	largebytesBytes, err := proto.Marshal(largebytes)
	if err != nil {
		panic(err)
	}
	presencemixBytes, err := proto.Marshal(presencemix)
	if err != nil {
		panic(err)
	}
	complexBytes, err := proto.Marshal(complex)
	if err != nil {
		panic(err)
	}
	complexJSONBytes, err := protojson.Marshal(complex)
	if err != nil {
		panic(err)
	}
	complexTextBytes, err := prototext.Marshal(complex)
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
	sfixedPacked := makeSFixedPacked()
	sfixedPackedBytes, err := proto.Marshal(sfixedPacked)
	if err != nil {
		panic(err)
	}
	sfixed64Packed := makeSFixed64Packed()
	sfixed64PackedBytes, err := proto.Marshal(sfixed64Packed)
	if err != nil {
		panic(err)
	}
	floatPacked := makeFloatPacked()
	floatPackedBytes, err := proto.Marshal(floatPacked)
	if err != nil {
		panic(err)
	}
	doublePacked := makeDoublePacked()
	doublePackedBytes, err := proto.Marshal(doublePacked)
	if err != nil {
		panic(err)
	}
	uint64Packed := makeUInt64Packed()
	uint64PackedBytes, err := proto.Marshal(uint64Packed)
	if err != nil {
		panic(err)
	}
	uint32Packed := makeUInt32Packed()
	uint32PackedBytes, err := proto.Marshal(uint32Packed)
	if err != nil {
		panic(err)
	}
	int64Packed := makeInt64Packed()
	int64PackedBytes, err := proto.Marshal(int64Packed)
	if err != nil {
		panic(err)
	}
	sint32Packed := makeSInt32Packed()
	sint32PackedBytes, err := proto.Marshal(sint32Packed)
	if err != nil {
		panic(err)
	}
	sint64Packed := makeSInt64Packed()
	sint64PackedBytes, err := proto.Marshal(sint64Packed)
	if err != nil {
		panic(err)
	}
	boolPacked := makeBoolPacked()
	boolPackedBytes, err := proto.Marshal(boolPacked)
	if err != nil {
		panic(err)
	}
	enumPacked := makeEnumPacked()
	enumPackedBytes, err := proto.Marshal(enumPacked)
	if err != nil {
		panic(err)
	}
	largeMap := makeLargeMap()
	largeMapBytes, err := proto.Marshal(largeMap)
	if err != nil {
		panic(err)
	}

	fmt.Println("go protobuf benchmark baseline")
	fmt.Printf("payload size: %d\n", len(bytes))
	fmt.Printf("json payload size: %d\n", len(jsonBytes))
	fmt.Printf("text payload size: %d\n", len(textBytes))
	fmt.Printf("scalarmix payload size: %d\n", len(scalarmixBytes))
	fmt.Printf("textbytes payload size: %d\n", len(textbytesBytes))
	fmt.Printf("largebytes payload size: %d\n", len(largebytesBytes))
	fmt.Printf("presencemix payload size: %d\n", len(presencemixBytes))
	fmt.Printf("complex payload size: %d\n", len(complexBytes))
	fmt.Printf("complex json payload size: %d\n", len(complexJSONBytes))
	fmt.Printf("complex text payload size: %d\n", len(complexTextBytes))
	fmt.Printf("packed payload size: %d\n", len(packedBytes))
	fmt.Printf("fixed32 packed payload size: %d\n", len(fixedPackedBytes))
	fmt.Printf("fixed64 packed payload size: %d\n", len(fixed64PackedBytes))
	fmt.Printf("sfixed32 packed payload size: %d\n", len(sfixedPackedBytes))
	fmt.Printf("sfixed64 packed payload size: %d\n", len(sfixed64PackedBytes))
	fmt.Printf("float packed payload size: %d\n", len(floatPackedBytes))
	fmt.Printf("double packed payload size: %d\n", len(doublePackedBytes))
	fmt.Printf("uint64 packed payload size: %d\n", len(uint64PackedBytes))
	fmt.Printf("uint32 packed payload size: %d\n", len(uint32PackedBytes))
	fmt.Printf("int64 packed payload size: %d\n", len(int64PackedBytes))
	fmt.Printf("sint32 packed payload size: %d\n", len(sint32PackedBytes))
	fmt.Printf("sint64 packed payload size: %d\n", len(sint64PackedBytes))
	fmt.Printf("bool packed payload size: %d\n", len(boolPackedBytes))
	fmt.Printf("enum packed payload size: %d\n", len(enumPackedBytes))
	fmt.Printf("large map payload size: %d\n", len(largeMapBytes))

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

	deterministicOptions := proto.MarshalOptions{Deterministic: true}
	deterministicBuf := make([]byte, 0, len(bytes))
	runTimed("go protobuf deterministic binary encode reuse", iterations, len(bytes), func() {
		var err error
		deterministicBuf, err = deterministicOptions.MarshalAppend(deterministicBuf[:0], person)
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

	runTimed("go protobuf scalarmix encode", iterations, len(scalarmixBytes), func() {
		out, err := proto.Marshal(scalarmix)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()
	scalarmixBuf := make([]byte, 0, len(scalarmixBytes))
	runTimed("go protobuf scalarmix encode reuse", iterations, len(scalarmixBytes), func() {
		var err error
		scalarmixBuf, err = marshalOptions.MarshalAppend(scalarmixBuf[:0], scalarmix)
		if err != nil {
			panic(err)
		}
	}).print()
	runTimed("go protobuf scalarmix decode", iterations, len(scalarmixBytes), func() {
		var decoded personpb.ScalarMix
		if err := unmarshalOptions.Unmarshal(scalarmixBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf textbytes encode", iterations, len(textbytesBytes), func() {
		out, err := proto.Marshal(textbytes)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	textbytesBuf := make([]byte, 0, len(textbytesBytes))
	runTimed("go protobuf textbytes encode reuse", iterations, len(textbytesBytes), func() {
		var err error
		textbytesBuf, err = marshalOptions.MarshalAppend(textbytesBuf[:0], textbytes)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf textbytes decode", iterations, len(textbytesBytes), func() {
		var decoded personpb.TextBytes
		if err := unmarshalOptions.Unmarshal(textbytesBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf largebytes encode", iterations, len(largebytesBytes), func() {
		out, err := proto.Marshal(largebytes)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	largebytesBuf := make([]byte, 0, len(largebytesBytes))
	runTimed("go protobuf largebytes encode reuse", iterations, len(largebytesBytes), func() {
		var err error
		largebytesBuf, err = marshalOptions.MarshalAppend(largebytesBuf[:0], largebytes)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf largebytes decode", iterations, len(largebytesBytes), func() {
		var decoded personpb.LargeBytes
		if err := unmarshalOptions.Unmarshal(largebytesBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf presencemix encode", iterations, len(presencemixBytes), func() {
		out, err := proto.Marshal(presencemix)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	presencemixBuf := make([]byte, 0, len(presencemixBytes))
	runTimed("go protobuf presencemix encode reuse", iterations, len(presencemixBytes), func() {
		var err error
		presencemixBuf, err = marshalOptions.MarshalAppend(presencemixBuf[:0], presencemix)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf presencemix decode", iterations, len(presencemixBytes), func() {
		var decoded personpb.PresenceMix
		if err := unmarshalOptions.Unmarshal(presencemixBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf complex encode", iterations, len(complexBytes), func() {
		out, err := proto.Marshal(complex)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	complexBuf := make([]byte, 0, len(complexBytes))
	runTimed("go protobuf complex encode reuse", iterations, len(complexBytes), func() {
		var err error
		complexBuf, err = marshalOptions.MarshalAppend(complexBuf[:0], complex)
		if err != nil {
			panic(err)
		}
	}).print()

	complexDeterministicBuf := make([]byte, 0, len(complexBytes))
	runTimed("go protobuf complex deterministic binary encode reuse", iterations, len(complexBytes), func() {
		var err error
		complexDeterministicBuf, err = deterministicOptions.MarshalAppend(complexDeterministicBuf[:0], complex)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf complex decode", iterations, len(complexBytes), func() {
		var decoded personpb.Complex
		if err := unmarshalOptions.Unmarshal(complexBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	jsonUnmarshalOptions := protojson.UnmarshalOptions{}
	textUnmarshalOptions := prototext.UnmarshalOptions{}

	runTimed("go protobuf complex JSON stringify", iterations, len(complexJSONBytes), func() {
		out, err := protojson.Marshal(complex)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	runTimed("go protobuf complex JSON parse", iterations, len(complexJSONBytes), func() {
		var decoded personpb.Complex
		if err := jsonUnmarshalOptions.Unmarshal(complexJSONBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf complex TextFormat format", iterations, len(complexTextBytes), func() {
		out, err := prototext.Marshal(complex)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	runTimed("go protobuf complex TextFormat parse", iterations, len(complexTextBytes), func() {
		var decoded personpb.Complex
		if err := textUnmarshalOptions.Unmarshal(complexTextBytes, &decoded); err != nil {
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

	runTimed("go protobuf sfixed32 packed encode", iterations, len(sfixedPackedBytes), func() {
		out, err := proto.Marshal(sfixedPacked)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	sfixedPackedBuf := make([]byte, 0, len(sfixedPackedBytes))
	runTimed("go protobuf sfixed32 packed encode reuse", iterations, len(sfixedPackedBytes), func() {
		var err error
		sfixedPackedBuf, err = marshalOptions.MarshalAppend(sfixedPackedBuf[:0], sfixedPacked)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf sfixed32 packed decode", iterations, len(sfixedPackedBytes), func() {
		var decoded personpb.SFixedPacked
		if err := unmarshalOptions.Unmarshal(sfixedPackedBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf sfixed64 packed encode", iterations, len(sfixed64PackedBytes), func() {
		out, err := proto.Marshal(sfixed64Packed)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	sfixed64PackedBuf := make([]byte, 0, len(sfixed64PackedBytes))
	runTimed("go protobuf sfixed64 packed encode reuse", iterations, len(sfixed64PackedBytes), func() {
		var err error
		sfixed64PackedBuf, err = marshalOptions.MarshalAppend(sfixed64PackedBuf[:0], sfixed64Packed)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf sfixed64 packed decode", iterations, len(sfixed64PackedBytes), func() {
		var decoded personpb.SFixed64Packed
		if err := unmarshalOptions.Unmarshal(sfixed64PackedBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf float packed encode", iterations, len(floatPackedBytes), func() {
		out, err := proto.Marshal(floatPacked)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	floatPackedBuf := make([]byte, 0, len(floatPackedBytes))
	runTimed("go protobuf float packed encode reuse", iterations, len(floatPackedBytes), func() {
		var err error
		floatPackedBuf, err = marshalOptions.MarshalAppend(floatPackedBuf[:0], floatPacked)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf float packed decode", iterations, len(floatPackedBytes), func() {
		var decoded personpb.FloatPacked
		if err := unmarshalOptions.Unmarshal(floatPackedBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf double packed encode", iterations, len(doublePackedBytes), func() {
		out, err := proto.Marshal(doublePacked)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	doublePackedBuf := make([]byte, 0, len(doublePackedBytes))
	runTimed("go protobuf double packed encode reuse", iterations, len(doublePackedBytes), func() {
		var err error
		doublePackedBuf, err = marshalOptions.MarshalAppend(doublePackedBuf[:0], doublePacked)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf double packed decode", iterations, len(doublePackedBytes), func() {
		var decoded personpb.DoublePacked
		if err := unmarshalOptions.Unmarshal(doublePackedBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf uint64 packed encode", iterations, len(uint64PackedBytes), func() {
		out, err := proto.Marshal(uint64Packed)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	uint64PackedBuf := make([]byte, 0, len(uint64PackedBytes))
	runTimed("go protobuf uint64 packed encode reuse", iterations, len(uint64PackedBytes), func() {
		var err error
		uint64PackedBuf, err = marshalOptions.MarshalAppend(uint64PackedBuf[:0], uint64Packed)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf uint64 packed decode", iterations, len(uint64PackedBytes), func() {
		var decoded personpb.UInt64Packed
		if err := unmarshalOptions.Unmarshal(uint64PackedBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf uint32 packed encode", iterations, len(uint32PackedBytes), func() {
		out, err := proto.Marshal(uint32Packed)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	uint32PackedBuf := make([]byte, 0, len(uint32PackedBytes))
	runTimed("go protobuf uint32 packed encode reuse", iterations, len(uint32PackedBytes), func() {
		var err error
		uint32PackedBuf, err = marshalOptions.MarshalAppend(uint32PackedBuf[:0], uint32Packed)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf uint32 packed decode", iterations, len(uint32PackedBytes), func() {
		var decoded personpb.UInt32Packed
		if err := unmarshalOptions.Unmarshal(uint32PackedBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf int64 packed encode", iterations, len(int64PackedBytes), func() {
		out, err := proto.Marshal(int64Packed)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	int64PackedBuf := make([]byte, 0, len(int64PackedBytes))
	runTimed("go protobuf int64 packed encode reuse", iterations, len(int64PackedBytes), func() {
		var err error
		int64PackedBuf, err = marshalOptions.MarshalAppend(int64PackedBuf[:0], int64Packed)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf int64 packed decode", iterations, len(int64PackedBytes), func() {
		var decoded personpb.Int64Packed
		if err := unmarshalOptions.Unmarshal(int64PackedBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf sint32 packed encode", iterations, len(sint32PackedBytes), func() {
		out, err := proto.Marshal(sint32Packed)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	sint32PackedBuf := make([]byte, 0, len(sint32PackedBytes))
	runTimed("go protobuf sint32 packed encode reuse", iterations, len(sint32PackedBytes), func() {
		var err error
		sint32PackedBuf, err = marshalOptions.MarshalAppend(sint32PackedBuf[:0], sint32Packed)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf sint32 packed decode", iterations, len(sint32PackedBytes), func() {
		var decoded personpb.SInt32Packed
		if err := unmarshalOptions.Unmarshal(sint32PackedBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf sint64 packed encode", iterations, len(sint64PackedBytes), func() {
		out, err := proto.Marshal(sint64Packed)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	sint64PackedBuf := make([]byte, 0, len(sint64PackedBytes))
	runTimed("go protobuf sint64 packed encode reuse", iterations, len(sint64PackedBytes), func() {
		var err error
		sint64PackedBuf, err = marshalOptions.MarshalAppend(sint64PackedBuf[:0], sint64Packed)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf sint64 packed decode", iterations, len(sint64PackedBytes), func() {
		var decoded personpb.SInt64Packed
		if err := unmarshalOptions.Unmarshal(sint64PackedBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf bool packed encode", iterations, len(boolPackedBytes), func() {
		out, err := proto.Marshal(boolPacked)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	boolPackedBuf := make([]byte, 0, len(boolPackedBytes))
	runTimed("go protobuf bool packed encode reuse", iterations, len(boolPackedBytes), func() {
		var err error
		boolPackedBuf, err = marshalOptions.MarshalAppend(boolPackedBuf[:0], boolPacked)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf bool packed decode", iterations, len(boolPackedBytes), func() {
		var decoded personpb.BoolPacked
		if err := unmarshalOptions.Unmarshal(boolPackedBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf enum packed encode", iterations, len(enumPackedBytes), func() {
		out, err := proto.Marshal(enumPacked)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	enumPackedBuf := make([]byte, 0, len(enumPackedBytes))
	runTimed("go protobuf enum packed encode reuse", iterations, len(enumPackedBytes), func() {
		var err error
		enumPackedBuf, err = marshalOptions.MarshalAppend(enumPackedBuf[:0], enumPacked)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf enum packed decode", iterations, len(enumPackedBytes), func() {
		var decoded personpb.EnumPacked
		if err := unmarshalOptions.Unmarshal(enumPackedBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf large map encode", iterations, len(largeMapBytes), func() {
		out, err := proto.Marshal(largeMap)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	largeMapBuf := make([]byte, 0, len(largeMapBytes))
	runTimed("go protobuf large map encode reuse", iterations, len(largeMapBytes), func() {
		var err error
		largeMapBuf, err = marshalOptions.MarshalAppend(largeMapBuf[:0], largeMap)
		if err != nil {
			panic(err)
		}
	}).print()

	runTimed("go protobuf large map decode", iterations, len(largeMapBytes), func() {
		var decoded personpb.LargeMap
		if err := unmarshalOptions.Unmarshal(largeMapBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()
}
