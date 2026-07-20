package main

import (
	bytespkg "bytes"
	"fmt"
	"math"
	"time"

	"github.com/pbz/bench/personpb"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/encoding/prototext"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/durationpb"
	"google.golang.org/protobuf/types/known/emptypb"
	"google.golang.org/protobuf/types/known/fieldmaskpb"
	"google.golang.org/protobuf/types/known/structpb"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

const benchmarkSamples = 3
const largeMapEntryCount = 1024
const largeMapShuffleMultiplier = 257
const largeMapShuffleIncrement = 911

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

func runProtoJSONPair[T proto.Message](label string, iterations int, payload []byte, value T, newValue func() T, unmarshalOptions protojson.UnmarshalOptions) {
	runTimed("go protobuf "+label+" JSON stringify", iterations, len(payload), func() {
		out, err := protojson.Marshal(value)
		if err != nil {
			panic(err)
		}
		_ = out
	}).print()

	runTimed("go protobuf "+label+" JSON parse", iterations, len(payload), func() {
		decoded := newValue()
		if err := unmarshalOptions.Unmarshal(payload, decoded); err != nil {
			panic(err)
		}
	}).print()
}

func runProtoJSONParseOnly[T proto.Message](label string, iterations int, payload []byte, newValue func() T, unmarshalOptions protojson.UnmarshalOptions) {
	runTimed("go protobuf "+label+" JSON parse", iterations, len(payload), func() {
		decoded := newValue()
		if err := unmarshalOptions.Unmarshal(payload, decoded); err != nil {
			panic(err)
		}
	}).print()
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
	counts := make(map[string]int32, largeMapEntryCount)
	for i := 0; i < largeMapEntryCount; i++ {
		counts[fmt.Sprintf("key-%04d", i)] = int32((i % 4096) + 1)
	}
	return &personpb.LargeMap{Counts: counts}
}

func shuffledLargeMapIndex(i int) int {
	return (i*largeMapShuffleMultiplier + largeMapShuffleIncrement) % largeMapEntryCount
}

func makeShuffledLargeMap() *personpb.LargeMap {
	counts := make(map[string]int32, largeMapEntryCount)
	for i := 0; i < largeMapEntryCount; i++ {
		keyIndex := shuffledLargeMapIndex(i)
		counts[fmt.Sprintf("key-%04d", keyIndex)] = int32((keyIndex % 4096) + 1)
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
	protoNameMarshalOptions := protojson.MarshalOptions{UseProtoNames: true}
	protoNameStringifyJSONBytes, err := protoNameMarshalOptions.Marshal(scalarmix)
	if err != nil {
		panic(err)
	}
	if !bytespkg.Contains(protoNameStringifyJSONBytes, []byte(`"big_delta"`)) ||
		!bytespkg.Contains(protoNameStringifyJSONBytes, []byte(`"signed_fixed"`)) ||
		!bytespkg.Contains(protoNameStringifyJSONBytes, []byte(`"signed_big_fixed"`)) ||
		bytespkg.Contains(protoNameStringifyJSONBytes, []byte(`"bigDelta"`)) {
		panic("unexpected ProtoName JSON stringify result")
	}
	mapKeySurrogateJSONBytes := []byte(`{"counts":{"\ud83d\ude00":9}}`)
	nullFieldsJSONBytes := []byte(`{"id":null,"name":null,"scores":null,"counts":null}`)
	{
		decoded := &personpb.Person{Id: 7, Name: "x", Scores: []int32{1}, Counts: map[string]int32{"red": 2}}
		if err := protojson.Unmarshal(nullFieldsJSONBytes, decoded); err != nil {
			panic(err)
		}
		if decoded.Id != 0 || decoded.Name != "" || len(decoded.Scores) != 0 || len(decoded.Counts) != 0 {
			panic("unexpected NullFields JSON parse result")
		}
	}
	openEnumJSONBytes := []byte(`{"kind":123}`)
	{
		var decoded personpb.ScalarMix
		if err := protojson.Unmarshal(openEnumJSONBytes, &decoded); err != nil {
			panic(err)
		}
		if decoded.Kind != 123 {
			panic("unexpected OpenEnum JSON parse result")
		}
	}
	enumNameJSONBytes := []byte(`{"kind":"BENCH_KIND_BETA"}`)
	{
		var decoded personpb.ScalarMix
		if err := protojson.Unmarshal(enumNameJSONBytes, &decoded); err != nil {
			panic(err)
		}
		if decoded.Kind != personpb.BenchKind_BENCH_KIND_BETA {
			panic("unexpected EnumName JSON parse result")
		}
	}
	protoNameJSONBytes := []byte(`{"big_delta":-321,"signed_fixed":-123,"signed_big_fixed":-456}`)
	{
		var decoded personpb.ScalarMix
		if err := protojson.Unmarshal(protoNameJSONBytes, &decoded); err != nil {
			panic(err)
		}
		if decoded.BigDelta != -321 || decoded.SignedFixed != -123 || decoded.SignedBigFixed != -456 {
			panic("unexpected ProtoName JSON parse result")
		}
	}
	intExponentJSONBytes := []byte(`{"count":1.2345e4,"total":9.87654321e9,"delta":-3.21e2,"bigDelta":-9.876543e6,"checksum":3.21e2,"token":4.096e3,"signedFixed":-1.23456e5,"signedBigFixed":-9.876543e6,"ids":[1e0,1.27e2,1.28e2]}`)
	{
		var decoded personpb.ScalarMix
		if err := protojson.Unmarshal(intExponentJSONBytes, &decoded); err != nil {
			panic(err)
		}
		if decoded.Count != 12345 || decoded.Total != 9_876_543_210 ||
			decoded.Delta != -321 || decoded.BigDelta != -9_876_543 ||
			decoded.Checksum != 321 || decoded.Token != 4096 ||
			decoded.SignedFixed != -123456 || decoded.SignedBigFixed != -9_876_543 ||
			len(decoded.Ids) != 3 || decoded.Ids[0] != 1 || decoded.Ids[1] != 127 || decoded.Ids[2] != 128 {
			panic("unexpected IntExponent JSON parse result")
		}
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
	anyWKT, err := anypb.New(&durationpb.Duration{Seconds: 1, Nanos: 500_000_000})
	if err != nil {
		panic(err)
	}
	anyWKTJSONBytes, err := protojson.Marshal(anyWKT)
	if err != nil {
		panic(err)
	}
	duration := &durationpb.Duration{Seconds: 1, Nanos: 500_000_000}
	durationJSONBytes, err := protojson.Marshal(duration)
	if err != nil {
		panic(err)
	}
	durationEscapeJSONBytes := []byte(`"1\u002e500s"`)
	anyDurationEscapeWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Duration","value":"1\u002e500s"}`)
	plusDurationJSONBytes := []byte(`"+1.500s"`)
	anyPlusDurationWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Duration","value":"+1.500s"}`)
	shortFractionDurationJSONBytes := []byte(`"1.5s"`)
	anyShortFractionDurationWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Duration","value":"1.5s"}`)
	microDuration := &durationpb.Duration{Seconds: 1, Nanos: 120_000}
	microDurationJSONBytes, err := protojson.Marshal(microDuration)
	if err != nil {
		panic(err)
	}
	anyMicroDurationWKT, err := anypb.New(microDuration)
	if err != nil {
		panic(err)
	}
	anyMicroDurationWKTJSONBytes, err := protojson.Marshal(anyMicroDurationWKT)
	if err != nil {
		panic(err)
	}
	nanoDuration := &durationpb.Duration{Seconds: 1, Nanos: 123_456_789}
	nanoDurationJSONBytes, err := protojson.Marshal(nanoDuration)
	if err != nil {
		panic(err)
	}
	anyNanoDurationWKT, err := anypb.New(nanoDuration)
	if err != nil {
		panic(err)
	}
	anyNanoDurationWKTJSONBytes, err := protojson.Marshal(anyNanoDurationWKT)
	if err != nil {
		panic(err)
	}
	negativeDuration := &durationpb.Duration{Seconds: -1, Nanos: -500_000_000}
	negativeDurationJSONBytes, err := protojson.Marshal(negativeDuration)
	if err != nil {
		panic(err)
	}
	anyNegativeDurationWKT, err := anypb.New(negativeDuration)
	if err != nil {
		panic(err)
	}
	anyNegativeDurationWKTJSONBytes, err := protojson.Marshal(anyNegativeDurationWKT)
	if err != nil {
		panic(err)
	}
	fractionalNegativeDuration := &durationpb.Duration{Nanos: -250_000_000}
	fractionalNegativeDurationJSONBytes, err := protojson.Marshal(fractionalNegativeDuration)
	if err != nil {
		panic(err)
	}
	anyFractionalNegativeDurationWKT, err := anypb.New(fractionalNegativeDuration)
	if err != nil {
		panic(err)
	}
	anyFractionalNegativeDurationWKTJSONBytes, err := protojson.Marshal(anyFractionalNegativeDurationWKT)
	if err != nil {
		panic(err)
	}
	maxDuration := &durationpb.Duration{Seconds: 315_576_000_000}
	maxDurationJSONBytes, err := protojson.Marshal(maxDuration)
	if err != nil {
		panic(err)
	}
	anyMaxDurationWKT, err := anypb.New(maxDuration)
	if err != nil {
		panic(err)
	}
	anyMaxDurationWKTJSONBytes, err := protojson.Marshal(anyMaxDurationWKT)
	if err != nil {
		panic(err)
	}
	minDuration := &durationpb.Duration{Seconds: -315_576_000_000}
	minDurationJSONBytes, err := protojson.Marshal(minDuration)
	if err != nil {
		panic(err)
	}
	anyMinDurationWKT, err := anypb.New(minDuration)
	if err != nil {
		panic(err)
	}
	anyMinDurationWKTJSONBytes, err := protojson.Marshal(anyMinDurationWKT)
	if err != nil {
		panic(err)
	}
	zeroDuration := &durationpb.Duration{}
	zeroDurationJSONBytes, err := protojson.Marshal(zeroDuration)
	if err != nil {
		panic(err)
	}
	anyZeroDurationWKT, err := anypb.New(zeroDuration)
	if err != nil {
		panic(err)
	}
	anyZeroDurationWKTJSONBytes, err := protojson.Marshal(anyZeroDurationWKT)
	if err != nil {
		panic(err)
	}
	fieldMask := &fieldmaskpb.FieldMask{Paths: []string{"foo_bar", "nested.value"}}
	fieldMaskJSONBytes, err := protojson.Marshal(fieldMask)
	if err != nil {
		panic(err)
	}
	anyFieldMaskWKT, err := anypb.New(fieldMask)
	if err != nil {
		panic(err)
	}
	anyFieldMaskWKTJSONBytes, err := protojson.Marshal(anyFieldMaskWKT)
	if err != nil {
		panic(err)
	}
	fieldMaskEscapeJSONBytes := []byte(`"fooBar,\u006eested.value"`)
	anyFieldMaskEscapeWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.FieldMask","value":"fooBar,\u006eested.value"}`)
	emptyFieldMask := &fieldmaskpb.FieldMask{}
	emptyFieldMaskJSONBytes, err := protojson.Marshal(emptyFieldMask)
	if err != nil {
		panic(err)
	}
	anyEmptyFieldMaskWKT, err := anypb.New(emptyFieldMask)
	if err != nil {
		panic(err)
	}
	anyEmptyFieldMaskWKTJSONBytes, err := protojson.Marshal(anyEmptyFieldMaskWKT)
	if err != nil {
		panic(err)
	}
	timestamp := &timestamppb.Timestamp{Seconds: 1_577_836_800, Nanos: 123_000_000}
	timestampJSONBytes, err := protojson.Marshal(timestamp)
	if err != nil {
		panic(err)
	}
	timestampEscapeJSONBytes := []byte(`"2020-01-01T00:00:00\u002e123Z"`)
	anyTimestampEscapeWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Timestamp","value":"2020-01-01T00:00:00\u002e123Z"}`)
	anyTimestampWKT, err := anypb.New(timestamp)
	if err != nil {
		panic(err)
	}
	anyTimestampWKTJSONBytes, err := protojson.Marshal(anyTimestampWKT)
	if err != nil {
		panic(err)
	}
	shortFractionTimestampJSONBytes := []byte(`"2020-01-01T00:00:00.1Z"`)
	anyShortFractionTimestampWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Timestamp","value":"2020-01-01T00:00:00.1Z"}`)
	microTimestamp := &timestamppb.Timestamp{Seconds: 1_577_836_800, Nanos: 123_456_000}
	microTimestampJSONBytes, err := protojson.Marshal(microTimestamp)
	if err != nil {
		panic(err)
	}
	anyMicroTimestampWKT, err := anypb.New(microTimestamp)
	if err != nil {
		panic(err)
	}
	anyMicroTimestampWKTJSONBytes, err := protojson.Marshal(anyMicroTimestampWKT)
	if err != nil {
		panic(err)
	}
	nanoTimestamp := &timestamppb.Timestamp{Seconds: 1_577_836_800, Nanos: 123_456_789}
	nanoTimestampJSONBytes, err := protojson.Marshal(nanoTimestamp)
	if err != nil {
		panic(err)
	}
	anyNanoTimestampWKT, err := anypb.New(nanoTimestamp)
	if err != nil {
		panic(err)
	}
	anyNanoTimestampWKTJSONBytes, err := protojson.Marshal(anyNanoTimestampWKT)
	if err != nil {
		panic(err)
	}
	offsetTimestampJSONBytes := []byte(`"2020-01-01T03:00:00.123456+03:00"`)
	anyOffsetTimestampWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Timestamp","value":"2020-01-01T03:00:00.123456+03:00"}`)
	preEpochTimestamp := &timestamppb.Timestamp{Seconds: -1}
	preEpochTimestampJSONBytes, err := protojson.Marshal(preEpochTimestamp)
	if err != nil {
		panic(err)
	}
	anyPreEpochTimestampWKT, err := anypb.New(preEpochTimestamp)
	if err != nil {
		panic(err)
	}
	anyPreEpochTimestampWKTJSONBytes, err := protojson.Marshal(anyPreEpochTimestampWKT)
	if err != nil {
		panic(err)
	}
	maxTimestamp := &timestamppb.Timestamp{Seconds: 253_402_300_799, Nanos: 999_999_999}
	maxTimestampJSONBytes, err := protojson.Marshal(maxTimestamp)
	if err != nil {
		panic(err)
	}
	anyMaxTimestampWKT, err := anypb.New(maxTimestamp)
	if err != nil {
		panic(err)
	}
	anyMaxTimestampWKTJSONBytes, err := protojson.Marshal(anyMaxTimestampWKT)
	if err != nil {
		panic(err)
	}
	minTimestamp := &timestamppb.Timestamp{Seconds: -62_135_596_800}
	minTimestampJSONBytes, err := protojson.Marshal(minTimestamp)
	if err != nil {
		panic(err)
	}
	anyMinTimestampWKT, err := anypb.New(minTimestamp)
	if err != nil {
		panic(err)
	}
	anyMinTimestampWKTJSONBytes, err := protojson.Marshal(anyMinTimestampWKT)
	if err != nil {
		panic(err)
	}
	emptyValue := &emptypb.Empty{}
	emptyJSONBytes, err := protojson.Marshal(emptyValue)
	if err != nil {
		panic(err)
	}
	anyEmptyWKT, err := anypb.New(emptyValue)
	if err != nil {
		panic(err)
	}
	anyEmptyWKTJSONBytes, err := protojson.Marshal(anyEmptyWKT)
	if err != nil {
		panic(err)
	}
	structValue := &structpb.Struct{Fields: map[string]*structpb.Value{
		"enabled": structpb.NewBoolValue(true),
		"items": structpb.NewListValue(&structpb.ListValue{Values: []*structpb.Value{
			structpb.NewNullValue(),
			structpb.NewStringValue("zig"),
		}}),
		"meta": structpb.NewStructValue(&structpb.Struct{Fields: map[string]*structpb.Value{
			"score": structpb.NewNumberValue(1.5),
		}}),
	}}
	structJSONBytes, err := protojson.Marshal(structValue)
	if err != nil {
		panic(err)
	}
	structEscapeJSONBytes := []byte(`{"\u0065nabled":true,"items":[null,"\u007aig"],"meta":{"score":1.5}}`)
	structNumberExponentJSONBytes := []byte(`{"enabled":true,"items":[null,"zig"],"meta":{"score":1.5e0}}`)
	structSurrogateJSONBytes := []byte(`{"emoji":"\ud83d\ude00"}`)
	structKeySurrogateJSONBytes := []byte(`{"\ud83d\ude00":"ok"}`)
	anyStructEscapeWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Struct","value":{"\u0065nabled":true,"items":[null,"\u007aig"],"meta":{"score":1.5}}}`)
	anyStructNumberExponentWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Struct","value":{"enabled":true,"items":[null,"zig"],"meta":{"score":1.5e0}}}`)
	anyStructSurrogateWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Struct","value":{"emoji":"\ud83d\ude00"}}`)
	anyStructKeySurrogateWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Struct","value":{"\ud83d\ude00":"ok"}}`)
	anyStructWKT, err := anypb.New(structValue)
	if err != nil {
		panic(err)
	}
	anyStructWKTJSONBytes, err := protojson.Marshal(anyStructWKT)
	if err != nil {
		panic(err)
	}
	emptyStructValue := &structpb.Struct{}
	emptyStructJSONBytes, err := protojson.Marshal(emptyStructValue)
	if err != nil {
		panic(err)
	}
	anyEmptyStructWKT, err := anypb.New(emptyStructValue)
	if err != nil {
		panic(err)
	}
	anyEmptyStructWKTJSONBytes, err := protojson.Marshal(anyEmptyStructWKT)
	if err != nil {
		panic(err)
	}
	valueValue := structpb.NewStructValue(structValue)
	valueJSONBytes, err := protojson.Marshal(valueValue)
	if err != nil {
		panic(err)
	}
	valueEscapeJSONBytes := structEscapeJSONBytes
	valueNumberExponentJSONBytes := structNumberExponentJSONBytes
	valueSurrogateJSONBytes := structSurrogateJSONBytes
	valueKeySurrogateJSONBytes := structKeySurrogateJSONBytes
	anyValueEscapeWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Value","value":{"\u0065nabled":true,"items":[null,"\u007aig"],"meta":{"score":1.5}}}`)
	anyValueNumberExponentWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Value","value":{"enabled":true,"items":[null,"zig"],"meta":{"score":1.5e0}}}`)
	anyValueSurrogateWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Value","value":{"emoji":"\ud83d\ude00"}}`)
	anyValueKeySurrogateWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Value","value":{"\ud83d\ude00":"ok"}}`)
	anyValueWKT, err := anypb.New(valueValue)
	if err != nil {
		panic(err)
	}
	anyValueWKTJSONBytes, err := protojson.Marshal(anyValueWKT)
	if err != nil {
		panic(err)
	}
	nullValueValue := structpb.NewNullValue()
	nullValueJSONBytes, err := protojson.Marshal(nullValueValue)
	if err != nil {
		panic(err)
	}
	anyNullValueWKT, err := anypb.New(nullValueValue)
	if err != nil {
		panic(err)
	}
	anyNullValueWKTJSONBytes, err := protojson.Marshal(anyNullValueWKT)
	if err != nil {
		panic(err)
	}
	stringScalarValue := structpb.NewStringValue("zig")
	stringScalarValueJSONBytes, err := protojson.Marshal(stringScalarValue)
	if err != nil {
		panic(err)
	}
	stringScalarValueEscapeJSONBytes := []byte(`"\u007aig"`)
	stringScalarValueSurrogateJSONBytes := []byte(`"\ud83d\ude00"`)
	anyStringScalarValueEscapeWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Value","value":"\u007aig"}`)
	anyStringScalarValueSurrogateWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Value","value":"\ud83d\ude00"}`)
	anyStringScalarValueWKT, err := anypb.New(stringScalarValue)
	if err != nil {
		panic(err)
	}
	anyStringScalarValueWKTJSONBytes, err := protojson.Marshal(anyStringScalarValueWKT)
	if err != nil {
		panic(err)
	}
	emptyStringScalarValue := structpb.NewStringValue("")
	emptyStringScalarValueJSONBytes, err := protojson.Marshal(emptyStringScalarValue)
	if err != nil {
		panic(err)
	}
	anyEmptyStringScalarValueWKT, err := anypb.New(emptyStringScalarValue)
	if err != nil {
		panic(err)
	}
	anyEmptyStringScalarValueWKTJSONBytes, err := protojson.Marshal(anyEmptyStringScalarValueWKT)
	if err != nil {
		panic(err)
	}
	numberValue := structpb.NewNumberValue(1.5)
	numberValueJSONBytes, err := protojson.Marshal(numberValue)
	if err != nil {
		panic(err)
	}
	numberValueExponentJSONBytes := []byte(`1.5e0`)
	anyNumberValueWKT, err := anypb.New(numberValue)
	if err != nil {
		panic(err)
	}
	anyNumberValueWKTJSONBytes, err := protojson.Marshal(anyNumberValueWKT)
	if err != nil {
		panic(err)
	}
	anyNumberValueExponentWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Value","value":1.5e0}`)
	negativeNumberValue := structpb.NewNumberValue(-1.5)
	negativeNumberValueJSONBytes, err := protojson.Marshal(negativeNumberValue)
	if err != nil {
		panic(err)
	}
	anyNegativeNumberValueWKT, err := anypb.New(negativeNumberValue)
	if err != nil {
		panic(err)
	}
	anyNegativeNumberValueWKTJSONBytes, err := protojson.Marshal(anyNegativeNumberValueWKT)
	if err != nil {
		panic(err)
	}
	zeroNumberValue := structpb.NewNumberValue(0)
	zeroNumberValueJSONBytes, err := protojson.Marshal(zeroNumberValue)
	if err != nil {
		panic(err)
	}
	anyZeroNumberValueWKT, err := anypb.New(zeroNumberValue)
	if err != nil {
		panic(err)
	}
	anyZeroNumberValueWKTJSONBytes, err := protojson.Marshal(anyZeroNumberValueWKT)
	if err != nil {
		panic(err)
	}
	boolScalarValue := structpb.NewBoolValue(true)
	boolScalarValueJSONBytes, err := protojson.Marshal(boolScalarValue)
	if err != nil {
		panic(err)
	}
	anyBoolScalarValueWKT, err := anypb.New(boolScalarValue)
	if err != nil {
		panic(err)
	}
	anyBoolScalarValueWKTJSONBytes, err := protojson.Marshal(anyBoolScalarValueWKT)
	if err != nil {
		panic(err)
	}
	falseBoolScalarValue := structpb.NewBoolValue(false)
	falseBoolScalarValueJSONBytes, err := protojson.Marshal(falseBoolScalarValue)
	if err != nil {
		panic(err)
	}
	anyFalseBoolScalarValueWKT, err := anypb.New(falseBoolScalarValue)
	if err != nil {
		panic(err)
	}
	anyFalseBoolScalarValueWKTJSONBytes, err := protojson.Marshal(anyFalseBoolScalarValueWKT)
	if err != nil {
		panic(err)
	}
	listValue := &structpb.ListValue{Values: []*structpb.Value{
		structpb.NewNullValue(),
		structpb.NewStringValue("zig"),
		structpb.NewNumberValue(1.5),
		structpb.NewBoolValue(true),
		structpb.NewStructValue(&structpb.Struct{Fields: map[string]*structpb.Value{
			"nested": structpb.NewStringValue("value"),
		}}),
	}}
	listValueJSONBytes, err := protojson.Marshal(listValue)
	if err != nil {
		panic(err)
	}
	listValueEscapeJSONBytes := []byte(`[null,"\u007aig",1.5,true,{"\u006eested":"value"}]`)
	listValueSurrogateJSONBytes := []byte(`["\ud83d\ude00"]`)
	listKindValue := structpb.NewListValue(listValue)
	listKindValueJSONBytes, err := protojson.Marshal(listKindValue)
	if err != nil {
		panic(err)
	}
	listKindValueEscapeJSONBytes := listValueEscapeJSONBytes
	listKindValueSurrogateJSONBytes := listValueSurrogateJSONBytes
	anyListKindValueWKT, err := anypb.New(listKindValue)
	if err != nil {
		panic(err)
	}
	anyListKindValueWKTJSONBytes, err := protojson.Marshal(anyListKindValueWKT)
	if err != nil {
		panic(err)
	}
	anyListKindValueEscapeWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Value","value":[null,"\u007aig",1.5,true,{"\u006eested":"value"}]}`)
	anyListKindValueSurrogateWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Value","value":["\ud83d\ude00"]}`)
	emptyStructKindValue := structpb.NewStructValue(emptyStructValue)
	emptyStructKindValueJSONBytes, err := protojson.Marshal(emptyStructKindValue)
	if err != nil {
		panic(err)
	}
	anyEmptyStructKindValueWKT, err := anypb.New(emptyStructKindValue)
	if err != nil {
		panic(err)
	}
	anyEmptyStructKindValueWKTJSONBytes, err := protojson.Marshal(anyEmptyStructKindValueWKT)
	if err != nil {
		panic(err)
	}
	emptyListValue := &structpb.ListValue{}
	emptyListValueJSONBytes, err := protojson.Marshal(emptyListValue)
	if err != nil {
		panic(err)
	}
	emptyListKindValue := structpb.NewListValue(emptyListValue)
	emptyListKindValueJSONBytes, err := protojson.Marshal(emptyListKindValue)
	if err != nil {
		panic(err)
	}
	anyEmptyListKindValueWKT, err := anypb.New(emptyListKindValue)
	if err != nil {
		panic(err)
	}
	anyEmptyListKindValueWKTJSONBytes, err := protojson.Marshal(anyEmptyListKindValueWKT)
	if err != nil {
		panic(err)
	}
	doubleValue := wrapperspb.Double(3.25)
	doubleValueJSONBytes, err := protojson.Marshal(doubleValue)
	if err != nil {
		panic(err)
	}
	doubleValueStringJSONBytes := []byte(`"3.25"`)
	doubleValueExponentJSONBytes := []byte(`3.25e0`)
	anyDoubleValueWKT, err := anypb.New(doubleValue)
	if err != nil {
		panic(err)
	}
	anyDoubleValueWKTJSONBytes, err := protojson.Marshal(anyDoubleValueWKT)
	if err != nil {
		panic(err)
	}
	anyDoubleValueStringWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.DoubleValue","value":"3.25"}`)
	anyDoubleValueExponentWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.DoubleValue","value":3.25e0}`)
	negativeDoubleValue := wrapperspb.Double(-3.25)
	negativeDoubleValueJSONBytes, err := protojson.Marshal(negativeDoubleValue)
	if err != nil {
		panic(err)
	}
	anyNegativeDoubleValueWKT, err := anypb.New(negativeDoubleValue)
	if err != nil {
		panic(err)
	}
	anyNegativeDoubleValueWKTJSONBytes, err := protojson.Marshal(anyNegativeDoubleValueWKT)
	if err != nil {
		panic(err)
	}
	zeroDoubleValue := wrapperspb.Double(0)
	zeroDoubleValueJSONBytes, err := protojson.Marshal(zeroDoubleValue)
	if err != nil {
		panic(err)
	}
	anyZeroDoubleValueWKT, err := anypb.New(zeroDoubleValue)
	if err != nil {
		panic(err)
	}
	anyZeroDoubleValueWKTJSONBytes, err := protojson.Marshal(anyZeroDoubleValueWKT)
	if err != nil {
		panic(err)
	}
	doubleValueNaN := wrapperspb.Double(math.NaN())
	doubleValueNaNJSONBytes, err := protojson.Marshal(doubleValueNaN)
	if err != nil {
		panic(err)
	}
	anyDoubleValueNaNWKT, err := anypb.New(doubleValueNaN)
	if err != nil {
		panic(err)
	}
	anyDoubleValueNaNWKTJSONBytes, err := protojson.Marshal(anyDoubleValueNaNWKT)
	if err != nil {
		panic(err)
	}
	doubleValueInf := wrapperspb.Double(math.Inf(1))
	doubleValueInfJSONBytes, err := protojson.Marshal(doubleValueInf)
	if err != nil {
		panic(err)
	}
	anyDoubleValueInfWKT, err := anypb.New(doubleValueInf)
	if err != nil {
		panic(err)
	}
	anyDoubleValueInfWKTJSONBytes, err := protojson.Marshal(anyDoubleValueInfWKT)
	if err != nil {
		panic(err)
	}
	doubleValueNegInf := wrapperspb.Double(math.Inf(-1))
	doubleValueNegInfJSONBytes, err := protojson.Marshal(doubleValueNegInf)
	if err != nil {
		panic(err)
	}
	anyDoubleValueNegInfWKT, err := anypb.New(doubleValueNegInf)
	if err != nil {
		panic(err)
	}
	anyDoubleValueNegInfWKTJSONBytes, err := protojson.Marshal(anyDoubleValueNegInfWKT)
	if err != nil {
		panic(err)
	}
	floatValue := wrapperspb.Float(1.5)
	floatValueJSONBytes, err := protojson.Marshal(floatValue)
	if err != nil {
		panic(err)
	}
	floatValueStringJSONBytes := []byte(`"1.5"`)
	floatValueExponentJSONBytes := []byte(`1.5e0`)
	anyFloatValueWKT, err := anypb.New(floatValue)
	if err != nil {
		panic(err)
	}
	anyFloatValueWKTJSONBytes, err := protojson.Marshal(anyFloatValueWKT)
	if err != nil {
		panic(err)
	}
	anyFloatValueStringWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.FloatValue","value":"1.5"}`)
	anyFloatValueExponentWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.FloatValue","value":1.5e0}`)
	negativeFloatValue := wrapperspb.Float(-1.5)
	negativeFloatValueJSONBytes, err := protojson.Marshal(negativeFloatValue)
	if err != nil {
		panic(err)
	}
	anyNegativeFloatValueWKT, err := anypb.New(negativeFloatValue)
	if err != nil {
		panic(err)
	}
	anyNegativeFloatValueWKTJSONBytes, err := protojson.Marshal(anyNegativeFloatValueWKT)
	if err != nil {
		panic(err)
	}
	zeroFloatValue := wrapperspb.Float(0)
	zeroFloatValueJSONBytes, err := protojson.Marshal(zeroFloatValue)
	if err != nil {
		panic(err)
	}
	anyZeroFloatValueWKT, err := anypb.New(zeroFloatValue)
	if err != nil {
		panic(err)
	}
	anyZeroFloatValueWKTJSONBytes, err := protojson.Marshal(anyZeroFloatValueWKT)
	if err != nil {
		panic(err)
	}
	floatValueNaN := wrapperspb.Float(float32(math.NaN()))
	floatValueNaNJSONBytes, err := protojson.Marshal(floatValueNaN)
	if err != nil {
		panic(err)
	}
	anyFloatValueNaNWKT, err := anypb.New(floatValueNaN)
	if err != nil {
		panic(err)
	}
	anyFloatValueNaNWKTJSONBytes, err := protojson.Marshal(anyFloatValueNaNWKT)
	if err != nil {
		panic(err)
	}
	floatValueInf := wrapperspb.Float(float32(math.Inf(1)))
	floatValueInfJSONBytes, err := protojson.Marshal(floatValueInf)
	if err != nil {
		panic(err)
	}
	anyFloatValueInfWKT, err := anypb.New(floatValueInf)
	if err != nil {
		panic(err)
	}
	anyFloatValueInfWKTJSONBytes, err := protojson.Marshal(anyFloatValueInfWKT)
	if err != nil {
		panic(err)
	}
	floatValueNegInf := wrapperspb.Float(float32(math.Inf(-1)))
	floatValueNegInfJSONBytes, err := protojson.Marshal(floatValueNegInf)
	if err != nil {
		panic(err)
	}
	anyFloatValueNegInfWKT, err := anypb.New(floatValueNegInf)
	if err != nil {
		panic(err)
	}
	anyFloatValueNegInfWKTJSONBytes, err := protojson.Marshal(anyFloatValueNegInfWKT)
	if err != nil {
		panic(err)
	}
	int64Value := wrapperspb.Int64(9_007_199_254_740_993)
	int64ValueJSONBytes, err := protojson.Marshal(int64Value)
	if err != nil {
		panic(err)
	}
	int64ValueNumberJSONBytes := []byte(`9007199254740993`)
	int64ValueExponentJSONBytes := []byte(`1.2345e4`)
	anyInt64ValueWKT, err := anypb.New(int64Value)
	if err != nil {
		panic(err)
	}
	anyInt64ValueWKTJSONBytes, err := protojson.Marshal(anyInt64ValueWKT)
	if err != nil {
		panic(err)
	}
	anyInt64ValueNumberWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":9007199254740993}`)
	anyInt64ValueExponentWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":1.2345e4}`)
	zeroInt64Value := wrapperspb.Int64(0)
	zeroInt64ValueJSONBytes, err := protojson.Marshal(zeroInt64Value)
	if err != nil {
		panic(err)
	}
	anyZeroInt64ValueWKT, err := anypb.New(zeroInt64Value)
	if err != nil {
		panic(err)
	}
	anyZeroInt64ValueWKTJSONBytes, err := protojson.Marshal(anyZeroInt64ValueWKT)
	if err != nil {
		panic(err)
	}
	negativeInt64Value := wrapperspb.Int64(-9_007_199_254_740_993)
	negativeInt64ValueJSONBytes, err := protojson.Marshal(negativeInt64Value)
	if err != nil {
		panic(err)
	}
	anyNegativeInt64ValueWKT, err := anypb.New(negativeInt64Value)
	if err != nil {
		panic(err)
	}
	anyNegativeInt64ValueWKTJSONBytes, err := protojson.Marshal(anyNegativeInt64ValueWKT)
	if err != nil {
		panic(err)
	}
	minInt64Value := wrapperspb.Int64(-9_223_372_036_854_775_808)
	minInt64ValueJSONBytes, err := protojson.Marshal(minInt64Value)
	if err != nil {
		panic(err)
	}
	anyMinInt64ValueWKT, err := anypb.New(minInt64Value)
	if err != nil {
		panic(err)
	}
	anyMinInt64ValueWKTJSONBytes, err := protojson.Marshal(anyMinInt64ValueWKT)
	if err != nil {
		panic(err)
	}
	maxInt64Value := wrapperspb.Int64(9_223_372_036_854_775_807)
	maxInt64ValueJSONBytes, err := protojson.Marshal(maxInt64Value)
	if err != nil {
		panic(err)
	}
	anyMaxInt64ValueWKT, err := anypb.New(maxInt64Value)
	if err != nil {
		panic(err)
	}
	anyMaxInt64ValueWKTJSONBytes, err := protojson.Marshal(anyMaxInt64ValueWKT)
	if err != nil {
		panic(err)
	}
	uint64Value := wrapperspb.UInt64(9_007_199_254_740_993)
	uint64ValueJSONBytes, err := protojson.Marshal(uint64Value)
	if err != nil {
		panic(err)
	}
	uint64ValueNumberJSONBytes := []byte(`9007199254740993`)
	uint64ValueExponentJSONBytes := []byte(`1.2345e4`)
	anyUInt64ValueWKT, err := anypb.New(uint64Value)
	if err != nil {
		panic(err)
	}
	anyUInt64ValueWKTJSONBytes, err := protojson.Marshal(anyUInt64ValueWKT)
	if err != nil {
		panic(err)
	}
	anyUInt64ValueNumberWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.UInt64Value","value":9007199254740993}`)
	anyUInt64ValueExponentWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.UInt64Value","value":1.2345e4}`)
	zeroUInt64Value := wrapperspb.UInt64(0)
	zeroUInt64ValueJSONBytes, err := protojson.Marshal(zeroUInt64Value)
	if err != nil {
		panic(err)
	}
	anyZeroUInt64ValueWKT, err := anypb.New(zeroUInt64Value)
	if err != nil {
		panic(err)
	}
	anyZeroUInt64ValueWKTJSONBytes, err := protojson.Marshal(anyZeroUInt64ValueWKT)
	if err != nil {
		panic(err)
	}
	maxUInt64Value := wrapperspb.UInt64(^uint64(0))
	maxUInt64ValueJSONBytes, err := protojson.Marshal(maxUInt64Value)
	if err != nil {
		panic(err)
	}
	anyMaxUInt64ValueWKT, err := anypb.New(maxUInt64Value)
	if err != nil {
		panic(err)
	}
	anyMaxUInt64ValueWKTJSONBytes, err := protojson.Marshal(anyMaxUInt64ValueWKT)
	if err != nil {
		panic(err)
	}
	int32Value := wrapperspb.Int32(12345)
	int32ValueJSONBytes, err := protojson.Marshal(int32Value)
	if err != nil {
		panic(err)
	}
	int32ValueStringJSONBytes := []byte(`"12345"`)
	int32ValueExponentJSONBytes := []byte(`1.2345e4`)
	anyInt32ValueWKT, err := anypb.New(int32Value)
	if err != nil {
		panic(err)
	}
	anyInt32ValueWKTJSONBytes, err := protojson.Marshal(anyInt32ValueWKT)
	if err != nil {
		panic(err)
	}
	anyInt32ValueStringWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Int32Value","value":"12345"}`)
	anyInt32ValueExponentWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.Int32Value","value":1.2345e4}`)
	zeroInt32Value := wrapperspb.Int32(0)
	zeroInt32ValueJSONBytes, err := protojson.Marshal(zeroInt32Value)
	if err != nil {
		panic(err)
	}
	anyZeroInt32ValueWKT, err := anypb.New(zeroInt32Value)
	if err != nil {
		panic(err)
	}
	anyZeroInt32ValueWKTJSONBytes, err := protojson.Marshal(anyZeroInt32ValueWKT)
	if err != nil {
		panic(err)
	}
	negativeInt32Value := wrapperspb.Int32(-12345)
	negativeInt32ValueJSONBytes, err := protojson.Marshal(negativeInt32Value)
	if err != nil {
		panic(err)
	}
	anyNegativeInt32ValueWKT, err := anypb.New(negativeInt32Value)
	if err != nil {
		panic(err)
	}
	anyNegativeInt32ValueWKTJSONBytes, err := protojson.Marshal(anyNegativeInt32ValueWKT)
	if err != nil {
		panic(err)
	}
	minInt32Value := wrapperspb.Int32(-2_147_483_648)
	minInt32ValueJSONBytes, err := protojson.Marshal(minInt32Value)
	if err != nil {
		panic(err)
	}
	anyMinInt32ValueWKT, err := anypb.New(minInt32Value)
	if err != nil {
		panic(err)
	}
	anyMinInt32ValueWKTJSONBytes, err := protojson.Marshal(anyMinInt32ValueWKT)
	if err != nil {
		panic(err)
	}
	maxInt32Value := wrapperspb.Int32(2_147_483_647)
	maxInt32ValueJSONBytes, err := protojson.Marshal(maxInt32Value)
	if err != nil {
		panic(err)
	}
	anyMaxInt32ValueWKT, err := anypb.New(maxInt32Value)
	if err != nil {
		panic(err)
	}
	anyMaxInt32ValueWKTJSONBytes, err := protojson.Marshal(anyMaxInt32ValueWKT)
	if err != nil {
		panic(err)
	}
	uint32Value := wrapperspb.UInt32(12345)
	uint32ValueJSONBytes, err := protojson.Marshal(uint32Value)
	if err != nil {
		panic(err)
	}
	uint32ValueStringJSONBytes := []byte(`"12345"`)
	uint32ValueExponentJSONBytes := []byte(`1.2345e4`)
	anyUInt32ValueWKT, err := anypb.New(uint32Value)
	if err != nil {
		panic(err)
	}
	anyUInt32ValueWKTJSONBytes, err := protojson.Marshal(anyUInt32ValueWKT)
	if err != nil {
		panic(err)
	}
	anyUInt32ValueStringWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.UInt32Value","value":"12345"}`)
	anyUInt32ValueExponentWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.UInt32Value","value":1.2345e4}`)
	zeroUInt32Value := wrapperspb.UInt32(0)
	zeroUInt32ValueJSONBytes, err := protojson.Marshal(zeroUInt32Value)
	if err != nil {
		panic(err)
	}
	anyZeroUInt32ValueWKT, err := anypb.New(zeroUInt32Value)
	if err != nil {
		panic(err)
	}
	anyZeroUInt32ValueWKTJSONBytes, err := protojson.Marshal(anyZeroUInt32ValueWKT)
	if err != nil {
		panic(err)
	}
	maxUInt32Value := wrapperspb.UInt32(^uint32(0))
	maxUInt32ValueJSONBytes, err := protojson.Marshal(maxUInt32Value)
	if err != nil {
		panic(err)
	}
	anyMaxUInt32ValueWKT, err := anypb.New(maxUInt32Value)
	if err != nil {
		panic(err)
	}
	anyMaxUInt32ValueWKTJSONBytes, err := protojson.Marshal(anyMaxUInt32ValueWKT)
	if err != nil {
		panic(err)
	}
	boolValue := wrapperspb.Bool(true)
	boolValueJSONBytes, err := protojson.Marshal(boolValue)
	if err != nil {
		panic(err)
	}
	anyBoolValueWKT, err := anypb.New(boolValue)
	if err != nil {
		panic(err)
	}
	anyBoolValueWKTJSONBytes, err := protojson.Marshal(anyBoolValueWKT)
	if err != nil {
		panic(err)
	}
	falseBoolValue := wrapperspb.Bool(false)
	falseBoolValueJSONBytes, err := protojson.Marshal(falseBoolValue)
	if err != nil {
		panic(err)
	}
	anyFalseBoolValueWKT, err := anypb.New(falseBoolValue)
	if err != nil {
		panic(err)
	}
	anyFalseBoolValueWKTJSONBytes, err := protojson.Marshal(anyFalseBoolValueWKT)
	if err != nil {
		panic(err)
	}
	stringValue := wrapperspb.String("hello")
	stringValueJSONBytes, err := protojson.Marshal(stringValue)
	if err != nil {
		panic(err)
	}
	anyStringValueWKT, err := anypb.New(stringValue)
	if err != nil {
		panic(err)
	}
	anyStringValueWKTJSONBytes, err := protojson.Marshal(anyStringValueWKT)
	if err != nil {
		panic(err)
	}
	stringValueEscapeJSONBytes := []byte(`"\u0068ello"`)
	stringValueSurrogateJSONBytes := []byte(`"\ud83d\ude00"`)
	anyStringValueEscapeWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.StringValue","value":"\u0068ello"}`)
	anyStringValueSurrogateWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.StringValue","value":"\ud83d\ude00"}`)
	emptyStringValue := wrapperspb.String("")
	emptyStringValueJSONBytes, err := protojson.Marshal(emptyStringValue)
	if err != nil {
		panic(err)
	}
	anyEmptyStringValueWKT, err := anypb.New(emptyStringValue)
	if err != nil {
		panic(err)
	}
	anyEmptyStringValueWKTJSONBytes, err := protojson.Marshal(anyEmptyStringValueWKT)
	if err != nil {
		panic(err)
	}
	nestedAnyWKT, err := anypb.New(anyStringValueWKT)
	if err != nil {
		panic(err)
	}
	nestedAnyWKTJSONBytes, err := protojson.Marshal(nestedAnyWKT)
	if err != nil {
		panic(err)
	}
	bytesValue := wrapperspb.Bytes([]byte("hi"))
	bytesValueJSONBytes, err := protojson.Marshal(bytesValue)
	if err != nil {
		panic(err)
	}
	anyBytesValueWKT, err := anypb.New(bytesValue)
	if err != nil {
		panic(err)
	}
	anyBytesValueWKTJSONBytes, err := protojson.Marshal(anyBytesValueWKT)
	if err != nil {
		panic(err)
	}
	bytesValueURLJSONBytes := []byte(`"-_8"`)
	bytesValueStandardBase64JSONBytes := []byte(`"+/8"`)
	bytesValueUnpaddedJSONBytes := []byte(`"aGk"`)
	anyBytesValueURLWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.BytesValue","value":"-_8"}`)
	anyBytesValueStandardBase64WKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.BytesValue","value":"+/8"}`)
	anyBytesValueUnpaddedWKTJSONBytes := []byte(`{"@type":"type.googleapis.com/google.protobuf.BytesValue","value":"aGk"}`)
	emptyBytesValue := wrapperspb.Bytes([]byte{})
	emptyBytesValueJSONBytes, err := protojson.Marshal(emptyBytesValue)
	if err != nil {
		panic(err)
	}
	anyEmptyBytesValueWKT, err := anypb.New(emptyBytesValue)
	if err != nil {
		panic(err)
	}
	anyEmptyBytesValueWKTJSONBytes, err := protojson.Marshal(anyEmptyBytesValueWKT)
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
	shuffledLargeMap := makeShuffledLargeMap()
	shuffledLargeMapBytes, err := proto.Marshal(shuffledLargeMap)
	if err != nil {
		panic(err)
	}

	fmt.Println("go protobuf benchmark baseline")
	fmt.Printf("payload size: %d\n", len(bytes))
	fmt.Printf("json payload size: %d\n", len(jsonBytes))
	fmt.Printf("proto name stringify json payload size: %d\n", len(protoNameStringifyJSONBytes))
	fmt.Printf("map key-surrogate json payload size: %d\n", len(mapKeySurrogateJSONBytes))
	fmt.Printf("null fields json payload size: %d\n", len(nullFieldsJSONBytes))
	fmt.Printf("open enum json payload size: %d\n", len(openEnumJSONBytes))
	fmt.Printf("enum name json payload size: %d\n", len(enumNameJSONBytes))
	fmt.Printf("proto name json payload size: %d\n", len(protoNameJSONBytes))
	fmt.Printf("int exponent json payload size: %d\n", len(intExponentJSONBytes))
	fmt.Printf("timestamp json payload size: %d\n", len(timestampJSONBytes))
	fmt.Printf("any Timestamp WKT json payload size: %d\n", len(anyTimestampWKTJSONBytes))
	fmt.Printf("timestamp escape json payload size: %d\n", len(timestampEscapeJSONBytes))
	fmt.Printf("any Timestamp Escape WKT json payload size: %d\n", len(anyTimestampEscapeWKTJSONBytes))
	fmt.Printf("short fraction timestamp json payload size: %d\n", len(shortFractionTimestampJSONBytes))
	fmt.Printf("any ShortFraction Timestamp WKT json payload size: %d\n", len(anyShortFractionTimestampWKTJSONBytes))
	fmt.Printf("micro timestamp json payload size: %d\n", len(microTimestampJSONBytes))
	fmt.Printf("any Micro Timestamp WKT json payload size: %d\n", len(anyMicroTimestampWKTJSONBytes))
	fmt.Printf("nano timestamp json payload size: %d\n", len(nanoTimestampJSONBytes))
	fmt.Printf("any Nano Timestamp WKT json payload size: %d\n", len(anyNanoTimestampWKTJSONBytes))
	fmt.Printf("offset timestamp json payload size: %d\n", len(offsetTimestampJSONBytes))
	fmt.Printf("any Offset Timestamp WKT json payload size: %d\n", len(anyOffsetTimestampWKTJSONBytes))
	fmt.Printf("pre-epoch timestamp json payload size: %d\n", len(preEpochTimestampJSONBytes))
	fmt.Printf("any PreEpoch Timestamp WKT json payload size: %d\n", len(anyPreEpochTimestampWKTJSONBytes))
	fmt.Printf("max timestamp json payload size: %d\n", len(maxTimestampJSONBytes))
	fmt.Printf("any Max Timestamp WKT json payload size: %d\n", len(anyMaxTimestampWKTJSONBytes))
	fmt.Printf("min timestamp json payload size: %d\n", len(minTimestampJSONBytes))
	fmt.Printf("any Min Timestamp WKT json payload size: %d\n", len(anyMinTimestampWKTJSONBytes))
	fmt.Printf("duration json payload size: %d\n", len(durationJSONBytes))
	fmt.Printf("duration escape json payload size: %d\n", len(durationEscapeJSONBytes))
	fmt.Printf("any Duration Escape WKT json payload size: %d\n", len(anyDurationEscapeWKTJSONBytes))
	fmt.Printf("plus duration json payload size: %d\n", len(plusDurationJSONBytes))
	fmt.Printf("short fraction duration json payload size: %d\n", len(shortFractionDurationJSONBytes))
	fmt.Printf("micro duration json payload size: %d\n", len(microDurationJSONBytes))
	fmt.Printf("nano duration json payload size: %d\n", len(nanoDurationJSONBytes))
	fmt.Printf("negative duration json payload size: %d\n", len(negativeDurationJSONBytes))
	fmt.Printf("fractional negative duration json payload size: %d\n", len(fractionalNegativeDurationJSONBytes))
	fmt.Printf("max duration json payload size: %d\n", len(maxDurationJSONBytes))
	fmt.Printf("min duration json payload size: %d\n", len(minDurationJSONBytes))
	fmt.Printf("zero duration json payload size: %d\n", len(zeroDurationJSONBytes))
	fmt.Printf("field mask json payload size: %d\n", len(fieldMaskJSONBytes))
	fmt.Printf("any PlusDuration WKT json payload size: %d\n", len(anyPlusDurationWKTJSONBytes))
	fmt.Printf("any ShortFractionDuration WKT json payload size: %d\n", len(anyShortFractionDurationWKTJSONBytes))
	fmt.Printf("any MicroDuration WKT json payload size: %d\n", len(anyMicroDurationWKTJSONBytes))
	fmt.Printf("any NanoDuration WKT json payload size: %d\n", len(anyNanoDurationWKTJSONBytes))
	fmt.Printf("any NegativeDuration WKT json payload size: %d\n", len(anyNegativeDurationWKTJSONBytes))
	fmt.Printf("any FractionalNegativeDuration WKT json payload size: %d\n", len(anyFractionalNegativeDurationWKTJSONBytes))
	fmt.Printf("any MaxDuration WKT json payload size: %d\n", len(anyMaxDurationWKTJSONBytes))
	fmt.Printf("any MinDuration WKT json payload size: %d\n", len(anyMinDurationWKTJSONBytes))
	fmt.Printf("any ZeroDuration WKT json payload size: %d\n", len(anyZeroDurationWKTJSONBytes))
	fmt.Printf("field mask escape json payload size: %d\n", len(fieldMaskEscapeJSONBytes))
	fmt.Printf("any FieldMask Escape WKT json payload size: %d\n", len(anyFieldMaskEscapeWKTJSONBytes))
	fmt.Printf("any FieldMask WKT json payload size: %d\n", len(anyFieldMaskWKTJSONBytes))
	fmt.Printf("empty field mask json payload size: %d\n", len(emptyFieldMaskJSONBytes))
	fmt.Printf("any EmptyFieldMask WKT json payload size: %d\n", len(anyEmptyFieldMaskWKTJSONBytes))
	fmt.Printf("empty json payload size: %d\n", len(emptyJSONBytes))
	fmt.Printf("any Empty WKT json payload size: %d\n", len(anyEmptyWKTJSONBytes))
	fmt.Printf("struct json payload size: %d\n", len(structJSONBytes))
	fmt.Printf("struct escape json payload size: %d\n", len(structEscapeJSONBytes))
	fmt.Printf("struct number exponent json payload size: %d\n", len(structNumberExponentJSONBytes))
	fmt.Printf("struct surrogate json payload size: %d\n", len(structSurrogateJSONBytes))
	fmt.Printf("struct key-surrogate json payload size: %d\n", len(structKeySurrogateJSONBytes))
	fmt.Printf("value json payload size: %d\n", len(valueJSONBytes))
	fmt.Printf("value escape json payload size: %d\n", len(valueEscapeJSONBytes))
	fmt.Printf("value number exponent json payload size: %d\n", len(valueNumberExponentJSONBytes))
	fmt.Printf("value surrogate json payload size: %d\n", len(valueSurrogateJSONBytes))
	fmt.Printf("value key-surrogate json payload size: %d\n", len(valueKeySurrogateJSONBytes))
	fmt.Printf("list value json payload size: %d\n", len(listValueJSONBytes))
	fmt.Printf("list value escape json payload size: %d\n", len(listValueEscapeJSONBytes))
	fmt.Printf("list value surrogate json payload size: %d\n", len(listValueSurrogateJSONBytes))
	fmt.Printf("empty list value json payload size: %d\n", len(emptyListValueJSONBytes))
	fmt.Printf("any Struct WKT json payload size: %d\n", len(anyStructWKTJSONBytes))
	fmt.Printf("any Struct Escape WKT json payload size: %d\n", len(anyStructEscapeWKTJSONBytes))
	fmt.Printf("any Struct NumberExponent WKT json payload size: %d\n", len(anyStructNumberExponentWKTJSONBytes))
	fmt.Printf("any Struct Surrogate WKT json payload size: %d\n", len(anyStructSurrogateWKTJSONBytes))
	fmt.Printf("any Struct KeySurrogate WKT json payload size: %d\n", len(anyStructKeySurrogateWKTJSONBytes))
	fmt.Printf("empty struct json payload size: %d\n", len(emptyStructJSONBytes))
	fmt.Printf("any EmptyStruct WKT json payload size: %d\n", len(anyEmptyStructWKTJSONBytes))
	fmt.Printf("any Value WKT json payload size: %d\n", len(anyValueWKTJSONBytes))
	fmt.Printf("any Value Escape WKT json payload size: %d\n", len(anyValueEscapeWKTJSONBytes))
	fmt.Printf("any Value NumberExponent WKT json payload size: %d\n", len(anyValueNumberExponentWKTJSONBytes))
	fmt.Printf("any Value Surrogate WKT json payload size: %d\n", len(anyValueSurrogateWKTJSONBytes))
	fmt.Printf("any Value KeySurrogate WKT json payload size: %d\n", len(anyValueKeySurrogateWKTJSONBytes))
	fmt.Printf("null value json payload size: %d\n", len(nullValueJSONBytes))
	fmt.Printf("any NullValue WKT json payload size: %d\n", len(anyNullValueWKTJSONBytes))
	fmt.Printf("string scalar value json payload size: %d\n", len(stringScalarValueJSONBytes))
	fmt.Printf("string scalar value escape json payload size: %d\n", len(stringScalarValueEscapeJSONBytes))
	fmt.Printf("string scalar value surrogate json payload size: %d\n", len(stringScalarValueSurrogateJSONBytes))
	fmt.Printf("any StringScalarValue WKT json payload size: %d\n", len(anyStringScalarValueWKTJSONBytes))
	fmt.Printf("any StringScalarValue Escape WKT json payload size: %d\n", len(anyStringScalarValueEscapeWKTJSONBytes))
	fmt.Printf("any StringScalarValue Surrogate WKT json payload size: %d\n", len(anyStringScalarValueSurrogateWKTJSONBytes))
	fmt.Printf("empty string scalar value json payload size: %d\n", len(emptyStringScalarValueJSONBytes))
	fmt.Printf("any EmptyStringScalarValue WKT json payload size: %d\n", len(anyEmptyStringScalarValueWKTJSONBytes))
	fmt.Printf("number value json payload size: %d\n", len(numberValueJSONBytes))
	fmt.Printf("any NumberValue WKT json payload size: %d\n", len(anyNumberValueWKTJSONBytes))
	fmt.Printf("negative number value json payload size: %d\n", len(negativeNumberValueJSONBytes))
	fmt.Printf("any NegativeNumberValue WKT json payload size: %d\n", len(anyNegativeNumberValueWKTJSONBytes))
	fmt.Printf("zero number value json payload size: %d\n", len(zeroNumberValueJSONBytes))
	fmt.Printf("any ZeroNumberValue WKT json payload size: %d\n", len(anyZeroNumberValueWKTJSONBytes))
	fmt.Printf("bool scalar value json payload size: %d\n", len(boolScalarValueJSONBytes))
	fmt.Printf("any BoolScalarValue WKT json payload size: %d\n", len(anyBoolScalarValueWKTJSONBytes))
	fmt.Printf("false bool scalar value json payload size: %d\n", len(falseBoolScalarValueJSONBytes))
	fmt.Printf("any FalseBoolScalarValue WKT json payload size: %d\n", len(anyFalseBoolScalarValueWKTJSONBytes))
	fmt.Printf("list-kind value json payload size: %d\n", len(listKindValueJSONBytes))
	fmt.Printf("list-kind value escape json payload size: %d\n", len(listKindValueEscapeJSONBytes))
	fmt.Printf("list-kind value surrogate json payload size: %d\n", len(listKindValueSurrogateJSONBytes))
	fmt.Printf("any ListKindValue WKT json payload size: %d\n", len(anyListKindValueWKTJSONBytes))
	fmt.Printf("any ListKindValue Escape WKT json payload size: %d\n", len(anyListKindValueEscapeWKTJSONBytes))
	fmt.Printf("any ListKindValue Surrogate WKT json payload size: %d\n", len(anyListKindValueSurrogateWKTJSONBytes))
	fmt.Printf("empty struct-kind value json payload size: %d\n", len(emptyStructKindValueJSONBytes))
	fmt.Printf("any EmptyStructKindValue WKT json payload size: %d\n", len(anyEmptyStructKindValueWKTJSONBytes))
	fmt.Printf("empty list-kind value json payload size: %d\n", len(emptyListKindValueJSONBytes))
	fmt.Printf("any EmptyListKindValue WKT json payload size: %d\n", len(anyEmptyListKindValueWKTJSONBytes))
	fmt.Printf("any StringValue WKT json payload size: %d\n", len(anyStringValueWKTJSONBytes))
	fmt.Printf("any EmptyStringValue WKT json payload size: %d\n", len(anyEmptyStringValueWKTJSONBytes))
	fmt.Printf("any BytesValue WKT json payload size: %d\n", len(anyBytesValueWKTJSONBytes))
	fmt.Printf("any EmptyBytesValue WKT json payload size: %d\n", len(anyEmptyBytesValueWKTJSONBytes))
	fmt.Printf("nested Any WKT json payload size: %d\n", len(nestedAnyWKTJSONBytes))
	fmt.Printf("double value json payload size: %d\n", len(doubleValueJSONBytes))
	fmt.Printf("double value string json payload size: %d\n", len(doubleValueStringJSONBytes))
	fmt.Printf("double value exponent json payload size: %d\n", len(doubleValueExponentJSONBytes))
	fmt.Printf("any DoubleValue WKT json payload size: %d\n", len(anyDoubleValueWKTJSONBytes))
	fmt.Printf("any DoubleValue String WKT json payload size: %d\n", len(anyDoubleValueStringWKTJSONBytes))
	fmt.Printf("any DoubleValue Exponent WKT json payload size: %d\n", len(anyDoubleValueExponentWKTJSONBytes))
	fmt.Printf("negative double value json payload size: %d\n", len(negativeDoubleValueJSONBytes))
	fmt.Printf("any NegativeDoubleValue WKT json payload size: %d\n", len(anyNegativeDoubleValueWKTJSONBytes))
	fmt.Printf("zero double value json payload size: %d\n", len(zeroDoubleValueJSONBytes))
	fmt.Printf("any ZeroDoubleValue WKT json payload size: %d\n", len(anyZeroDoubleValueWKTJSONBytes))
	fmt.Printf("double value NaN json payload size: %d\n", len(doubleValueNaNJSONBytes))
	fmt.Printf("any DoubleValue NaN WKT json payload size: %d\n", len(anyDoubleValueNaNWKTJSONBytes))
	fmt.Printf("double value Infinity json payload size: %d\n", len(doubleValueInfJSONBytes))
	fmt.Printf("any DoubleValue Infinity WKT json payload size: %d\n", len(anyDoubleValueInfWKTJSONBytes))
	fmt.Printf("double value NegativeInfinity json payload size: %d\n", len(doubleValueNegInfJSONBytes))
	fmt.Printf("any DoubleValue NegativeInfinity WKT json payload size: %d\n", len(anyDoubleValueNegInfWKTJSONBytes))
	fmt.Printf("float value json payload size: %d\n", len(floatValueJSONBytes))
	fmt.Printf("float value string json payload size: %d\n", len(floatValueStringJSONBytes))
	fmt.Printf("float value exponent json payload size: %d\n", len(floatValueExponentJSONBytes))
	fmt.Printf("any FloatValue WKT json payload size: %d\n", len(anyFloatValueWKTJSONBytes))
	fmt.Printf("any FloatValue String WKT json payload size: %d\n", len(anyFloatValueStringWKTJSONBytes))
	fmt.Printf("any FloatValue Exponent WKT json payload size: %d\n", len(anyFloatValueExponentWKTJSONBytes))
	fmt.Printf("negative float value json payload size: %d\n", len(negativeFloatValueJSONBytes))
	fmt.Printf("any NegativeFloatValue WKT json payload size: %d\n", len(anyNegativeFloatValueWKTJSONBytes))
	fmt.Printf("zero float value json payload size: %d\n", len(zeroFloatValueJSONBytes))
	fmt.Printf("any ZeroFloatValue WKT json payload size: %d\n", len(anyZeroFloatValueWKTJSONBytes))
	fmt.Printf("float value NaN json payload size: %d\n", len(floatValueNaNJSONBytes))
	fmt.Printf("any FloatValue NaN WKT json payload size: %d\n", len(anyFloatValueNaNWKTJSONBytes))
	fmt.Printf("float value Infinity json payload size: %d\n", len(floatValueInfJSONBytes))
	fmt.Printf("any FloatValue Infinity WKT json payload size: %d\n", len(anyFloatValueInfWKTJSONBytes))
	fmt.Printf("float value NegativeInfinity json payload size: %d\n", len(floatValueNegInfJSONBytes))
	fmt.Printf("any FloatValue NegativeInfinity WKT json payload size: %d\n", len(anyFloatValueNegInfWKTJSONBytes))
	fmt.Printf("int64 value json payload size: %d\n", len(int64ValueJSONBytes))
	fmt.Printf("int64 value number json payload size: %d\n", len(int64ValueNumberJSONBytes))
	fmt.Printf("int64 value exponent json payload size: %d\n", len(int64ValueExponentJSONBytes))
	fmt.Printf("any Int64Value WKT json payload size: %d\n", len(anyInt64ValueWKTJSONBytes))
	fmt.Printf("any Int64Value Number WKT json payload size: %d\n", len(anyInt64ValueNumberWKTJSONBytes))
	fmt.Printf("any Int64Value Exponent WKT json payload size: %d\n", len(anyInt64ValueExponentWKTJSONBytes))
	fmt.Printf("zero int64 value json payload size: %d\n", len(zeroInt64ValueJSONBytes))
	fmt.Printf("any ZeroInt64Value WKT json payload size: %d\n", len(anyZeroInt64ValueWKTJSONBytes))
	fmt.Printf("negative int64 value json payload size: %d\n", len(negativeInt64ValueJSONBytes))
	fmt.Printf("any NegativeInt64Value WKT json payload size: %d\n", len(anyNegativeInt64ValueWKTJSONBytes))
	fmt.Printf("min int64 value json payload size: %d\n", len(minInt64ValueJSONBytes))
	fmt.Printf("any MinInt64Value WKT json payload size: %d\n", len(anyMinInt64ValueWKTJSONBytes))
	fmt.Printf("max int64 value json payload size: %d\n", len(maxInt64ValueJSONBytes))
	fmt.Printf("any MaxInt64Value WKT json payload size: %d\n", len(anyMaxInt64ValueWKTJSONBytes))
	fmt.Printf("uint64 value json payload size: %d\n", len(uint64ValueJSONBytes))
	fmt.Printf("uint64 value number json payload size: %d\n", len(uint64ValueNumberJSONBytes))
	fmt.Printf("uint64 value exponent json payload size: %d\n", len(uint64ValueExponentJSONBytes))
	fmt.Printf("any UInt64Value WKT json payload size: %d\n", len(anyUInt64ValueWKTJSONBytes))
	fmt.Printf("any UInt64Value Number WKT json payload size: %d\n", len(anyUInt64ValueNumberWKTJSONBytes))
	fmt.Printf("any UInt64Value Exponent WKT json payload size: %d\n", len(anyUInt64ValueExponentWKTJSONBytes))
	fmt.Printf("zero uint64 value json payload size: %d\n", len(zeroUInt64ValueJSONBytes))
	fmt.Printf("any ZeroUInt64Value WKT json payload size: %d\n", len(anyZeroUInt64ValueWKTJSONBytes))
	fmt.Printf("max uint64 value json payload size: %d\n", len(maxUInt64ValueJSONBytes))
	fmt.Printf("any MaxUInt64Value WKT json payload size: %d\n", len(anyMaxUInt64ValueWKTJSONBytes))
	fmt.Printf("int32 value json payload size: %d\n", len(int32ValueJSONBytes))
	fmt.Printf("int32 value string json payload size: %d\n", len(int32ValueStringJSONBytes))
	fmt.Printf("int32 value exponent json payload size: %d\n", len(int32ValueExponentJSONBytes))
	fmt.Printf("any Int32Value WKT json payload size: %d\n", len(anyInt32ValueWKTJSONBytes))
	fmt.Printf("any Int32Value String WKT json payload size: %d\n", len(anyInt32ValueStringWKTJSONBytes))
	fmt.Printf("any Int32Value Exponent WKT json payload size: %d\n", len(anyInt32ValueExponentWKTJSONBytes))
	fmt.Printf("zero int32 value json payload size: %d\n", len(zeroInt32ValueJSONBytes))
	fmt.Printf("any ZeroInt32Value WKT json payload size: %d\n", len(anyZeroInt32ValueWKTJSONBytes))
	fmt.Printf("negative int32 value json payload size: %d\n", len(negativeInt32ValueJSONBytes))
	fmt.Printf("any NegativeInt32Value WKT json payload size: %d\n", len(anyNegativeInt32ValueWKTJSONBytes))
	fmt.Printf("min int32 value json payload size: %d\n", len(minInt32ValueJSONBytes))
	fmt.Printf("any MinInt32Value WKT json payload size: %d\n", len(anyMinInt32ValueWKTJSONBytes))
	fmt.Printf("max int32 value json payload size: %d\n", len(maxInt32ValueJSONBytes))
	fmt.Printf("any MaxInt32Value WKT json payload size: %d\n", len(anyMaxInt32ValueWKTJSONBytes))
	fmt.Printf("uint32 value json payload size: %d\n", len(uint32ValueJSONBytes))
	fmt.Printf("uint32 value string json payload size: %d\n", len(uint32ValueStringJSONBytes))
	fmt.Printf("uint32 value exponent json payload size: %d\n", len(uint32ValueExponentJSONBytes))
	fmt.Printf("any UInt32Value WKT json payload size: %d\n", len(anyUInt32ValueWKTJSONBytes))
	fmt.Printf("any UInt32Value String WKT json payload size: %d\n", len(anyUInt32ValueStringWKTJSONBytes))
	fmt.Printf("any UInt32Value Exponent WKT json payload size: %d\n", len(anyUInt32ValueExponentWKTJSONBytes))
	fmt.Printf("zero uint32 value json payload size: %d\n", len(zeroUInt32ValueJSONBytes))
	fmt.Printf("any ZeroUInt32Value WKT json payload size: %d\n", len(anyZeroUInt32ValueWKTJSONBytes))
	fmt.Printf("max uint32 value json payload size: %d\n", len(maxUInt32ValueJSONBytes))
	fmt.Printf("any MaxUInt32Value WKT json payload size: %d\n", len(anyMaxUInt32ValueWKTJSONBytes))
	fmt.Printf("bool value json payload size: %d\n", len(boolValueJSONBytes))
	fmt.Printf("any BoolValue WKT json payload size: %d\n", len(anyBoolValueWKTJSONBytes))
	fmt.Printf("false bool value json payload size: %d\n", len(falseBoolValueJSONBytes))
	fmt.Printf("any FalseBoolValue WKT json payload size: %d\n", len(anyFalseBoolValueWKTJSONBytes))
	fmt.Printf("string value json payload size: %d\n", len(stringValueJSONBytes))
	fmt.Printf("string value escape json payload size: %d\n", len(stringValueEscapeJSONBytes))
	fmt.Printf("string value surrogate json payload size: %d\n", len(stringValueSurrogateJSONBytes))
	fmt.Printf("any StringValue Escape WKT json payload size: %d\n", len(anyStringValueEscapeWKTJSONBytes))
	fmt.Printf("any StringValue Surrogate WKT json payload size: %d\n", len(anyStringValueSurrogateWKTJSONBytes))
	fmt.Printf("empty string value json payload size: %d\n", len(emptyStringValueJSONBytes))
	fmt.Printf("bytes value json payload size: %d\n", len(bytesValueJSONBytes))
	fmt.Printf("bytes value URL json payload size: %d\n", len(bytesValueURLJSONBytes))
	fmt.Printf("bytes value StandardBase64 json payload size: %d\n", len(bytesValueStandardBase64JSONBytes))
	fmt.Printf("bytes value unpadded json payload size: %d\n", len(bytesValueUnpaddedJSONBytes))
	fmt.Printf("any BytesValue URL WKT json payload size: %d\n", len(anyBytesValueURLWKTJSONBytes))
	fmt.Printf("any BytesValue StandardBase64 WKT json payload size: %d\n", len(anyBytesValueStandardBase64WKTJSONBytes))
	fmt.Printf("any BytesValue Unpadded WKT json payload size: %d\n", len(anyBytesValueUnpaddedWKTJSONBytes))
	fmt.Printf("empty bytes value json payload size: %d\n", len(emptyBytesValueJSONBytes))
	fmt.Printf("any WKT json payload size: %d\n", len(anyWKTJSONBytes))
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
	fmt.Printf("shuffled large map payload size: %d\n", len(shuffledLargeMapBytes))

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
	runTimed("go protobuf ProtoName JSON stringify", iterations, len(protoNameStringifyJSONBytes), func() {
		out, err := protoNameMarshalOptions.Marshal(scalarmix)
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
	runTimed("go protobuf MapKeySurrogate JSON parse", iterations, len(mapKeySurrogateJSONBytes), func() {
		var decoded personpb.Person
		if err := jsonUnmarshalOptions.Unmarshal(mapKeySurrogateJSONBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()
	runTimed("go protobuf NullFields JSON parse", iterations, len(nullFieldsJSONBytes), func() {
		var decoded personpb.Person
		if err := jsonUnmarshalOptions.Unmarshal(nullFieldsJSONBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()
	runTimed("go protobuf OpenEnum JSON parse", iterations, len(openEnumJSONBytes), func() {
		var decoded personpb.ScalarMix
		if err := jsonUnmarshalOptions.Unmarshal(openEnumJSONBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()
	runTimed("go protobuf EnumName JSON parse", iterations, len(enumNameJSONBytes), func() {
		var decoded personpb.ScalarMix
		if err := jsonUnmarshalOptions.Unmarshal(enumNameJSONBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()
	runTimed("go protobuf ProtoName JSON parse", iterations, len(protoNameJSONBytes), func() {
		var decoded personpb.ScalarMix
		if err := jsonUnmarshalOptions.Unmarshal(protoNameJSONBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()
	runTimed("go protobuf IntExponent JSON parse", iterations, len(intExponentJSONBytes), func() {
		var decoded personpb.ScalarMix
		if err := jsonUnmarshalOptions.Unmarshal(intExponentJSONBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()

	runProtoJSONPair("Any WKT", iterations, anyWKTJSONBytes, anyWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any Duration Escape WKT", iterations, anyDurationEscapeWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runTimed("go protobuf Any PlusDuration WKT JSON parse", iterations, len(anyPlusDurationWKTJSONBytes), func() {
		var decoded anypb.Any
		if err := jsonUnmarshalOptions.Unmarshal(anyPlusDurationWKTJSONBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()
	runTimed("go protobuf Any ShortFractionDuration WKT JSON parse", iterations, len(anyShortFractionDurationWKTJSONBytes), func() {
		var decoded anypb.Any
		if err := jsonUnmarshalOptions.Unmarshal(anyShortFractionDurationWKTJSONBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()
	runProtoJSONPair("Any MicroDuration WKT", iterations, anyMicroDurationWKTJSONBytes, anyMicroDurationWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any NanoDuration WKT", iterations, anyNanoDurationWKTJSONBytes, anyNanoDurationWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any NegativeDuration WKT", iterations, anyNegativeDurationWKTJSONBytes, anyNegativeDurationWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any FractionalNegativeDuration WKT", iterations, anyFractionalNegativeDurationWKTJSONBytes, anyFractionalNegativeDurationWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any MaxDuration WKT", iterations, anyMaxDurationWKTJSONBytes, anyMaxDurationWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any MinDuration WKT", iterations, anyMinDurationWKTJSONBytes, anyMinDurationWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any ZeroDuration WKT", iterations, anyZeroDurationWKTJSONBytes, anyZeroDurationWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any FieldMask WKT", iterations, anyFieldMaskWKTJSONBytes, anyFieldMaskWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any FieldMask Escape WKT", iterations, anyFieldMaskEscapeWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any EmptyFieldMask WKT", iterations, anyEmptyFieldMaskWKTJSONBytes, anyEmptyFieldMaskWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any Timestamp WKT", iterations, anyTimestampWKTJSONBytes, anyTimestampWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any Timestamp Escape WKT", iterations, anyTimestampEscapeWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any ShortFraction Timestamp WKT", iterations, anyShortFractionTimestampWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any Micro Timestamp WKT", iterations, anyMicroTimestampWKTJSONBytes, anyMicroTimestampWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any Nano Timestamp WKT", iterations, anyNanoTimestampWKTJSONBytes, anyNanoTimestampWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runTimed("go protobuf Any Offset Timestamp WKT JSON parse", iterations, len(anyOffsetTimestampWKTJSONBytes), func() {
		var decoded anypb.Any
		if err := jsonUnmarshalOptions.Unmarshal(anyOffsetTimestampWKTJSONBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()
	runProtoJSONPair("Any PreEpoch Timestamp WKT", iterations, anyPreEpochTimestampWKTJSONBytes, anyPreEpochTimestampWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any Max Timestamp WKT", iterations, anyMaxTimestampWKTJSONBytes, anyMaxTimestampWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any Min Timestamp WKT", iterations, anyMinTimestampWKTJSONBytes, anyMinTimestampWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any Empty WKT", iterations, anyEmptyWKTJSONBytes, anyEmptyWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any Struct WKT", iterations, anyStructWKTJSONBytes, anyStructWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any Struct Escape WKT", iterations, anyStructEscapeWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any Struct NumberExponent WKT", iterations, anyStructNumberExponentWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any Struct Surrogate WKT", iterations, anyStructSurrogateWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any Struct KeySurrogate WKT", iterations, anyStructKeySurrogateWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any EmptyStruct WKT", iterations, anyEmptyStructWKTJSONBytes, anyEmptyStructWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any Value WKT", iterations, anyValueWKTJSONBytes, anyValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any Value Escape WKT", iterations, anyValueEscapeWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any Value NumberExponent WKT", iterations, anyValueNumberExponentWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any Value Surrogate WKT", iterations, anyValueSurrogateWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any Value KeySurrogate WKT", iterations, anyValueKeySurrogateWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any NullValue WKT", iterations, anyNullValueWKTJSONBytes, anyNullValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any StringScalarValue WKT", iterations, anyStringScalarValueWKTJSONBytes, anyStringScalarValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any StringScalarValue Escape WKT", iterations, anyStringScalarValueEscapeWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any StringScalarValue Surrogate WKT", iterations, anyStringScalarValueSurrogateWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any EmptyStringScalarValue WKT", iterations, anyEmptyStringScalarValueWKTJSONBytes, anyEmptyStringScalarValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any NumberValue WKT", iterations, anyNumberValueWKTJSONBytes, anyNumberValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any NumberValue Exponent WKT", iterations, anyNumberValueExponentWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any NegativeNumberValue WKT", iterations, anyNegativeNumberValueWKTJSONBytes, anyNegativeNumberValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any ZeroNumberValue WKT", iterations, anyZeroNumberValueWKTJSONBytes, anyZeroNumberValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any BoolScalarValue WKT", iterations, anyBoolScalarValueWKTJSONBytes, anyBoolScalarValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any FalseBoolScalarValue WKT", iterations, anyFalseBoolScalarValueWKTJSONBytes, anyFalseBoolScalarValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any ListKindValue WKT", iterations, anyListKindValueWKTJSONBytes, anyListKindValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any ListKindValue Escape WKT", iterations, anyListKindValueEscapeWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any ListKindValue Surrogate WKT", iterations, anyListKindValueSurrogateWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any EmptyStructKindValue WKT", iterations, anyEmptyStructKindValueWKTJSONBytes, anyEmptyStructKindValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any EmptyListKindValue WKT", iterations, anyEmptyListKindValueWKTJSONBytes, anyEmptyListKindValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any StringValue WKT", iterations, anyStringValueWKTJSONBytes, anyStringValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any BytesValue WKT", iterations, anyBytesValueWKTJSONBytes, anyBytesValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Nested Any WKT", iterations, nestedAnyWKTJSONBytes, nestedAnyWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Duration", iterations, durationJSONBytes, duration, func() *durationpb.Duration { return &durationpb.Duration{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Duration Escape", iterations, durationEscapeJSONBytes, func() *durationpb.Duration { return &durationpb.Duration{} }, jsonUnmarshalOptions)
	runTimed("go protobuf PlusDuration JSON parse", iterations, len(plusDurationJSONBytes), func() {
		var decoded durationpb.Duration
		if err := jsonUnmarshalOptions.Unmarshal(plusDurationJSONBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()
	runTimed("go protobuf ShortFractionDuration JSON parse", iterations, len(shortFractionDurationJSONBytes), func() {
		var decoded durationpb.Duration
		if err := jsonUnmarshalOptions.Unmarshal(shortFractionDurationJSONBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()
	runProtoJSONPair("MicroDuration", iterations, microDurationJSONBytes, microDuration, func() *durationpb.Duration { return &durationpb.Duration{} }, jsonUnmarshalOptions)
	runProtoJSONPair("NanoDuration", iterations, nanoDurationJSONBytes, nanoDuration, func() *durationpb.Duration { return &durationpb.Duration{} }, jsonUnmarshalOptions)
	runProtoJSONPair("NegativeDuration", iterations, negativeDurationJSONBytes, negativeDuration, func() *durationpb.Duration { return &durationpb.Duration{} }, jsonUnmarshalOptions)
	runProtoJSONPair("FractionalNegativeDuration", iterations, fractionalNegativeDurationJSONBytes, fractionalNegativeDuration, func() *durationpb.Duration { return &durationpb.Duration{} }, jsonUnmarshalOptions)
	runProtoJSONPair("MaxDuration", iterations, maxDurationJSONBytes, maxDuration, func() *durationpb.Duration { return &durationpb.Duration{} }, jsonUnmarshalOptions)
	runProtoJSONPair("MinDuration", iterations, minDurationJSONBytes, minDuration, func() *durationpb.Duration { return &durationpb.Duration{} }, jsonUnmarshalOptions)
	runProtoJSONPair("ZeroDuration", iterations, zeroDurationJSONBytes, zeroDuration, func() *durationpb.Duration { return &durationpb.Duration{} }, jsonUnmarshalOptions)
	runProtoJSONPair("FieldMask", iterations, fieldMaskJSONBytes, fieldMask, func() *fieldmaskpb.FieldMask { return &fieldmaskpb.FieldMask{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("FieldMask Escape", iterations, fieldMaskEscapeJSONBytes, func() *fieldmaskpb.FieldMask { return &fieldmaskpb.FieldMask{} }, jsonUnmarshalOptions)
	runProtoJSONPair("EmptyFieldMask", iterations, emptyFieldMaskJSONBytes, emptyFieldMask, func() *fieldmaskpb.FieldMask { return &fieldmaskpb.FieldMask{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Timestamp", iterations, timestampJSONBytes, timestamp, func() *timestamppb.Timestamp { return &timestamppb.Timestamp{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Timestamp Escape", iterations, timestampEscapeJSONBytes, func() *timestamppb.Timestamp { return &timestamppb.Timestamp{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("ShortFraction Timestamp", iterations, shortFractionTimestampJSONBytes, func() *timestamppb.Timestamp { return &timestamppb.Timestamp{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Micro Timestamp", iterations, microTimestampJSONBytes, microTimestamp, func() *timestamppb.Timestamp { return &timestamppb.Timestamp{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Nano Timestamp", iterations, nanoTimestampJSONBytes, nanoTimestamp, func() *timestamppb.Timestamp { return &timestamppb.Timestamp{} }, jsonUnmarshalOptions)
	runTimed("go protobuf Offset Timestamp JSON parse", iterations, len(offsetTimestampJSONBytes), func() {
		var decoded timestamppb.Timestamp
		if err := jsonUnmarshalOptions.Unmarshal(offsetTimestampJSONBytes, &decoded); err != nil {
			panic(err)
		}
	}).print()
	runProtoJSONPair("PreEpoch Timestamp", iterations, preEpochTimestampJSONBytes, preEpochTimestamp, func() *timestamppb.Timestamp { return &timestamppb.Timestamp{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Max Timestamp", iterations, maxTimestampJSONBytes, maxTimestamp, func() *timestamppb.Timestamp { return &timestamppb.Timestamp{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Min Timestamp", iterations, minTimestampJSONBytes, minTimestamp, func() *timestamppb.Timestamp { return &timestamppb.Timestamp{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Empty", iterations, emptyJSONBytes, emptyValue, func() *emptypb.Empty { return &emptypb.Empty{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Struct", iterations, structJSONBytes, structValue, func() *structpb.Struct { return &structpb.Struct{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Struct Escape", iterations, structEscapeJSONBytes, func() *structpb.Struct { return &structpb.Struct{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Struct NumberExponent", iterations, structNumberExponentJSONBytes, func() *structpb.Struct { return &structpb.Struct{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Struct Surrogate", iterations, structSurrogateJSONBytes, func() *structpb.Struct { return &structpb.Struct{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Struct KeySurrogate", iterations, structKeySurrogateJSONBytes, func() *structpb.Struct { return &structpb.Struct{} }, jsonUnmarshalOptions)
	runProtoJSONPair("EmptyStruct", iterations, emptyStructJSONBytes, emptyStructValue, func() *structpb.Struct { return &structpb.Struct{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Value", iterations, valueJSONBytes, valueValue, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Value Escape", iterations, valueEscapeJSONBytes, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Value NumberExponent", iterations, valueNumberExponentJSONBytes, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Value Surrogate", iterations, valueSurrogateJSONBytes, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Value KeySurrogate", iterations, valueKeySurrogateJSONBytes, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("NullValue", iterations, nullValueJSONBytes, nullValueValue, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("StringScalarValue", iterations, stringScalarValueJSONBytes, stringScalarValue, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("StringScalarValue Escape", iterations, stringScalarValueEscapeJSONBytes, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("StringScalarValue Surrogate", iterations, stringScalarValueSurrogateJSONBytes, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("EmptyStringScalarValue", iterations, emptyStringScalarValueJSONBytes, emptyStringScalarValue, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("NumberValue", iterations, numberValueJSONBytes, numberValue, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("NumberValue Exponent", iterations, numberValueExponentJSONBytes, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("NegativeNumberValue", iterations, negativeNumberValueJSONBytes, negativeNumberValue, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("ZeroNumberValue", iterations, zeroNumberValueJSONBytes, zeroNumberValue, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("BoolScalarValue", iterations, boolScalarValueJSONBytes, boolScalarValue, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("FalseBoolScalarValue", iterations, falseBoolScalarValueJSONBytes, falseBoolScalarValue, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("ListKindValue", iterations, listKindValueJSONBytes, listKindValue, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("ListKindValue Escape", iterations, listKindValueEscapeJSONBytes, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("ListKindValue Surrogate", iterations, listKindValueSurrogateJSONBytes, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("EmptyStructKindValue", iterations, emptyStructKindValueJSONBytes, emptyStructKindValue, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("EmptyListKindValue", iterations, emptyListKindValueJSONBytes, emptyListKindValue, func() *structpb.Value { return &structpb.Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("ListValue", iterations, listValueJSONBytes, listValue, func() *structpb.ListValue { return &structpb.ListValue{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("ListValue Escape", iterations, listValueEscapeJSONBytes, func() *structpb.ListValue { return &structpb.ListValue{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("ListValue Surrogate", iterations, listValueSurrogateJSONBytes, func() *structpb.ListValue { return &structpb.ListValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("EmptyListValue", iterations, emptyListValueJSONBytes, emptyListValue, func() *structpb.ListValue { return &structpb.ListValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("DoubleValue", iterations, doubleValueJSONBytes, doubleValue, func() *wrapperspb.DoubleValue { return &wrapperspb.DoubleValue{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("DoubleValue String", iterations, doubleValueStringJSONBytes, func() *wrapperspb.DoubleValue { return &wrapperspb.DoubleValue{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("DoubleValue Exponent", iterations, doubleValueExponentJSONBytes, func() *wrapperspb.DoubleValue { return &wrapperspb.DoubleValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any DoubleValue WKT", iterations, anyDoubleValueWKTJSONBytes, anyDoubleValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any DoubleValue String WKT", iterations, anyDoubleValueStringWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any DoubleValue Exponent WKT", iterations, anyDoubleValueExponentWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("NegativeDoubleValue", iterations, negativeDoubleValueJSONBytes, negativeDoubleValue, func() *wrapperspb.DoubleValue { return &wrapperspb.DoubleValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any NegativeDoubleValue WKT", iterations, anyNegativeDoubleValueWKTJSONBytes, anyNegativeDoubleValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("ZeroDoubleValue", iterations, zeroDoubleValueJSONBytes, zeroDoubleValue, func() *wrapperspb.DoubleValue { return &wrapperspb.DoubleValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any ZeroDoubleValue WKT", iterations, anyZeroDoubleValueWKTJSONBytes, anyZeroDoubleValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("DoubleValue NaN", iterations, doubleValueNaNJSONBytes, doubleValueNaN, func() *wrapperspb.DoubleValue { return &wrapperspb.DoubleValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any DoubleValue NaN WKT", iterations, anyDoubleValueNaNWKTJSONBytes, anyDoubleValueNaNWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("DoubleValue Infinity", iterations, doubleValueInfJSONBytes, doubleValueInf, func() *wrapperspb.DoubleValue { return &wrapperspb.DoubleValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any DoubleValue Infinity WKT", iterations, anyDoubleValueInfWKTJSONBytes, anyDoubleValueInfWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("DoubleValue NegativeInfinity", iterations, doubleValueNegInfJSONBytes, doubleValueNegInf, func() *wrapperspb.DoubleValue { return &wrapperspb.DoubleValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any DoubleValue NegativeInfinity WKT", iterations, anyDoubleValueNegInfWKTJSONBytes, anyDoubleValueNegInfWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("FloatValue", iterations, floatValueJSONBytes, floatValue, func() *wrapperspb.FloatValue { return &wrapperspb.FloatValue{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("FloatValue String", iterations, floatValueStringJSONBytes, func() *wrapperspb.FloatValue { return &wrapperspb.FloatValue{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("FloatValue Exponent", iterations, floatValueExponentJSONBytes, func() *wrapperspb.FloatValue { return &wrapperspb.FloatValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any FloatValue WKT", iterations, anyFloatValueWKTJSONBytes, anyFloatValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any FloatValue String WKT", iterations, anyFloatValueStringWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any FloatValue Exponent WKT", iterations, anyFloatValueExponentWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("NegativeFloatValue", iterations, negativeFloatValueJSONBytes, negativeFloatValue, func() *wrapperspb.FloatValue { return &wrapperspb.FloatValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any NegativeFloatValue WKT", iterations, anyNegativeFloatValueWKTJSONBytes, anyNegativeFloatValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("ZeroFloatValue", iterations, zeroFloatValueJSONBytes, zeroFloatValue, func() *wrapperspb.FloatValue { return &wrapperspb.FloatValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any ZeroFloatValue WKT", iterations, anyZeroFloatValueWKTJSONBytes, anyZeroFloatValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("FloatValue NaN", iterations, floatValueNaNJSONBytes, floatValueNaN, func() *wrapperspb.FloatValue { return &wrapperspb.FloatValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any FloatValue NaN WKT", iterations, anyFloatValueNaNWKTJSONBytes, anyFloatValueNaNWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("FloatValue Infinity", iterations, floatValueInfJSONBytes, floatValueInf, func() *wrapperspb.FloatValue { return &wrapperspb.FloatValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any FloatValue Infinity WKT", iterations, anyFloatValueInfWKTJSONBytes, anyFloatValueInfWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("FloatValue NegativeInfinity", iterations, floatValueNegInfJSONBytes, floatValueNegInf, func() *wrapperspb.FloatValue { return &wrapperspb.FloatValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any FloatValue NegativeInfinity WKT", iterations, anyFloatValueNegInfWKTJSONBytes, anyFloatValueNegInfWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Int64Value", iterations, int64ValueJSONBytes, int64Value, func() *wrapperspb.Int64Value { return &wrapperspb.Int64Value{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Int64Value Number", iterations, int64ValueNumberJSONBytes, func() *wrapperspb.Int64Value { return &wrapperspb.Int64Value{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Int64Value Exponent", iterations, int64ValueExponentJSONBytes, func() *wrapperspb.Int64Value { return &wrapperspb.Int64Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any Int64Value WKT", iterations, anyInt64ValueWKTJSONBytes, anyInt64ValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any Int64Value Number WKT", iterations, anyInt64ValueNumberWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any Int64Value Exponent WKT", iterations, anyInt64ValueExponentWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("ZeroInt64Value", iterations, zeroInt64ValueJSONBytes, zeroInt64Value, func() *wrapperspb.Int64Value { return &wrapperspb.Int64Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any ZeroInt64Value WKT", iterations, anyZeroInt64ValueWKTJSONBytes, anyZeroInt64ValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("NegativeInt64Value", iterations, negativeInt64ValueJSONBytes, negativeInt64Value, func() *wrapperspb.Int64Value { return &wrapperspb.Int64Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any NegativeInt64Value WKT", iterations, anyNegativeInt64ValueWKTJSONBytes, anyNegativeInt64ValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("MinInt64Value", iterations, minInt64ValueJSONBytes, minInt64Value, func() *wrapperspb.Int64Value { return &wrapperspb.Int64Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any MinInt64Value WKT", iterations, anyMinInt64ValueWKTJSONBytes, anyMinInt64ValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("MaxInt64Value", iterations, maxInt64ValueJSONBytes, maxInt64Value, func() *wrapperspb.Int64Value { return &wrapperspb.Int64Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any MaxInt64Value WKT", iterations, anyMaxInt64ValueWKTJSONBytes, anyMaxInt64ValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("UInt64Value", iterations, uint64ValueJSONBytes, uint64Value, func() *wrapperspb.UInt64Value { return &wrapperspb.UInt64Value{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("UInt64Value Number", iterations, uint64ValueNumberJSONBytes, func() *wrapperspb.UInt64Value { return &wrapperspb.UInt64Value{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("UInt64Value Exponent", iterations, uint64ValueExponentJSONBytes, func() *wrapperspb.UInt64Value { return &wrapperspb.UInt64Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any UInt64Value WKT", iterations, anyUInt64ValueWKTJSONBytes, anyUInt64ValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any UInt64Value Number WKT", iterations, anyUInt64ValueNumberWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any UInt64Value Exponent WKT", iterations, anyUInt64ValueExponentWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("ZeroUInt64Value", iterations, zeroUInt64ValueJSONBytes, zeroUInt64Value, func() *wrapperspb.UInt64Value { return &wrapperspb.UInt64Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any ZeroUInt64Value WKT", iterations, anyZeroUInt64ValueWKTJSONBytes, anyZeroUInt64ValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("MaxUInt64Value", iterations, maxUInt64ValueJSONBytes, maxUInt64Value, func() *wrapperspb.UInt64Value { return &wrapperspb.UInt64Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any MaxUInt64Value WKT", iterations, anyMaxUInt64ValueWKTJSONBytes, anyMaxUInt64ValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Int32Value", iterations, int32ValueJSONBytes, int32Value, func() *wrapperspb.Int32Value { return &wrapperspb.Int32Value{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Int32Value String", iterations, int32ValueStringJSONBytes, func() *wrapperspb.Int32Value { return &wrapperspb.Int32Value{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Int32Value Exponent", iterations, int32ValueExponentJSONBytes, func() *wrapperspb.Int32Value { return &wrapperspb.Int32Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any Int32Value WKT", iterations, anyInt32ValueWKTJSONBytes, anyInt32ValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any Int32Value String WKT", iterations, anyInt32ValueStringWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any Int32Value Exponent WKT", iterations, anyInt32ValueExponentWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("ZeroInt32Value", iterations, zeroInt32ValueJSONBytes, zeroInt32Value, func() *wrapperspb.Int32Value { return &wrapperspb.Int32Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any ZeroInt32Value WKT", iterations, anyZeroInt32ValueWKTJSONBytes, anyZeroInt32ValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("NegativeInt32Value", iterations, negativeInt32ValueJSONBytes, negativeInt32Value, func() *wrapperspb.Int32Value { return &wrapperspb.Int32Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any NegativeInt32Value WKT", iterations, anyNegativeInt32ValueWKTJSONBytes, anyNegativeInt32ValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("MinInt32Value", iterations, minInt32ValueJSONBytes, minInt32Value, func() *wrapperspb.Int32Value { return &wrapperspb.Int32Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any MinInt32Value WKT", iterations, anyMinInt32ValueWKTJSONBytes, anyMinInt32ValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("MaxInt32Value", iterations, maxInt32ValueJSONBytes, maxInt32Value, func() *wrapperspb.Int32Value { return &wrapperspb.Int32Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any MaxInt32Value WKT", iterations, anyMaxInt32ValueWKTJSONBytes, anyMaxInt32ValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("UInt32Value", iterations, uint32ValueJSONBytes, uint32Value, func() *wrapperspb.UInt32Value { return &wrapperspb.UInt32Value{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("UInt32Value String", iterations, uint32ValueStringJSONBytes, func() *wrapperspb.UInt32Value { return &wrapperspb.UInt32Value{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("UInt32Value Exponent", iterations, uint32ValueExponentJSONBytes, func() *wrapperspb.UInt32Value { return &wrapperspb.UInt32Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any UInt32Value WKT", iterations, anyUInt32ValueWKTJSONBytes, anyUInt32ValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any UInt32Value String WKT", iterations, anyUInt32ValueStringWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any UInt32Value Exponent WKT", iterations, anyUInt32ValueExponentWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("ZeroUInt32Value", iterations, zeroUInt32ValueJSONBytes, zeroUInt32Value, func() *wrapperspb.UInt32Value { return &wrapperspb.UInt32Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any ZeroUInt32Value WKT", iterations, anyZeroUInt32ValueWKTJSONBytes, anyZeroUInt32ValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("MaxUInt32Value", iterations, maxUInt32ValueJSONBytes, maxUInt32Value, func() *wrapperspb.UInt32Value { return &wrapperspb.UInt32Value{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any MaxUInt32Value WKT", iterations, anyMaxUInt32ValueWKTJSONBytes, anyMaxUInt32ValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("BoolValue", iterations, boolValueJSONBytes, boolValue, func() *wrapperspb.BoolValue { return &wrapperspb.BoolValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any BoolValue WKT", iterations, anyBoolValueWKTJSONBytes, anyBoolValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("FalseBoolValue", iterations, falseBoolValueJSONBytes, falseBoolValue, func() *wrapperspb.BoolValue { return &wrapperspb.BoolValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any FalseBoolValue WKT", iterations, anyFalseBoolValueWKTJSONBytes, anyFalseBoolValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("StringValue", iterations, stringValueJSONBytes, stringValue, func() *wrapperspb.StringValue { return &wrapperspb.StringValue{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("StringValue Escape", iterations, stringValueEscapeJSONBytes, func() *wrapperspb.StringValue { return &wrapperspb.StringValue{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("StringValue Surrogate", iterations, stringValueSurrogateJSONBytes, func() *wrapperspb.StringValue { return &wrapperspb.StringValue{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any StringValue Escape WKT", iterations, anyStringValueEscapeWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any StringValue Surrogate WKT", iterations, anyStringValueSurrogateWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("EmptyStringValue", iterations, emptyStringValueJSONBytes, emptyStringValue, func() *wrapperspb.StringValue { return &wrapperspb.StringValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any EmptyStringValue WKT", iterations, anyEmptyStringValueWKTJSONBytes, anyEmptyStringValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("BytesValue", iterations, bytesValueJSONBytes, bytesValue, func() *wrapperspb.BytesValue { return &wrapperspb.BytesValue{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("BytesValue URL", iterations, bytesValueURLJSONBytes, func() *wrapperspb.BytesValue { return &wrapperspb.BytesValue{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("BytesValue StandardBase64", iterations, bytesValueStandardBase64JSONBytes, func() *wrapperspb.BytesValue { return &wrapperspb.BytesValue{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("BytesValue Unpadded", iterations, bytesValueUnpaddedJSONBytes, func() *wrapperspb.BytesValue { return &wrapperspb.BytesValue{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any BytesValue URL WKT", iterations, anyBytesValueURLWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any BytesValue StandardBase64 WKT", iterations, anyBytesValueStandardBase64WKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONParseOnly("Any BytesValue Unpadded WKT", iterations, anyBytesValueUnpaddedWKTJSONBytes, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)
	runProtoJSONPair("EmptyBytesValue", iterations, emptyBytesValueJSONBytes, emptyBytesValue, func() *wrapperspb.BytesValue { return &wrapperspb.BytesValue{} }, jsonUnmarshalOptions)
	runProtoJSONPair("Any EmptyBytesValue WKT", iterations, anyEmptyBytesValueWKTJSONBytes, anyEmptyBytesValueWKT, func() *anypb.Any { return &anypb.Any{} }, jsonUnmarshalOptions)

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

	shuffledLargeMapDeterministicBuf := make([]byte, 0, len(shuffledLargeMapBytes))
	runTimed("go protobuf shuffled large map deterministic binary encode reuse", iterations, len(shuffledLargeMapBytes), func() {
		var err error
		shuffledLargeMapDeterministicBuf, err = deterministicOptions.MarshalAppend(shuffledLargeMapDeterministicBuf[:0], shuffledLargeMap)
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
