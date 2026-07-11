use prost::Message;
use std::collections::HashMap;
use std::time::{Duration, Instant};

const BENCHMARK_SAMPLES: usize = 3;

#[derive(Clone, PartialEq, Message)]
pub struct Person {
    #[prost(int32, tag = "1")]
    pub id: i32,
    #[prost(string, tag = "2")]
    pub name: String,
    #[prost(int32, repeated, tag = "3")]
    pub scores: Vec<i32>,
    #[prost(map = "string, int32", tag = "4")]
    pub counts: HashMap<String, i32>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
#[repr(i32)]
pub enum BenchKind {
    Unknown = 0,
    Alpha = 1,
    Beta = 2,
}

#[derive(Clone, PartialEq, Message)]
pub struct ScalarMix {
    #[prost(bool, tag = "1")]
    pub active: bool,
    #[prost(uint32, tag = "2")]
    pub count: u32,
    #[prost(uint64, tag = "3")]
    pub total: u64,
    #[prost(sint32, tag = "4")]
    pub delta: i32,
    #[prost(sint64, tag = "5")]
    pub big_delta: i64,
    #[prost(fixed32, tag = "6")]
    pub checksum: u32,
    #[prost(fixed64, tag = "7")]
    pub token: u64,
    #[prost(sfixed32, tag = "8")]
    pub signed_fixed: i32,
    #[prost(sfixed64, tag = "9")]
    pub signed_big_fixed: i64,
    #[prost(float, tag = "10")]
    pub ratio: f32,
    #[prost(double, tag = "11")]
    pub score: f64,
    #[prost(enumeration = "BenchKind", tag = "12")]
    pub kind: i32,
    #[prost(bool, repeated, tag = "13")]
    pub flags: Vec<bool>,
    #[prost(uint64, repeated, tag = "14")]
    pub ids: Vec<u64>,
}

#[derive(Clone, PartialEq, Message)]
pub struct TextBytes {
    #[prost(string, tag = "1")]
    pub title: String,
    #[prost(bytes, tag = "2")]
    pub payload: Vec<u8>,
    #[prost(string, repeated, tag = "3")]
    pub tags: Vec<String>,
    #[prost(bytes, repeated, tag = "4")]
    pub chunks: Vec<Vec<u8>>,
}

#[derive(Clone, PartialEq, Message)]
pub struct ComplexAudit {
    #[prost(string, tag = "1")]
    pub actor: String,
    #[prost(int64, tag = "2")]
    pub at_unix: i64,
}

#[derive(Clone, PartialEq, Message)]
pub struct Complex {
    #[prost(int32, tag = "1")]
    pub id: i32,
    #[prost(message, optional, tag = "2")]
    pub audit: Option<ComplexAudit>,
    #[prost(message, repeated, tag = "3")]
    pub history: Vec<ComplexAudit>,
    #[prost(map = "string, message", tag = "4")]
    pub audits: HashMap<String, ComplexAudit>,
    #[prost(oneof = "complex::Subject", tags = "5, 6, 7")]
    pub subject: Option<complex::Subject>,
}

pub mod complex {
    use super::ComplexAudit;
    use prost::Oneof;

    #[derive(Clone, PartialEq, Oneof)]
    pub enum Subject {
        #[prost(string, tag = "5")]
        UserName(String),
        #[prost(bytes, tag = "6")]
        OrganizationId(Vec<u8>),
        #[prost(message, tag = "7")]
        AuditSubject(ComplexAudit),
    }
}

#[derive(Clone, Copy)]
struct Iterations {
    binary: usize,
}

struct BenchResult {
    name: &'static str,
    iterations: usize,
    samples: usize,
    elapsed: Duration,
    bytes_per_iter: usize,
}

impl BenchResult {
    fn print(&self) {
        let elapsed_ns = self.elapsed.as_nanos() as f64;
        let ns_per_iter = elapsed_ns / self.iterations as f64;
        let ops_per_sec = self.iterations as f64 * 1_000_000_000.0 / elapsed_ns;
        let mib_per_sec = self.bytes_per_iter as f64 * self.iterations as f64 * 1_000_000_000.0
            / elapsed_ns
            / (1024.0 * 1024.0);
        println!(
            "{}: best of {} x {} iters, {} bytes/iter, {:.2} ns/op, {:.2} ops/s, {:.2} MiB/s",
            self.name,
            self.samples,
            self.iterations,
            self.bytes_per_iter,
            ns_per_iter,
            ops_per_sec,
            mib_per_sec
        );
    }
}

#[derive(Clone, PartialEq, Message)]
pub struct Packed {
    #[prost(int32, repeated, tag = "1")]
    pub values: Vec<i32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct FixedPacked {
    #[prost(fixed32, repeated, tag = "1")]
    pub values: Vec<u32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct Fixed64Packed {
    #[prost(fixed64, repeated, tag = "1")]
    pub values: Vec<u64>,
}

#[derive(Clone, PartialEq, Message)]
pub struct SFixedPacked {
    #[prost(sfixed32, repeated, tag = "1")]
    pub values: Vec<i32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct SFixed64Packed {
    #[prost(sfixed64, repeated, tag = "1")]
    pub values: Vec<i64>,
}

#[derive(Clone, PartialEq, Message)]
pub struct FloatPacked {
    #[prost(float, repeated, tag = "1")]
    pub values: Vec<f32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct DoublePacked {
    #[prost(double, repeated, tag = "1")]
    pub values: Vec<f64>,
}

#[derive(Clone, PartialEq, Message)]
pub struct UInt64Packed {
    #[prost(uint64, repeated, tag = "1")]
    pub values: Vec<u64>,
}

#[derive(Clone, PartialEq, Message)]
pub struct UInt32Packed {
    #[prost(uint32, repeated, tag = "1")]
    pub values: Vec<u32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct Int64Packed {
    #[prost(int64, repeated, tag = "1")]
    pub values: Vec<i64>,
}

#[derive(Clone, PartialEq, Message)]
pub struct SInt32Packed {
    #[prost(sint32, repeated, tag = "1")]
    pub values: Vec<i32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct SInt64Packed {
    #[prost(sint64, repeated, tag = "1")]
    pub values: Vec<i64>,
}

#[derive(Clone, PartialEq, Message)]
pub struct BoolPacked {
    #[prost(bool, repeated, tag = "1")]
    pub values: Vec<bool>,
}

#[derive(Clone, PartialEq, Message)]
pub struct EnumPacked {
    #[prost(enumeration = "BenchKind", repeated, tag = "1")]
    pub values: Vec<i32>,
}

#[derive(Clone, PartialEq, Message)]
pub struct LargeMap {
    #[prost(map = "string, int32", tag = "1")]
    pub counts: HashMap<String, i32>,
}

fn make_packed() -> Packed {
    Packed {
        values: (0..1024).map(|i| (i % 4096) as i32).collect(),
    }
}

fn make_fixed_packed() -> FixedPacked {
    FixedPacked {
        values: (0..1024).map(|i| (i * 3 + 1) as u32).collect(),
    }
}

fn make_fixed64_packed() -> Fixed64Packed {
    Fixed64Packed {
        values: (0..1024).map(|i| (i * 5 + 1) as u64).collect(),
    }
}

fn make_sfixed_packed() -> SFixedPacked {
    SFixedPacked {
        values: (0..1024)
            .map(|i| {
                let magnitude = (i * 7 + 1) as i32;
                if i & 1 == 0 {
                    magnitude
                } else {
                    -magnitude
                }
            })
            .collect(),
    }
}

fn make_sfixed64_packed() -> SFixed64Packed {
    SFixed64Packed {
        values: (0..1024)
            .map(|i| {
                let magnitude = ((i as i64) << 20) + (i as i64) * 11 + 1;
                if i & 1 == 0 {
                    magnitude
                } else {
                    -magnitude
                }
            })
            .collect(),
    }
}

fn make_float_packed() -> FloatPacked {
    FloatPacked {
        values: (0..1024).map(|i| i as f32 * 0.25 + 1.0).collect(),
    }
}

fn make_double_packed() -> DoublePacked {
    DoublePacked {
        values: (0..1024).map(|i| i as f64 * 0.5 + 1.0).collect(),
    }
}

fn make_uint64_packed() -> UInt64Packed {
    UInt64Packed {
        values: (0..1024)
            .map(|i| ((i as u64) << 21) + (i as u64) * 17 + 1)
            .collect(),
    }
}

fn make_uint32_packed() -> UInt32Packed {
    UInt32Packed {
        values: (0..1024).map(|i| ((i << 12) + i * 3 + 1) as u32).collect(),
    }
}

fn make_int64_packed() -> Int64Packed {
    Int64Packed {
        values: (0..1024)
            .map(|i| {
                let magnitude = ((i as i64) << 20) + (i as i64) * 7 + 1;
                if i & 1 == 0 {
                    magnitude
                } else {
                    -magnitude
                }
            })
            .collect(),
    }
}

fn make_sint32_packed() -> SInt32Packed {
    SInt32Packed {
        values: (0..1024)
            .map(|i| {
                let magnitude = (i * 5 + 1) as i32;
                if i & 1 == 0 {
                    magnitude
                } else {
                    -magnitude
                }
            })
            .collect(),
    }
}

fn make_sint64_packed() -> SInt64Packed {
    SInt64Packed {
        values: (0..1024)
            .map(|i| {
                let magnitude = ((i as i64) << 20) + (i as i64) * 13 + 1;
                if i & 1 == 0 {
                    magnitude
                } else {
                    -magnitude
                }
            })
            .collect(),
    }
}

fn make_bool_packed() -> BoolPacked {
    BoolPacked {
        values: (0..1024).map(|i| i % 3 != 0).collect(),
    }
}

fn make_enum_packed() -> EnumPacked {
    EnumPacked {
        values: (0..1024).map(|i| (i % 3) as i32).collect(),
    }
}

fn make_large_map() -> LargeMap {
    LargeMap {
        counts: (0..1024)
            .map(|i| (format!("key-{i:04}"), ((i % 4096) + 1) as i32))
            .collect(),
    }
}

fn make_person() -> Person {
    let mut counts = HashMap::new();
    counts.insert("red".to_string(), 1);
    counts.insert("green".to_string(), 2);
    counts.insert("blue".to_string(), 3);
    Person {
        id: 7,
        name: "Zig".to_string(),
        scores: vec![10, 20, 30, 40, 50, 60, 70, 80],
        counts,
    }
}

fn make_scalarmix() -> ScalarMix {
    ScalarMix {
        active: true,
        count: 12345,
        total: 9_876_543_210,
        delta: -321,
        big_delta: -9_876_543,
        checksum: 0xdead_beef,
        token: 0x0102_0304_0506_0708,
        signed_fixed: -123456,
        signed_big_fixed: -9_876_543_210,
        ratio: 1.25,
        score: 9.5,
        kind: BenchKind::Beta as i32,
        flags: vec![true, false, true, true, false, true, false, false],
        ids: vec![1, 127, 128, 16_384, 1_048_576, 9_876_543_210],
    }
}

fn make_textbytes() -> TextBytes {
    TextBytes {
        title: "ASCII title for protobuf".to_string(),
        payload: b"0123456789abcdef0123456789abcdef".to_vec(),
        tags: vec![
            "alpha".to_string(),
            "beta".to_string(),
            "gamma".to_string(),
            "delta".to_string(),
        ],
        chunks: vec![
            b"chunk-one".to_vec(),
            b"chunk-two".to_vec(),
            b"chunk-three".to_vec(),
            b"chunk-four".to_vec(),
        ],
    }
}

fn audit(actor: &str, at_unix: i64) -> ComplexAudit {
    ComplexAudit {
        actor: actor.to_string(),
        at_unix,
    }
}

fn make_complex() -> Complex {
    let latest = audit("reviewer", 67890);
    let mut audits = HashMap::new();
    audits.insert("latest".to_string(), latest.clone());
    audits.insert("created".to_string(), audit("creator", 12345));
    Complex {
        id: 42,
        audit: Some(audit("tester", 12345)),
        history: vec![audit("creator", 12345), latest],
        audits,
        subject: Some(complex::Subject::AuditSubject(audit("subject", 777))),
    }
}

fn run_timed<F>(
    name: &'static str,
    iterations: usize,
    bytes_per_iter: usize,
    mut f: F,
) -> BenchResult
where
    F: FnMut(),
{
    let warmup_iterations = (iterations / 10).clamp(1, 1_000);
    for _ in 0..warmup_iterations {
        f();
    }

    let mut best: Option<Duration> = None;
    for _ in 0..BENCHMARK_SAMPLES {
        let start = Instant::now();
        for _ in 0..iterations {
            f();
        }
        let elapsed = start.elapsed();
        if best.map_or(true, |current| elapsed < current) {
            best = Some(elapsed);
        }
    }
    BenchResult {
        name,
        iterations,
        samples: BENCHMARK_SAMPLES,
        elapsed: best.expect("at least one benchmark sample"),
        bytes_per_iter,
    }
}

fn main() {
    let iters = Iterations { binary: 20_000 };
    let large_map_iterations = 1_000;
    let person = make_person();
    let bytes = person.encode_to_vec();
    let scalarmix = make_scalarmix();
    let scalarmix_bytes = scalarmix.encode_to_vec();
    let textbytes = make_textbytes();
    let textbytes_bytes = textbytes.encode_to_vec();
    let complex = make_complex();
    let complex_bytes = complex.encode_to_vec();
    let packed = make_packed();
    let packed_bytes = packed.encode_to_vec();
    let fixed_packed = make_fixed_packed();
    let fixed_packed_bytes = fixed_packed.encode_to_vec();
    let fixed64_packed = make_fixed64_packed();
    let fixed64_packed_bytes = fixed64_packed.encode_to_vec();
    let sfixed_packed = make_sfixed_packed();
    let sfixed_packed_bytes = sfixed_packed.encode_to_vec();
    let sfixed64_packed = make_sfixed64_packed();
    let sfixed64_packed_bytes = sfixed64_packed.encode_to_vec();
    let float_packed = make_float_packed();
    let float_packed_bytes = float_packed.encode_to_vec();
    let double_packed = make_double_packed();
    let double_packed_bytes = double_packed.encode_to_vec();
    let uint64_packed = make_uint64_packed();
    let uint64_packed_bytes = uint64_packed.encode_to_vec();
    let uint32_packed = make_uint32_packed();
    let uint32_packed_bytes = uint32_packed.encode_to_vec();
    let int64_packed = make_int64_packed();
    let int64_packed_bytes = int64_packed.encode_to_vec();
    let sint32_packed = make_sint32_packed();
    let sint32_packed_bytes = sint32_packed.encode_to_vec();
    let sint64_packed = make_sint64_packed();
    let sint64_packed_bytes = sint64_packed.encode_to_vec();
    let bool_packed = make_bool_packed();
    let bool_packed_bytes = bool_packed.encode_to_vec();
    let enum_packed = make_enum_packed();
    let enum_packed_bytes = enum_packed.encode_to_vec();
    let large_map = make_large_map();
    let large_map_bytes = large_map.encode_to_vec();

    println!("rust prost benchmark baseline");
    println!("payload size: {}", bytes.len());
    println!("scalarmix payload size: {}", scalarmix_bytes.len());
    println!("textbytes payload size: {}", textbytes_bytes.len());
    println!("complex payload size: {}", complex_bytes.len());
    println!("packed payload size: {}", packed_bytes.len());
    println!("fixed32 packed payload size: {}", fixed_packed_bytes.len());
    println!(
        "fixed64 packed payload size: {}",
        fixed64_packed_bytes.len()
    );
    println!(
        "sfixed32 packed payload size: {}",
        sfixed_packed_bytes.len()
    );
    println!(
        "sfixed64 packed payload size: {}",
        sfixed64_packed_bytes.len()
    );
    println!("float packed payload size: {}", float_packed_bytes.len());
    println!("double packed payload size: {}", double_packed_bytes.len());
    println!("uint64 packed payload size: {}", uint64_packed_bytes.len());
    println!("uint32 packed payload size: {}", uint32_packed_bytes.len());
    println!("int64 packed payload size: {}", int64_packed_bytes.len());
    println!("sint32 packed payload size: {}", sint32_packed_bytes.len());
    println!("sint64 packed payload size: {}", sint64_packed_bytes.len());
    println!("bool packed payload size: {}", bool_packed_bytes.len());
    println!("enum packed payload size: {}", enum_packed_bytes.len());
    println!("large map payload size: {}", large_map_bytes.len());

    let encode = run_timed("prost binary encode", iters.binary, bytes.len(), || {
        let encoded = person.encode_to_vec();
        std::hint::black_box(encoded);
    });
    encode.print();

    let decode = run_timed("prost binary decode", iters.binary, bytes.len(), || {
        let decoded = Person::decode(bytes.as_slice()).expect("decode");
        std::hint::black_box(decoded);
    });
    decode.print();

    run_timed(
        "prost scalarmix encode",
        iters.binary,
        scalarmix_bytes.len(),
        || {
            let encoded = scalarmix.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost scalarmix decode",
        iters.binary,
        scalarmix_bytes.len(),
        || {
            let decoded = ScalarMix::decode(scalarmix_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "prost textbytes encode",
        iters.binary,
        textbytes_bytes.len(),
        || {
            let encoded = textbytes.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost textbytes decode",
        iters.binary,
        textbytes_bytes.len(),
        || {
            let decoded = TextBytes::decode(textbytes_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "prost complex encode",
        iters.binary,
        complex_bytes.len(),
        || {
            let encoded = complex.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost complex decode",
        iters.binary,
        complex_bytes.len(),
        || {
            let decoded = Complex::decode(complex_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "prost packed encode",
        iters.binary,
        packed_bytes.len(),
        || {
            let encoded = packed.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost packed decode",
        iters.binary,
        packed_bytes.len(),
        || {
            let decoded = Packed::decode(packed_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "prost fixed32 packed encode",
        iters.binary,
        fixed_packed_bytes.len(),
        || {
            let encoded = fixed_packed.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost fixed32 packed decode",
        iters.binary,
        fixed_packed_bytes.len(),
        || {
            let decoded = FixedPacked::decode(fixed_packed_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "prost fixed64 packed encode",
        iters.binary,
        fixed64_packed_bytes.len(),
        || {
            let encoded = fixed64_packed.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost fixed64 packed decode",
        iters.binary,
        fixed64_packed_bytes.len(),
        || {
            let decoded = Fixed64Packed::decode(fixed64_packed_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "prost sfixed32 packed encode",
        iters.binary,
        sfixed_packed_bytes.len(),
        || {
            let encoded = sfixed_packed.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost sfixed32 packed decode",
        iters.binary,
        sfixed_packed_bytes.len(),
        || {
            let decoded = SFixedPacked::decode(sfixed_packed_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "prost sfixed64 packed encode",
        iters.binary,
        sfixed64_packed_bytes.len(),
        || {
            let encoded = sfixed64_packed.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost sfixed64 packed decode",
        iters.binary,
        sfixed64_packed_bytes.len(),
        || {
            let decoded = SFixed64Packed::decode(sfixed64_packed_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "prost float packed encode",
        iters.binary,
        float_packed_bytes.len(),
        || {
            let encoded = float_packed.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost float packed decode",
        iters.binary,
        float_packed_bytes.len(),
        || {
            let decoded = FloatPacked::decode(float_packed_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "prost double packed encode",
        iters.binary,
        double_packed_bytes.len(),
        || {
            let encoded = double_packed.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost double packed decode",
        iters.binary,
        double_packed_bytes.len(),
        || {
            let decoded = DoublePacked::decode(double_packed_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "prost uint64 packed encode",
        iters.binary,
        uint64_packed_bytes.len(),
        || {
            let encoded = uint64_packed.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost uint64 packed decode",
        iters.binary,
        uint64_packed_bytes.len(),
        || {
            let decoded = UInt64Packed::decode(uint64_packed_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "prost uint32 packed encode",
        iters.binary,
        uint32_packed_bytes.len(),
        || {
            let encoded = uint32_packed.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost uint32 packed decode",
        iters.binary,
        uint32_packed_bytes.len(),
        || {
            let decoded = UInt32Packed::decode(uint32_packed_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "prost int64 packed encode",
        iters.binary,
        int64_packed_bytes.len(),
        || {
            let encoded = int64_packed.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost int64 packed decode",
        iters.binary,
        int64_packed_bytes.len(),
        || {
            let decoded = Int64Packed::decode(int64_packed_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "prost sint32 packed encode",
        iters.binary,
        sint32_packed_bytes.len(),
        || {
            let encoded = sint32_packed.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost sint32 packed decode",
        iters.binary,
        sint32_packed_bytes.len(),
        || {
            let decoded = SInt32Packed::decode(sint32_packed_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "prost sint64 packed encode",
        iters.binary,
        sint64_packed_bytes.len(),
        || {
            let encoded = sint64_packed.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost sint64 packed decode",
        iters.binary,
        sint64_packed_bytes.len(),
        || {
            let decoded = SInt64Packed::decode(sint64_packed_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "prost bool packed encode",
        iters.binary,
        bool_packed_bytes.len(),
        || {
            let encoded = bool_packed.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost bool packed decode",
        iters.binary,
        bool_packed_bytes.len(),
        || {
            let decoded = BoolPacked::decode(bool_packed_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "prost enum packed encode",
        iters.binary,
        enum_packed_bytes.len(),
        || {
            let encoded = enum_packed.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost enum packed decode",
        iters.binary,
        enum_packed_bytes.len(),
        || {
            let decoded = EnumPacked::decode(enum_packed_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "prost large map encode",
        large_map_iterations,
        large_map_bytes.len(),
        || {
            let encoded = large_map.encode_to_vec();
            std::hint::black_box(encoded);
        },
    )
    .print();

    run_timed(
        "prost large map decode",
        large_map_iterations,
        large_map_bytes.len(),
        || {
            let decoded = LargeMap::decode(large_map_bytes.as_slice()).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();
}
