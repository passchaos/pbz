pub const std = @import("std");
pub const pbz = @import("pbz");
pub const person_pb = @import("person_pb");
pub const root = @import("pbz_bench.zig");

pub const AnyWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Duration","value":"1.500s"}
;

pub const AnyDurationEscapeWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Duration","value":"1\u002e500s"}
;

pub const AnyPlusDurationWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Duration","value":"+1.500s"}
;

pub const AnyShortFractionDurationWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Duration","value":"1.5s"}
;

pub const AnyMicroDurationWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Duration","value":"1.000120s"}
;

pub const AnyNanoDurationWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Duration","value":"1.123456789s"}
;

pub const AnyNegativeDurationWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Duration","value":"-1.500s"}
;

pub const AnyFractionalNegativeDurationWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Duration","value":"-0.250s"}
;

pub const AnyMaxDurationWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Duration","value":"315576000000s"}
;

pub const AnyMinDurationWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Duration","value":"-315576000000s"}
;

pub const AnyZeroDurationWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Duration","value":"0s"}
;

pub const AnyFieldMaskWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.FieldMask","value":"fooBar,nested.value"}
;

pub const AnyFieldMaskEscapeWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.FieldMask","value":"fooBar,\u006eested.value"}
;

pub const AnyEmptyFieldMaskWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.FieldMask","value":""}
;

pub const AnyTimestampWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Timestamp","value":"2020-01-01T00:00:00.123Z"}
;

pub const AnyTimestampEscapeWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Timestamp","value":"2020-01-01T00:00:00\u002e123Z"}
;

pub const AnyShortFractionTimestampWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Timestamp","value":"2020-01-01T00:00:00.1Z"}
;

pub const AnyMicroTimestampWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Timestamp","value":"2020-01-01T00:00:00.123456Z"}
;

pub const AnyNanoTimestampWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Timestamp","value":"2020-01-01T00:00:00.123456789Z"}
;

pub const AnyOffsetTimestampWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Timestamp","value":"2020-01-01T03:00:00.123456+03:00"}
;

pub const AnyPreEpochTimestampWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Timestamp","value":"1969-12-31T23:59:59Z"}
;

pub const AnyMaxTimestampWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Timestamp","value":"9999-12-31T23:59:59.999999999Z"}
;

pub const AnyMinTimestampWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Timestamp","value":"0001-01-01T00:00:00Z"}
;

pub const AnyEmptyWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Empty"}
;

pub const AnyStructWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Struct","value":{"enabled":true,"items":[null,"zig"],"meta":{"score":1.5}}}
;

pub const AnyStructEscapeWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Struct","value":{"\u0065nabled":true,"items":[null,"\u007aig"],"meta":{"score":1.5}}}
;

pub const AnyStructNumberExponentWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Struct","value":{"enabled":true,"items":[null,"zig"],"meta":{"score":1.5e0}}}
;

pub const AnyStructSurrogateWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Struct","value":{"emoji":"\ud83d\ude00"}}
;

pub const AnyStructKeySurrogateWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Struct","value":{"\ud83d\ude00":"ok"}}
;

pub const AnyEmptyStructWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Struct","value":{}}
;

pub const AnyValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":{"enabled":true,"items":[null,"zig"],"meta":{"score":1.5}}}
;

pub const AnyValueEscapeWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":{"\u0065nabled":true,"items":[null,"\u007aig"],"meta":{"score":1.5}}}
;

pub const AnyValueNumberExponentWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":{"enabled":true,"items":[null,"zig"],"meta":{"score":1.5e0}}}
;

pub const AnyValueSurrogateWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":{"emoji":"\ud83d\ude00"}}
;

pub const AnyValueKeySurrogateWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":{"\ud83d\ude00":"ok"}}
;

pub const AnyNullValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":null}
;

pub const AnyStringScalarValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":"zig"}
;

pub const AnyStringScalarValueEscapeWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":"\u007aig"}
;

pub const AnyStringScalarValueSurrogateWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":"\ud83d\ude00"}
;

pub const AnyEmptyStringScalarValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":""}
;

pub const AnyNumberValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":1.5}
;

pub const AnyNumberValueExponentWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":1.5e0}
;

pub const AnyNegativeNumberValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":-1.5}
;

pub const AnyZeroNumberValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":0}
;

pub const AnyBoolScalarValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":true}
;

pub const AnyFalseBoolScalarValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":false}
;

pub const AnyListKindValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":[null,"zig",1.5,true,{"nested":"value"}]}
;

pub const AnyListKindValueEscapeWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":[null,"\u007aig",1.5,true,{"\u006eested":"value"}]}
;

pub const AnyListKindValueSurrogateWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":["\ud83d\ude00"]}
;

pub const AnyEmptyStructKindValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":{}}
;

pub const AnyEmptyListKindValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":[]}
;

pub const AnyDoubleValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.DoubleValue","value":3.25}
;

pub const AnyDoubleValueStringWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.DoubleValue","value":"3.25"}
;

pub const AnyDoubleValueExponentWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.DoubleValue","value":3.25e0}
;

pub const AnyNegativeDoubleValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.DoubleValue","value":-3.25}
;

pub const AnyZeroDoubleValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.DoubleValue","value":0}
;

pub const AnyDoubleValueNanWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.DoubleValue","value":"NaN"}
;

pub const AnyDoubleValueInfWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.DoubleValue","value":"Infinity"}
;

pub const AnyDoubleValueNegInfWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.DoubleValue","value":"-Infinity"}
;

pub const AnyFloatValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.FloatValue","value":1.5}
;

pub const AnyFloatValueStringWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.FloatValue","value":"1.5"}
;

pub const AnyFloatValueExponentWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.FloatValue","value":1.5e0}
;

pub const AnyNegativeFloatValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.FloatValue","value":-1.5}
;

pub const AnyZeroFloatValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.FloatValue","value":0}
;

pub const AnyFloatValueNanWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.FloatValue","value":"NaN"}
;

pub const AnyFloatValueInfWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.FloatValue","value":"Infinity"}
;

pub const AnyFloatValueNegInfWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.FloatValue","value":"-Infinity"}
;

pub const AnyInt64ValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":"9007199254740993"}
;

pub const AnyInt64ValueNumberWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":9007199254740993}
;

pub const AnyInt64ValueExponentWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":1.2345e4}
;

pub const AnyZeroInt64ValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":"0"}
;

pub const AnyNegativeInt64ValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":"-9007199254740993"}
;

pub const AnyMinInt64ValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":"-9223372036854775808"}
;

pub const AnyMaxInt64ValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":"9223372036854775807"}
;

pub const AnyUInt64ValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.UInt64Value","value":"9007199254740993"}
;

pub const AnyUInt64ValueNumberWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.UInt64Value","value":9007199254740993}
;

pub const AnyUInt64ValueExponentWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.UInt64Value","value":1.2345e4}
;

pub const AnyZeroUInt64ValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.UInt64Value","value":"0"}
;

pub const AnyMaxUInt64ValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.UInt64Value","value":"18446744073709551615"}
;

pub const AnyInt32ValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Int32Value","value":12345}
;

pub const AnyInt32ValueStringWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Int32Value","value":"12345"}
;

pub const AnyInt32ValueExponentWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Int32Value","value":1.2345e4}
;

pub const AnyZeroInt32ValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Int32Value","value":0}
;

pub const AnyNegativeInt32ValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Int32Value","value":-12345}
;

pub const AnyMinInt32ValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Int32Value","value":-2147483648}
;

pub const AnyMaxInt32ValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Int32Value","value":2147483647}
;

pub const AnyUInt32ValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.UInt32Value","value":12345}
;

pub const AnyUInt32ValueStringWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.UInt32Value","value":"12345"}
;

pub const AnyUInt32ValueExponentWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.UInt32Value","value":1.2345e4}
;

pub const AnyZeroUInt32ValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.UInt32Value","value":0}
;

pub const AnyMaxUInt32ValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.UInt32Value","value":4294967295}
;

pub const AnyBoolValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.BoolValue","value":true}
;

pub const AnyFalseBoolValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.BoolValue","value":false}
;

pub const AnyStringValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.StringValue","value":"hello"}
;

pub const AnyStringValueEscapeWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.StringValue","value":"\\u0068ello"}
;

pub const AnyStringValueSurrogateWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.StringValue","value":"\\ud83d\\ude00"}
;

pub const AnyEmptyStringValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.StringValue","value":""}
;

pub const AnyBytesValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.BytesValue","value":"aGk="}
;

pub const AnyBytesValueUrlWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.BytesValue","value":"-_8"}
;

pub const AnyBytesValueStandardBase64WktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.BytesValue","value":"+/8"}
;

pub const AnyBytesValueUnpaddedWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.BytesValue","value":"aGk"}
;

pub const AnyEmptyBytesValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.BytesValue","value":""}
;

pub const NestedAnyWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Any","value":{"@type":"type.googleapis.com/google.protobuf.StringValue","value":"hello"}}
;

pub const GeneratedMapKeySurrogateJson = "{\"counts\":{\"\\ud83d\\ude00\":9}}";

pub const GeneratedIntExponentJson = "{\"count\":1.2345e4,\"total\":9.87654321e9,\"delta\":-3.21e2,\"bigDelta\":-9.876543e6,\"checksum\":3.21e2,\"token\":4.096e3,\"signedFixed\":-1.23456e5,\"signedBigFixed\":-9.876543e6,\"ids\":[1e0,1.27e2,1.28e2]}";

pub const GeneratedStringNumberJson = "{\"count\":\"12345\",\"total\":\"9876543210\",\"delta\":\"-321\",\"bigDelta\":\"-9876543\",\"checksum\":\"321\",\"token\":\"4096\",\"signedFixed\":\"-123456\",\"signedBigFixed\":\"-9876543\",\"ids\":[\"1\",\"127\",\"128\"]}";

pub const GeneratedNullFieldsJson = "{\"id\":null,\"name\":null,\"scores\":null,\"counts\":null}";

pub const GeneratedIgnoreUnknownJson = "{\"id\":7,\"name\":\"zig\",\"scores\":[3],\"counts\":{\"red\":4},\"unknownNested\":{\"x\":1},\"unknownList\":[1,2]}";

pub const GeneratedOpenEnumJson = "{\"kind\":123}";

pub const GeneratedEnumNameJson = "{\"kind\":\"BENCH_KIND_BETA\"}";

pub const GeneratedProtoNameJson = "{\"big_delta\":-321,\"signed_fixed\":-123,\"signed_big_fixed\":-456}";

pub const TimestampJson = "\"2020-01-01T00:00:00.123Z\"";

pub const TimestampEscapeJson = "\"2020-01-01T00:00:00\\u002e123Z\"";

pub const ShortFractionTimestampJson = "\"2020-01-01T00:00:00.1Z\"";

pub const MicroTimestampJson = "\"2020-01-01T00:00:00.123456Z\"";

pub const NanoTimestampJson = "\"2020-01-01T00:00:00.123456789Z\"";

pub const OffsetTimestampJson = "\"2020-01-01T03:00:00.123456+03:00\"";

pub const PreEpochTimestampJson = "\"1969-12-31T23:59:59Z\"";

pub const MaxTimestampJson = "\"9999-12-31T23:59:59.999999999Z\"";

pub const MinTimestampJson = "\"0001-01-01T00:00:00Z\"";

pub const DurationJson = "\"1.500s\"";

pub const DurationEscapeJson = "\"1\\u002e500s\"";

pub const PlusDurationJson = "\"+1.500s\"";

pub const ShortFractionDurationJson = "\"1.5s\"";

pub const MicroDurationJson = "\"1.000120s\"";

pub const NanoDurationJson = "\"1.123456789s\"";

pub const NegativeDurationJson = "\"-1.500s\"";

pub const FractionalNegativeDurationJson = "\"-0.250s\"";

pub const MaxDurationJson = "\"315576000000s\"";

pub const MinDurationJson = "\"-315576000000s\"";

pub const ZeroDurationJson = "\"0s\"";

pub const FieldMaskJson = "\"fooBar,nested.value\"";

pub const FieldMaskEscapeJson = "\"fooBar,\\u006eested.value\"";

pub const EmptyFieldMaskJson = "\"\"";

pub const EmptyJson = "{}";

pub const StructJson = "{\"enabled\":true,\"items\":[null,\"zig\"],\"meta\":{\"score\":1.5}}";

pub const StructEscapeJson = "{\"\\u0065nabled\":true,\"items\":[null,\"\\u007aig\"],\"meta\":{\"score\":1.5}}";

pub const StructNumberExponentJson = "{\"enabled\":true,\"items\":[null,\"zig\"],\"meta\":{\"score\":1.5e0}}";

pub const StructSurrogateJson = "{\"emoji\":\"\\ud83d\\ude00\"}";

pub const StructKeySurrogateJson = "{\"\\ud83d\\ude00\":\"ok\"}";

pub const EmptyStructJson = "{}";

pub const ValueJson = StructJson;

pub const ValueEscapeJson = StructEscapeJson;

pub const ValueNumberExponentJson = StructNumberExponentJson;

pub const ValueSurrogateJson = StructSurrogateJson;

pub const ValueKeySurrogateJson = StructKeySurrogateJson;

pub const NullValueJson = "null";

pub const StringScalarValueJson = "\"zig\"";

pub const StringScalarValueEscapeJson = "\"\\u007aig\"";

pub const StringScalarValueSurrogateJson = "\"\\ud83d\\ude00\"";

pub const EmptyStringScalarValueJson = "\"\"";

pub const NumberValueJson = "1.5";

pub const NumberValueExponentJson = "1.5e0";

pub const NegativeNumberValueJson = "-1.5";

pub const ZeroNumberValueJson = "0";

pub const BoolScalarValueJson = "true";

pub const FalseBoolScalarValueJson = "false";

pub const ListValueJson = "[null,\"zig\",1.5,true,{\"nested\":\"value\"}]";

pub const ListValueEscapeJson = "[null,\"\\u007aig\",1.5,true,{\"\\u006eested\":\"value\"}]";

pub const ListValueSurrogateJson = "[\"\\ud83d\\ude00\"]";

pub const ListKindValueJson = ListValueJson;

pub const ListKindValueEscapeJson = ListValueEscapeJson;

pub const ListKindValueSurrogateJson = ListValueSurrogateJson;

pub const EmptyStructKindValueJson = EmptyStructJson;

pub const EmptyListValueJson = "[]";

pub const EmptyListKindValueJson = EmptyListValueJson;

pub const DoubleValueJson = "3.25";

pub const DoubleValueStringJson = "\"3.25\"";

pub const DoubleValueExponentJson = "3.25e0";

pub const NegativeDoubleValueJson = "-3.25";

pub const ZeroDoubleValueJson = "0";

pub const DoubleValueNanJson = "\"NaN\"";

pub const DoubleValueInfJson = "\"Infinity\"";

pub const DoubleValueNegInfJson = "\"-Infinity\"";

pub const FloatValueJson = "1.5";

pub const FloatValueStringJson = "\"1.5\"";

pub const FloatValueExponentJson = "1.5e0";

pub const NegativeFloatValueJson = "-1.5";

pub const ZeroFloatValueJson = "0";

pub const FloatValueNanJson = "\"NaN\"";

pub const FloatValueInfJson = "\"Infinity\"";

pub const FloatValueNegInfJson = "\"-Infinity\"";

pub const Int64ValueJson = "\"9007199254740993\"";

pub const Int64ValueNumberJson = "9007199254740993";

pub const Int64ValueExponentJson = "1.2345e4";

pub const ZeroInt64ValueJson = "\"0\"";

pub const NegativeInt64ValueJson = "\"-9007199254740993\"";

pub const MinInt64ValueJson = "\"-9223372036854775808\"";

pub const MaxInt64ValueJson = "\"9223372036854775807\"";

pub const UInt64ValueJson = "\"9007199254740993\"";

pub const UInt64ValueNumberJson = "9007199254740993";

pub const UInt64ValueExponentJson = "1.2345e4";

pub const ZeroUInt64ValueJson = "\"0\"";

pub const MaxUInt64ValueJson = "\"18446744073709551615\"";

pub const Int32ValueJson = "12345";

pub const Int32ValueStringJson = "\"12345\"";

pub const Int32ValueExponentJson = "1.2345e4";

pub const ZeroInt32ValueJson = "0";

pub const NegativeInt32ValueJson = "-12345";

pub const MinInt32ValueJson = "-2147483648";

pub const MaxInt32ValueJson = "2147483647";

pub const UInt32ValueJson = "12345";

pub const UInt32ValueStringJson = "\"12345\"";

pub const UInt32ValueExponentJson = "1.2345e4";

pub const ZeroUInt32ValueJson = "0";

pub const MaxUInt32ValueJson = "4294967295";

pub const BoolValueJson = "true";

pub const FalseBoolValueJson = "false";

pub const StringValueJson = "\"hello\"";

pub const StringValueEscapeJson = "\"\\u0068ello\"";

pub const StringValueSurrogateJson = "\"\\ud83d\\ude00\"";

pub const EmptyStringValueJson = "\"\"";

pub const BytesValueJson = "\"aGk=\"";

pub const BytesValueUrlJson = "\"-_8\"";

pub const BytesValueStandardBase64Json = "\"+/8\"";

pub const BytesValueUnpaddedJson = "\"aGk\"";

pub const EmptyBytesValueJson = "\"\"";

pub const GeneratedTextBytesJsonStringifyCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.TextBytes };

pub fn generatedTextBytesJsonStringify(ctx: GeneratedTextBytesJsonStringifyCtx) !void {
    const json = try ctx.message.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

pub const GeneratedTextBytesJsonParseCtx = struct { allocator: std.mem.Allocator, json: []const u8 };

pub fn generatedTextBytesJsonParse(ctx: GeneratedTextBytesJsonParseCtx) !void {
    var decoded = try person_pb.demo.TextBytes.jsonParse(ctx.allocator, ctx.json);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedPresenceMixJsonStringifyCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.PresenceMix };

pub fn generatedPresenceMixJsonStringify(ctx: GeneratedPresenceMixJsonStringifyCtx) !void {
    const json = try ctx.message.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

pub const GeneratedPresenceMixJsonParseCtx = struct { allocator: std.mem.Allocator, json: []const u8 };

pub fn generatedPresenceMixJsonParse(ctx: GeneratedPresenceMixJsonParseCtx) !void {
    var decoded = try person_pb.demo.PresenceMix.jsonParse(ctx.allocator, ctx.json);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedComplexJsonStringifyCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.Complex };

pub fn generatedComplexJsonStringify(ctx: GeneratedComplexJsonStringifyCtx) !void {
    const json = try ctx.message.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

pub fn generatedComplexProtoNameJsonStringify(ctx: GeneratedComplexJsonStringifyCtx) !void {
    const json = try ctx.message.jsonStringifyAllocWithOptions(ctx.allocator, .{ .preserve_proto_field_names = true });
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

pub const GeneratedComplexJsonParseCtx = struct { allocator: std.mem.Allocator, json: []const u8 };

pub fn generatedComplexJsonParse(ctx: GeneratedComplexJsonParseCtx) !void {
    var decoded = try person_pb.demo.Complex.jsonParse(ctx.allocator, ctx.json);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedComplexTextFormatCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.Complex };

pub fn generatedComplexTextFormat(ctx: GeneratedComplexTextFormatCtx) !void {
    const text = try ctx.message.formatTextAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(text.ptr);
    ctx.allocator.free(text);
}

pub const GeneratedComplexTextParseCtx = struct { allocator: std.mem.Allocator, text: []const u8 };

pub fn generatedComplexTextParse(ctx: GeneratedComplexTextParseCtx) !void {
    var decoded = try person_pb.demo.Complex.parseText(ctx.allocator, ctx.text);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedLargeMapJsonStringifyCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.LargeMap };

pub fn generatedLargeMapJsonStringify(ctx: GeneratedLargeMapJsonStringifyCtx) !void {
    const json = try ctx.message.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

pub const GeneratedLargeMapJsonParseCtx = struct { allocator: std.mem.Allocator, json: []const u8 };

pub fn generatedLargeMapJsonParse(ctx: GeneratedLargeMapJsonParseCtx) !void {
    var decoded = try person_pb.demo.LargeMap.jsonParse(ctx.allocator, ctx.json);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedJsonStringifyCtx = struct { allocator: std.mem.Allocator, person: *const person_pb.demo.Person };

pub fn generatedJsonStringify(ctx: GeneratedJsonStringifyCtx) !void {
    const json = try ctx.person.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

pub fn generatedAlwaysPrintJsonStringify(ctx: GeneratedJsonStringifyCtx) !void {
    const json = try ctx.person.jsonStringifyAllocWithOptions(ctx.allocator, .{ .always_print_primitive_fields = true });
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

pub const GeneratedScalarMixJsonStringifyCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.ScalarMix };

pub fn generatedScalarMixJsonStringify(ctx: GeneratedScalarMixJsonStringifyCtx) !void {
    const json = try ctx.message.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

pub fn generatedScalarMixProtoNameJsonStringify(ctx: GeneratedScalarMixJsonStringifyCtx) !void {
    const json = try ctx.message.jsonStringifyAllocWithOptions(ctx.allocator, .{ .preserve_proto_field_names = true });
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

pub fn generatedScalarMixEnumNumberJsonStringify(ctx: GeneratedScalarMixJsonStringifyCtx) !void {
    const json = try ctx.message.jsonStringifyAllocWithOptions(ctx.allocator, .{ .enum_as_name = false });
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

pub const GeneratedJsonParseCtx = struct { allocator: std.mem.Allocator, json: []const u8 };

pub fn generatedJsonParse(ctx: GeneratedJsonParseCtx) !void {
    var decoded = try person_pb.demo.Person.jsonParse(ctx.allocator, ctx.json);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub fn generatedIgnoreUnknownJsonParse(ctx: GeneratedJsonParseCtx) !void {
    var decoded = try person_pb.demo.Person.jsonParseWithOptions(ctx.allocator, ctx.json, .{ .ignore_unknown_fields = true });
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedScalarMixJsonParseCtx = struct { allocator: std.mem.Allocator, json: []const u8 };

pub fn generatedScalarMixJsonParse(ctx: GeneratedScalarMixJsonParseCtx) !void {
    var decoded = try person_pb.demo.ScalarMix.jsonParse(ctx.allocator, ctx.json);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const DynamicJsonStringifyCtx = struct { allocator: std.mem.Allocator, file: *const pbz.FileDescriptor, message: *const pbz.DynamicMessage };

pub fn dynamicJsonStringify(ctx: DynamicJsonStringifyCtx) !void {
    const json = try pbz.stringifyJsonAlloc(ctx.allocator, ctx.file, ctx.message, .{});
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

pub const DynamicJsonParseCtx = struct { allocator: std.mem.Allocator, file: *const pbz.FileDescriptor, descriptor: *const pbz.MessageDescriptor, json: []const u8 };

pub fn dynamicJsonParse(ctx: DynamicJsonParseCtx) !void {
    var msg = try pbz.parseJsonAlloc(ctx.allocator, ctx.file, ctx.descriptor, ctx.json, .{});
    std.mem.doNotOptimizeAway(&msg);
    msg.deinit();
}

pub const AnyWktJsonStringifyCtx = struct { allocator: std.mem.Allocator, any: *const pbz.Any };

pub fn anyWktJsonStringify(ctx: AnyWktJsonStringifyCtx) !void {
    const json = try ctx.any.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

pub const AnyWktJsonParseCtx = struct { allocator: std.mem.Allocator, json: []const u8 };

pub fn anyWktJsonParse(ctx: AnyWktJsonParseCtx) !void {
    var any = try pbz.Any.jsonParse(ctx.allocator, ctx.json);
    std.mem.doNotOptimizeAway(&any);
    any.deinit(ctx.allocator);
}

pub const DurationJsonStringifyCtx = struct { allocator: std.mem.Allocator, duration: pbz.Duration };

pub fn durationJsonStringify(ctx: DurationJsonStringifyCtx) !void {
    const json = try ctx.duration.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

pub const DurationJsonParseCtx = struct { json: []const u8 };

pub fn durationJsonParse(ctx: DurationJsonParseCtx) !void {
    const duration = try pbz.Duration.jsonParse(ctx.json);
    std.mem.doNotOptimizeAway(duration);
}

pub const FieldMaskJsonStringifyCtx = struct { allocator: std.mem.Allocator, mask: *const pbz.FieldMask };

pub fn fieldMaskJsonStringify(ctx: FieldMaskJsonStringifyCtx) !void {
    const json = try ctx.mask.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

pub const FieldMaskJsonParseCtx = struct { allocator: std.mem.Allocator, json: []const u8 };

pub fn fieldMaskJsonParse(ctx: FieldMaskJsonParseCtx) !void {
    const paths = try pbz.FieldMask.jsonParse(ctx.allocator, ctx.json);
    std.mem.doNotOptimizeAway(paths.ptr);
    for (paths) |path| ctx.allocator.free(path);
    ctx.allocator.free(paths);
}

pub const TimestampJsonStringifyCtx = struct { allocator: std.mem.Allocator, timestamp: pbz.Timestamp };

pub fn timestampJsonStringify(ctx: TimestampJsonStringifyCtx) !void {
    const json = try ctx.timestamp.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

pub const TimestampJsonParseCtx = struct { json: []const u8 };

pub fn timestampJsonParse(ctx: TimestampJsonParseCtx) !void {
    const timestamp = try pbz.Timestamp.jsonParse(ctx.json);
    std.mem.doNotOptimizeAway(timestamp);
}

pub const EmptyJsonStringifyCtx = struct { allocator: std.mem.Allocator };

pub fn emptyJsonStringify(ctx: EmptyJsonStringifyCtx) !void {
    var out: std.Io.Writer.Allocating = .init(ctx.allocator);
    defer out.deinit();
    try pbz.Empty.jsonStringify(&out.writer);
    std.mem.doNotOptimizeAway(out.written().ptr);
}

pub const EmptyJsonParseCtx = struct { allocator: std.mem.Allocator, json: []const u8 };

pub fn emptyJsonParse(ctx: EmptyJsonParseCtx) !void {
    const value = try pbz.Empty.jsonParse(ctx.allocator, ctx.json);
    std.mem.doNotOptimizeAway(value);
}

pub fn WktJsonStringifyCtx(comptime Value: type) type {
    return struct { allocator: std.mem.Allocator, value: Value };
}

pub fn wktJsonStringify(ctx: anytype) !void {
    const json = try ctx.value.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

pub fn WktJsonParseCtx(comptime Value: type) type {
    return struct {
        allocator: std.mem.Allocator,
        json: []const u8,
        const Wkt = Value;
    };
}

pub fn wktJsonParse(ctx: anytype) !void {
    var value = try @TypeOf(ctx).Wkt.jsonParse(ctx.allocator, ctx.json);
    std.mem.doNotOptimizeAway(&value);
    value.deinit(ctx.allocator);
}

pub const GeneratedTextFormatCtx = struct { allocator: std.mem.Allocator, person: *const person_pb.demo.Person };

pub fn generatedTextFormat(ctx: GeneratedTextFormatCtx) !void {
    const text = try ctx.person.formatTextAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(text.ptr);
    ctx.allocator.free(text);
}

pub const GeneratedTextParseCtx = struct { allocator: std.mem.Allocator, text: []const u8 };

pub fn generatedTextParse(ctx: GeneratedTextParseCtx) !void {
    var decoded = try person_pb.demo.Person.parseText(ctx.allocator, ctx.text);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const DynamicTextFormatCtx = struct { allocator: std.mem.Allocator, file: *const pbz.FileDescriptor, message: *const pbz.DynamicMessage };

pub fn dynamicTextFormat(ctx: DynamicTextFormatCtx) !void {
    const text = try pbz.formatTextAlloc(ctx.allocator, ctx.file, ctx.message, .{});
    std.mem.doNotOptimizeAway(text.ptr);
    ctx.allocator.free(text);
}

pub const DynamicTextParseCtx = struct { allocator: std.mem.Allocator, file: *const pbz.FileDescriptor, descriptor: *const pbz.MessageDescriptor, text: []const u8 };

pub fn dynamicTextParse(ctx: DynamicTextParseCtx) !void {
    var msg = try pbz.parseTextAlloc(ctx.allocator, ctx.file, ctx.descriptor, ctx.text);
    std.mem.doNotOptimizeAway(&msg);
    msg.deinit();
}
