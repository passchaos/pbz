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
pub struct UInt64Packed {
    #[prost(uint64, repeated, tag = "1")]
    pub values: Vec<u64>,
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

fn make_uint64_packed() -> UInt64Packed {
    UInt64Packed {
        values: (0..1024)
            .map(|i| ((i as u64) << 21) + (i as u64) * 17 + 1)
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
    let uint64_packed = make_uint64_packed();
    let uint64_packed_bytes = uint64_packed.encode_to_vec();

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
    println!("uint64 packed payload size: {}", uint64_packed_bytes.len());

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
}
