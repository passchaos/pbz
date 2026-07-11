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

#[derive(Debug, Default, Clone, PartialEq)]
pub struct ScalarMix {
    pub active: bool,
    pub count: u32,
    pub total: u64,
    pub delta: i32,
    pub big_delta: i64,
    pub checksum: u32,
    pub token: u64,
    pub signed_fixed: i32,
    pub signed_big_fixed: i64,
    pub ratio: f32,
    pub score: f64,
    pub kind: i32,
    pub flags: Vec<bool>,
    pub ids: Vec<u64>,
}

fn sizeof_sint32(v: i32) -> usize {
    sizeofs::sizeof_uint32(((v << 1) ^ (v >> 31)) as u32)
}
fn sizeof_sint64(v: i64) -> usize {
    sizeofs::sizeof_uint64(((v << 1) ^ (v >> 63)) as u64)
}

impl MessageWrite for ScalarMix {
    fn get_size(&self) -> usize {
        let mut size = 0usize;
        if self.active {
            size += 2;
        }
        if self.count != 0 {
            size += 1 + sizeofs::sizeof_uint32(self.count);
        }
        if self.total != 0 {
            size += 1 + sizeofs::sizeof_uint64(self.total);
        }
        if self.delta != 0 {
            size += 1 + sizeof_sint32(self.delta);
        }
        if self.big_delta != 0 {
            size += 1 + sizeof_sint64(self.big_delta);
        }
        if self.checksum != 0 {
            size += 1 + 4;
        }
        if self.token != 0 {
            size += 1 + 8;
        }
        if self.signed_fixed != 0 {
            size += 1 + 4;
        }
        if self.signed_big_fixed != 0 {
            size += 1 + 8;
        }
        if self.ratio != 0.0 {
            size += 1 + 4;
        }
        if self.score != 0.0 {
            size += 1 + 8;
        }
        if self.kind != 0 {
            size += 1 + sizeofs::sizeof_int32(self.kind);
        }
        if !self.flags.is_empty() {
            size += 1 + sizeofs::sizeof_len(self.flags.len());
        }
        if !self.ids.is_empty() {
            let len: usize = self.ids.iter().map(|v| sizeofs::sizeof_uint64(*v)).sum();
            size += 2 + sizeofs::sizeof_len(len);
        }
        size
    }
    fn write_message<W: WriterBackend>(&self, w: &mut Writer<W>) -> Result<()> {
        if self.active {
            w.write_with_tag(8, |w| w.write_bool(self.active))?;
        }
        if self.count != 0 {
            w.write_with_tag(16, |w| w.write_uint32(self.count))?;
        }
        if self.total != 0 {
            w.write_with_tag(24, |w| w.write_uint64(self.total))?;
        }
        if self.delta != 0 {
            w.write_with_tag(32, |w| w.write_sint32(self.delta))?;
        }
        if self.big_delta != 0 {
            w.write_with_tag(40, |w| w.write_sint64(self.big_delta))?;
        }
        if self.checksum != 0 {
            w.write_with_tag(53, |w| w.write_fixed32(self.checksum))?;
        }
        if self.token != 0 {
            w.write_with_tag(57, |w| w.write_fixed64(self.token))?;
        }
        if self.signed_fixed != 0 {
            w.write_with_tag(69, |w| w.write_sfixed32(self.signed_fixed))?;
        }
        if self.signed_big_fixed != 0 {
            w.write_with_tag(73, |w| w.write_sfixed64(self.signed_big_fixed))?;
        }
        if self.ratio != 0.0 {
            w.write_with_tag(85, |w| w.write_float(self.ratio))?;
        }
        if self.score != 0.0 {
            w.write_with_tag(89, |w| w.write_double(self.score))?;
        }
        if self.kind != 0 {
            w.write_with_tag(96, |w| w.write_int32(self.kind))?;
        }
        if !self.flags.is_empty() {
            w.write_packed_with_tag(106, &self.flags, |w, v| w.write_bool(*v), &|_| 1)?;
        }
        if !self.ids.is_empty() {
            w.write_packed_with_tag(114, &self.ids, |w, v| w.write_uint64(*v), &|v| {
                sizeofs::sizeof_uint64(*v)
            })?;
        }
        Ok(())
    }
}

impl<'a> MessageRead<'a> for ScalarMix {
    fn from_reader(r: &mut BytesReader, bytes: &'a [u8]) -> Result<Self> {
        let mut msg = ScalarMix::default();
        while !r.is_eof() {
            match r.next_tag(bytes)? {
                8 => msg.active = r.read_bool(bytes)?,
                16 => msg.count = r.read_uint32(bytes)?,
                24 => msg.total = r.read_uint64(bytes)?,
                32 => msg.delta = r.read_sint32(bytes)?,
                40 => msg.big_delta = r.read_sint64(bytes)?,
                53 => msg.checksum = r.read_fixed32(bytes)?,
                57 => msg.token = r.read_fixed64(bytes)?,
                69 => msg.signed_fixed = r.read_sfixed32(bytes)?,
                73 => msg.signed_big_fixed = r.read_sfixed64(bytes)?,
                85 => msg.ratio = r.read_float(bytes)?,
                89 => msg.score = r.read_double(bytes)?,
                96 => msg.kind = r.read_int32(bytes)?,
                106 => msg.flags = r.read_packed(bytes, |r, bytes| r.read_bool(bytes))?,
                114 => msg.ids = r.read_packed(bytes, |r, bytes| r.read_uint64(bytes))?,
                tag => r.read_unknown(bytes, tag)?,
            }
        }
        Ok(msg)
    }
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct TextBytes {
    pub title: String,
    pub payload: Vec<u8>,
    pub tags: Vec<String>,
    pub chunks: Vec<Vec<u8>>,
}

impl MessageWrite for TextBytes {
    fn get_size(&self) -> usize {
        let mut size = 0usize;
        if !self.title.is_empty() {
            size += 1 + sizeofs::sizeof_len(self.title.len());
        }
        if !self.payload.is_empty() {
            size += 1 + sizeofs::sizeof_len(self.payload.len());
        }
        for tag in &self.tags {
            size += 1 + sizeofs::sizeof_len(tag.len());
        }
        for chunk in &self.chunks {
            size += 1 + sizeofs::sizeof_len(chunk.len());
        }
        size
    }
    fn write_message<W: WriterBackend>(&self, w: &mut Writer<W>) -> Result<()> {
        if !self.title.is_empty() {
            w.write_with_tag(10, |w| w.write_string(&self.title))?;
        }
        if !self.payload.is_empty() {
            w.write_with_tag(18, |w| w.write_bytes(&self.payload))?;
        }
        for tag in &self.tags {
            w.write_with_tag(26, |w| w.write_string(tag))?;
        }
        for chunk in &self.chunks {
            w.write_with_tag(34, |w| w.write_bytes(chunk))?;
        }
        Ok(())
    }
}

impl<'a> MessageRead<'a> for TextBytes {
    fn from_reader(r: &mut BytesReader, bytes: &'a [u8]) -> Result<Self> {
        let mut msg = TextBytes::default();
        while !r.is_eof() {
            match r.next_tag(bytes)? {
                10 => msg.title = r.read_string(bytes)?.to_owned(),
                18 => msg.payload = r.read_bytes(bytes)?.to_vec(),
                26 => msg.tags.push(r.read_string(bytes)?.to_owned()),
                34 => msg.chunks.push(r.read_bytes(bytes)?.to_vec()),
                tag => r.read_unknown(bytes, tag)?,
            }
        }
        Ok(msg)
    }
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct ComplexAudit {
    pub actor: String,
    pub at_unix: i64,
}

impl MessageWrite for ComplexAudit {
    fn get_size(&self) -> usize {
        let mut size = 0usize;
        if !self.actor.is_empty() {
            size += 1 + sizeofs::sizeof_len(self.actor.len());
        }
        if self.at_unix != 0 {
            size += 1 + sizeofs::sizeof_int64(self.at_unix);
        }
        size
    }

    fn write_message<W: WriterBackend>(&self, w: &mut Writer<W>) -> Result<()> {
        if !self.actor.is_empty() {
            w.write_with_tag(10, |w| w.write_string(&self.actor))?;
        }
        if self.at_unix != 0 {
            w.write_with_tag(16, |w| w.write_int64(self.at_unix))?;
        }
        Ok(())
    }
}

impl<'a> MessageRead<'a> for ComplexAudit {
    fn from_reader(r: &mut BytesReader, bytes: &'a [u8]) -> Result<Self> {
        let mut msg = ComplexAudit::default();
        while !r.is_eof() {
            match r.next_tag(bytes)? {
                10 => msg.actor = r.read_string(bytes)?.to_owned(),
                16 => msg.at_unix = r.read_int64(bytes)?,
                tag => r.read_unknown(bytes, tag)?,
            }
        }
        Ok(msg)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum ComplexSubject {
    UserName(String),
    OrganizationId(Vec<u8>),
    AuditSubject(ComplexAudit),
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Complex {
    pub id: i32,
    pub audit: Option<ComplexAudit>,
    pub history: Vec<ComplexAudit>,
    pub audits: HashMap<String, ComplexAudit>,
    pub subject: Option<ComplexSubject>,
}

impl MessageWrite for Complex {
    fn get_size(&self) -> usize {
        let mut size = 0usize;
        if self.id != 0 {
            size += 1 + sizeofs::sizeof_int32(self.id);
        }
        if let Some(audit) = &self.audit {
            let len = audit.get_size();
            size += 1 + sizeofs::sizeof_len(len);
        }
        for item in &self.history {
            let len = item.get_size();
            size += 1 + sizeofs::sizeof_len(len);
        }
        for (key, value) in &self.audits {
            let value_len = value.get_size();
            let entry_len = 1 + sizeofs::sizeof_len(key.len()) + 1 + sizeofs::sizeof_len(value_len);
            size += 1 + sizeofs::sizeof_len(entry_len);
        }
        match &self.subject {
            Some(ComplexSubject::UserName(value)) => size += 1 + sizeofs::sizeof_len(value.len()),
            Some(ComplexSubject::OrganizationId(value)) => {
                size += 1 + sizeofs::sizeof_len(value.len())
            }
            Some(ComplexSubject::AuditSubject(value)) => {
                let len = value.get_size();
                size += 1 + sizeofs::sizeof_len(len);
            }
            None => {}
        }
        size
    }

    fn write_message<W: WriterBackend>(&self, w: &mut Writer<W>) -> Result<()> {
        if self.id != 0 {
            w.write_with_tag(8, |w| w.write_int32(self.id))?;
        }
        if let Some(audit) = &self.audit {
            w.write_with_tag(18, |w| w.write_message(audit))?;
        }
        for item in &self.history {
            w.write_with_tag(26, |w| w.write_message(item))?;
        }
        for (key, value) in &self.audits {
            let value_len = value.get_size();
            let entry_len = 1 + sizeofs::sizeof_len(key.len()) + 1 + sizeofs::sizeof_len(value_len);
            w.write_with_tag(34, |w| {
                w.write_map(
                    entry_len,
                    10,
                    |w| w.write_string(key),
                    18,
                    |w| w.write_message(value),
                )
            })?;
        }
        match &self.subject {
            Some(ComplexSubject::UserName(value)) => {
                w.write_with_tag(42, |w| w.write_string(value))?
            }
            Some(ComplexSubject::OrganizationId(value)) => {
                w.write_with_tag(50, |w| w.write_bytes(value))?
            }
            Some(ComplexSubject::AuditSubject(value)) => {
                w.write_with_tag(58, |w| w.write_message(value))?
            }
            None => {}
        }
        Ok(())
    }
}

impl<'a> MessageRead<'a> for Complex {
    fn from_reader(r: &mut BytesReader, bytes: &'a [u8]) -> Result<Self> {
        let mut msg = Complex::default();
        while !r.is_eof() {
            match r.next_tag(bytes)? {
                8 => msg.id = r.read_int32(bytes)?,
                18 => msg.audit = Some(r.read_message(bytes)?),
                26 => msg.history.push(r.read_message(bytes)?),
                34 => {
                    let (key, value) = r.read_map(
                        bytes,
                        |r, bytes| Ok(r.read_string(bytes)?.to_owned()),
                        |r, bytes| r.read_message(bytes),
                    )?;
                    msg.audits.insert(key, value);
                }
                42 => {
                    msg.subject = Some(ComplexSubject::UserName(r.read_string(bytes)?.to_owned()))
                }
                50 => {
                    msg.subject = Some(ComplexSubject::OrganizationId(
                        r.read_bytes(bytes)?.to_vec(),
                    ))
                }
                58 => msg.subject = Some(ComplexSubject::AuditSubject(r.read_message(bytes)?)),
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
        kind: 2,
        flags: vec![true, false, true, true, false, true, false, false],
        ids: vec![1, 127, 128, 16_384, 1_048_576, 9_876_543_210],
    }
}

fn make_textbytes() -> TextBytes {
    TextBytes {
        title: "ASCII title for protobuf".to_owned(),
        payload: b"0123456789abcdef0123456789abcdef".to_vec(),
        tags: vec![
            "alpha".to_owned(),
            "beta".to_owned(),
            "gamma".to_owned(),
            "delta".to_owned(),
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
        actor: actor.to_owned(),
        at_unix,
    }
}

fn make_complex() -> Complex {
    let mut audits = HashMap::new();
    audits.insert("latest".to_owned(), audit("reviewer", 67890));
    audits.insert("created".to_owned(), audit("creator", 12345));
    Complex {
        id: 42,
        audit: Some(audit("tester", 12345)),
        history: vec![audit("creator", 12345), audit("reviewer", 67890)],
        audits,
        subject: Some(ComplexSubject::AuditSubject(audit("subject", 777))),
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
    let scalarmix = make_scalarmix();
    let scalarmix_bytes = encode_to_vec(&scalarmix);
    let textbytes = make_textbytes();
    let textbytes_bytes = encode_to_vec(&textbytes);
    let complex = make_complex();
    let complex_bytes = encode_to_vec(&complex);
    let packed = make_packed();
    let packed_bytes = encode_to_vec(&packed);
    let fixed_packed = make_fixed_packed();
    let fixed_packed_bytes = encode_to_vec(&fixed_packed);
    let fixed64_packed = make_fixed64_packed();
    let fixed64_packed_bytes = encode_to_vec(&fixed64_packed);

    println!("rust quick-protobuf benchmark baseline");
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
        "quick-protobuf scalarmix encode",
        iters.binary,
        scalarmix_bytes.len(),
        || {
            let encoded = encode_to_vec(&scalarmix);
            std::hint::black_box(encoded);
        },
    )
    .print();
    let mut reused_scalarmix = Vec::with_capacity(scalarmix_bytes.len());
    run_timed(
        "quick-protobuf scalarmix encode reuse",
        iters.binary,
        scalarmix_bytes.len(),
        || {
            reused_scalarmix.clear();
            let mut writer = Writer::new(&mut reused_scalarmix);
            scalarmix.write_message(&mut writer).expect("encode");
            std::hint::black_box(&reused_scalarmix);
        },
    )
    .print();
    run_timed(
        "quick-protobuf scalarmix decode",
        iters.binary,
        scalarmix_bytes.len(),
        || {
            let mut reader = BytesReader::from_bytes(&scalarmix_bytes);
            let decoded = ScalarMix::from_reader(&mut reader, &scalarmix_bytes).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "quick-protobuf textbytes encode",
        iters.binary,
        textbytes_bytes.len(),
        || {
            let encoded = encode_to_vec(&textbytes);
            std::hint::black_box(encoded);
        },
    )
    .print();

    let mut reused_textbytes = Vec::with_capacity(textbytes_bytes.len());
    run_timed(
        "quick-protobuf textbytes encode reuse",
        iters.binary,
        textbytes_bytes.len(),
        || {
            reused_textbytes.clear();
            let mut writer = Writer::new(&mut reused_textbytes);
            textbytes.write_message(&mut writer).expect("encode");
            std::hint::black_box(&reused_textbytes);
        },
    )
    .print();

    run_timed(
        "quick-protobuf textbytes decode",
        iters.binary,
        textbytes_bytes.len(),
        || {
            let mut reader = BytesReader::from_bytes(&textbytes_bytes);
            let decoded = TextBytes::from_reader(&mut reader, &textbytes_bytes).expect("decode");
            std::hint::black_box(decoded);
        },
    )
    .print();

    run_timed(
        "quick-protobuf complex encode",
        iters.binary,
        complex_bytes.len(),
        || {
            let encoded = encode_to_vec(&complex);
            std::hint::black_box(encoded);
        },
    )
    .print();

    let mut reused_complex = Vec::with_capacity(complex_bytes.len());
    run_timed(
        "quick-protobuf complex encode reuse",
        iters.binary,
        complex_bytes.len(),
        || {
            reused_complex.clear();
            let mut writer = Writer::new(&mut reused_complex);
            complex.write_message(&mut writer).expect("encode");
            std::hint::black_box(&reused_complex);
        },
    )
    .print();

    run_timed(
        "quick-protobuf complex decode",
        iters.binary,
        complex_bytes.len(),
        || {
            let mut reader = BytesReader::from_bytes(&complex_bytes);
            let decoded = Complex::from_reader(&mut reader, &complex_bytes).expect("decode");
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
