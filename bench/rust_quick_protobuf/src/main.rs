use quick_protobuf::sizeofs;
use quick_protobuf::{BytesReader, MessageRead, MessageWrite, Result, Writer, WriterBackend};
use std::collections::HashMap;
use std::time::{Duration, Instant};

const BENCHMARK_SAMPLES: usize = 3;

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Person {
    pub id: i32,
    pub name: String,
    pub scores: Vec<i32>,
    pub counts: HashMap<String, i32>,
}

impl MessageWrite for Person {
    fn get_size(&self) -> usize {
        let mut size = 0usize;
        if self.id != 0 {
            size += 1 + sizeofs::sizeof_int32(self.id);
        }
        if !self.name.is_empty() {
            size += 1 + sizeofs::sizeof_len(self.name.len());
        }
        if !self.scores.is_empty() {
            let packed_len: usize = self.scores.iter().map(|v| sizeofs::sizeof_int32(*v)).sum();
            size += 1 + sizeofs::sizeof_len(packed_len);
        }
        for (key, value) in &self.counts {
            let entry_len = 1 + sizeofs::sizeof_len(key.len()) + 1 + sizeofs::sizeof_int32(*value);
            size += 1 + sizeofs::sizeof_len(entry_len);
        }
        size
    }

    fn write_message<W: WriterBackend>(&self, w: &mut Writer<W>) -> Result<()> {
        if self.id != 0 {
            w.write_with_tag(8, |w| w.write_int32(self.id))?;
        }
        if !self.name.is_empty() {
            w.write_with_tag(18, |w| w.write_string(&self.name))?;
        }
        if !self.scores.is_empty() {
            w.write_packed_with_tag(26, &self.scores, |w, v| w.write_int32(*v), &|v| {
                sizeofs::sizeof_int32(*v)
            })?;
        }
        for (key, value) in &self.counts {
            let entry_len = 1 + sizeofs::sizeof_len(key.len()) + 1 + sizeofs::sizeof_int32(*value);
            w.write_with_tag(34, |w| {
                w.write_map(
                    entry_len,
                    10,
                    |w| w.write_string(key),
                    16,
                    |w| w.write_int32(*value),
                )
            })?;
        }
        Ok(())
    }
}

impl<'a> MessageRead<'a> for Person {
    fn from_reader(r: &mut BytesReader, bytes: &'a [u8]) -> Result<Self> {
        let mut msg = Person::default();
        while !r.is_eof() {
            match r.next_tag(bytes)? {
                8 => msg.id = r.read_int32(bytes)?,
                18 => msg.name = r.read_string(bytes)?.to_owned(),
                26 => msg.scores = r.read_packed(bytes, |r, bytes| r.read_int32(bytes))?,
                34 => {
                    let (key, value) = r.read_map(
                        bytes,
                        |r, bytes| Ok(r.read_string(bytes)?.to_owned()),
                        |r, bytes| r.read_int32(bytes),
                    )?;
                    msg.counts.insert(key, value);
                }
                tag => r.read_unknown(bytes, tag)?,
            }
        }
        Ok(msg)
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

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Packed {
    pub values: Vec<i32>,
}

impl MessageWrite for Packed {
    fn get_size(&self) -> usize {
        if self.values.is_empty() {
            return 0;
        }
        let packed_len: usize = self.values.iter().map(|v| sizeofs::sizeof_int32(*v)).sum();
        1 + sizeofs::sizeof_len(packed_len)
    }
    fn write_message<W: WriterBackend>(&self, w: &mut Writer<W>) -> Result<()> {
        if !self.values.is_empty() {
            w.write_packed_with_tag(10, &self.values, |w, v| w.write_int32(*v), &|v| {
                sizeofs::sizeof_int32(*v)
            })?;
        }
        Ok(())
    }
}

impl<'a> MessageRead<'a> for Packed {
    fn from_reader(r: &mut BytesReader, bytes: &'a [u8]) -> Result<Self> {
        let mut msg = Packed::default();
        while !r.is_eof() {
            match r.next_tag(bytes)? {
                10 => msg.values = r.read_packed(bytes, |r, bytes| r.read_int32(bytes))?,
                tag => r.read_unknown(bytes, tag)?,
            }
        }
        Ok(msg)
    }
}

fn make_packed() -> Packed {
    Packed {
        values: (0..1024).map(|i| (i % 4096) as i32).collect(),
    }
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct FixedPacked {
    pub values: Vec<u32>,
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Fixed64Packed {
    pub values: Vec<u64>,
}

impl MessageWrite for FixedPacked {
    fn get_size(&self) -> usize {
        if self.values.is_empty() {
            return 0;
        }
        let packed_len = self.values.len() * 4;
        1 + sizeofs::sizeof_len(packed_len)
    }
    fn write_message<W: WriterBackend>(&self, w: &mut Writer<W>) -> Result<()> {
        if !self.values.is_empty() {
            w.write_packed_with_tag(10, &self.values, |w, v| w.write_fixed32(*v), &|_| 4)?;
        }
        Ok(())
    }
}

impl<'a> MessageRead<'a> for FixedPacked {
    fn from_reader(r: &mut BytesReader, bytes: &'a [u8]) -> Result<Self> {
        let mut msg = FixedPacked::default();
        while !r.is_eof() {
            match r.next_tag(bytes)? {
                10 => msg.values = r.read_packed(bytes, |r, bytes| r.read_fixed32(bytes))?,
                tag => r.read_unknown(bytes, tag)?,
            }
        }
        Ok(msg)
    }
}

fn make_fixed_packed() -> FixedPacked {
    FixedPacked {
        values: (0..1024).map(|i| (i * 3 + 1) as u32).collect(),
    }
}

impl MessageWrite for Fixed64Packed {
    fn get_size(&self) -> usize {
        if self.values.is_empty() {
            return 0;
        }
        let packed_len = self.values.len() * 8;
        1 + sizeofs::sizeof_len(packed_len)
    }
    fn write_message<W: WriterBackend>(&self, w: &mut Writer<W>) -> Result<()> {
        if !self.values.is_empty() {
            w.write_packed_with_tag(10, &self.values, |w, v| w.write_fixed64(*v), &|_| 8)?;
        }
        Ok(())
    }
}

impl<'a> MessageRead<'a> for Fixed64Packed {
    fn from_reader(r: &mut BytesReader, bytes: &'a [u8]) -> Result<Self> {
        let mut msg = Fixed64Packed::default();
        while !r.is_eof() {
            match r.next_tag(bytes)? {
                10 => msg.values = r.read_packed(bytes, |r, bytes| r.read_fixed64(bytes))?,
                tag => r.read_unknown(bytes, tag)?,
            }
        }
        Ok(msg)
    }
}

fn make_fixed64_packed() -> Fixed64Packed {
    Fixed64Packed {
        values: (0..1024).map(|i| (i * 5 + 1) as u64).collect(),
    }
}

fn make_person() -> Person {
    let mut counts = HashMap::new();
    counts.insert("red".to_owned(), 1);
    counts.insert("green".to_owned(), 2);
    counts.insert("blue".to_owned(), 3);
    Person {
        id: 7,
        name: "Zig".to_owned(),
        scores: vec![10, 20, 30, 40, 50, 60, 70, 80],
        counts,
    }
}

fn encode_to_vec<M: MessageWrite>(message: &M) -> Vec<u8> {
    let mut out = Vec::with_capacity(message.get_size());
    {
        let mut writer = Writer::new(&mut out);
        message.write_message(&mut writer).expect("encode");
    }
    out
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
    let bytes = encode_to_vec(&person);
    let packed = make_packed();
    let packed_bytes = encode_to_vec(&packed);
    let fixed_packed = make_fixed_packed();
    let fixed_packed_bytes = encode_to_vec(&fixed_packed);
    let fixed64_packed = make_fixed64_packed();
    let fixed64_packed_bytes = encode_to_vec(&fixed64_packed);

    println!("rust quick-protobuf benchmark baseline");
    println!("payload size: {}", bytes.len());
    println!("packed payload size: {}", packed_bytes.len());
    println!("fixed32 packed payload size: {}", fixed_packed_bytes.len());
    println!(
        "fixed64 packed payload size: {}",
        fixed64_packed_bytes.len()
    );

    run_timed(
        "quick-protobuf binary encode",
        iters.binary,
        bytes.len(),
        || {
            let encoded = encode_to_vec(&person);
            std::hint::black_box(encoded);
        },
    )
    .print();

    let mut reused = Vec::with_capacity(bytes.len());
    run_timed(
        "quick-protobuf binary encode reuse",
        iters.binary,
        bytes.len(),
        || {
            reused.clear();
            let mut writer = Writer::new(&mut reused);
            person.write_message(&mut writer).expect("encode");
            std::hint::black_box(&reused);
        },
    )
    .print();

    run_timed(
        "quick-protobuf binary decode",
        iters.binary,
        bytes.len(),
        || {
            let mut reader = BytesReader::from_bytes(&bytes);
            let decoded = Person::from_reader(&mut reader, &bytes).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "quick-protobuf packed encode",
        iters.binary,
        packed_bytes.len(),
        || {
            let encoded = encode_to_vec(&packed);
            std::hint::black_box(encoded);
        },
    )
    .print();

    let mut reused_packed = Vec::with_capacity(packed_bytes.len());
    run_timed(
        "quick-protobuf packed encode reuse",
        iters.binary,
        packed_bytes.len(),
        || {
            reused_packed.clear();
            let mut writer = Writer::new(&mut reused_packed);
            packed.write_message(&mut writer).expect("encode");
            std::hint::black_box(&reused_packed);
        },
    )
    .print();

    run_timed(
        "quick-protobuf packed decode",
        iters.binary,
        packed_bytes.len(),
        || {
            let mut reader = BytesReader::from_bytes(&packed_bytes);
            let decoded = Packed::from_reader(&mut reader, &packed_bytes).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "quick-protobuf fixed32 packed encode",
        iters.binary,
        fixed_packed_bytes.len(),
        || {
            let encoded = encode_to_vec(&fixed_packed);
            std::hint::black_box(encoded);
        },
    )
    .print();

    let mut reused_fixed_packed = Vec::with_capacity(fixed_packed_bytes.len());
    run_timed(
        "quick-protobuf fixed32 packed encode reuse",
        iters.binary,
        fixed_packed_bytes.len(),
        || {
            reused_fixed_packed.clear();
            let mut writer = Writer::new(&mut reused_fixed_packed);
            fixed_packed.write_message(&mut writer).expect("encode");
            std::hint::black_box(&reused_fixed_packed);
        },
    )
    .print();

    run_timed(
        "quick-protobuf fixed32 packed decode",
        iters.binary,
        fixed_packed_bytes.len(),
        || {
            let mut reader = BytesReader::from_bytes(&fixed_packed_bytes);
            let decoded =
                FixedPacked::from_reader(&mut reader, &fixed_packed_bytes).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "quick-protobuf fixed64 packed encode",
        iters.binary,
        fixed64_packed_bytes.len(),
        || {
            let encoded = encode_to_vec(&fixed64_packed);
            std::hint::black_box(encoded);
        },
    )
    .print();

    let mut reused_fixed64_packed = Vec::with_capacity(fixed64_packed_bytes.len());
    run_timed(
        "quick-protobuf fixed64 packed encode reuse",
        iters.binary,
        fixed64_packed_bytes.len(),
        || {
            reused_fixed64_packed.clear();
            let mut writer = Writer::new(&mut reused_fixed64_packed);
            fixed64_packed.write_message(&mut writer).expect("encode");
            std::hint::black_box(&reused_fixed64_packed);
        },
    )
    .print();

    run_timed(
        "quick-protobuf fixed64 packed decode",
        iters.binary,
        fixed64_packed_bytes.len(),
        || {
            let mut reader = BytesReader::from_bytes(&fixed64_packed_bytes);
            let decoded =
                Fixed64Packed::from_reader(&mut reader, &fixed64_packed_bytes).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();
}
