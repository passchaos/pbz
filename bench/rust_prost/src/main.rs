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
    let packed = make_packed();
    let packed_bytes = packed.encode_to_vec();
    let fixed_packed = make_fixed_packed();
    let fixed_packed_bytes = fixed_packed.encode_to_vec();
    let fixed64_packed = make_fixed64_packed();
    let fixed64_packed_bytes = fixed64_packed.encode_to_vec();

    println!("rust prost benchmark baseline");
    println!("payload size: {}", bytes.len());
    println!("packed payload size: {}", packed_bytes.len());
    println!("fixed32 packed payload size: {}", fixed_packed_bytes.len());
    println!(
        "fixed64 packed payload size: {}",
        fixed64_packed_bytes.len()
    );

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
}
