// Benchmark for the upb C runtime (protobuf 35.1), the C implementation used
// inside Google's production protobuf runtimes. The workload shapes mirror
// bench/cpp_protobuf/main.cc so rows can be compared one-to-one.
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>

#include "person.upb.h"
#include "person.upbdefs.h"
#include "upb/json/decode.h"
#include "upb/json/encode.h"
#include "upb/mem/arena.h"
#include "upb/message/array.h"
#include "upb/message/map.h"
#include "upb/message/message.h"

using Clock = std::chrono::steady_clock;
constexpr int kBenchmarkSamples = 3;
int g_iterations = 20000;
constexpr int kLargeMapEntryCount = 1024;
constexpr int kLargeMapShuffleMultiplier = 257;
constexpr int kLargeMapShuffleIncrement = 911;
constexpr int kUnknownFieldStressCount = 1024;
constexpr int kUnknownFieldStressFirstNumber = 1000;
constexpr int kUnknownFieldStressNumberSpan = 16;
constexpr int kUnknownFieldStressCountPerNumber =
    kUnknownFieldStressCount / kUnknownFieldStressNumberSpan;

struct BenchResult {
  const char *name;
  int iterations;
  int samples;
  std::chrono::nanoseconds elapsed;
  std::size_t bytes_per_iter;

  void Print() const {
    const double elapsed_ns = static_cast<double>(elapsed.count());
    const double ns_per_iter = elapsed_ns / static_cast<double>(iterations);
    const double ops_per_sec =
        static_cast<double>(iterations) * 1000000000.0 / elapsed_ns;
    const double mib_per_sec =
        static_cast<double>(bytes_per_iter * iterations) * 1000000000.0 /
        elapsed_ns / (1024.0 * 1024.0);
    std::cout << name << ": best of " << samples << " x " << iterations
              << " iters, " << bytes_per_iter << " bytes/iter, " << ns_per_iter
              << " ns/op, " << ops_per_sec << " ops/s, " << mib_per_sec
              << " MiB/s\n";
  }
};

template <class F>
BenchResult RunTimed(const char *name, int iterations,
                     std::size_t bytes_per_iter, F &&f) {
  const int warmup_iterations = std::max(1, std::min(iterations / 10, 1000));
  for (int i = 0; i < warmup_iterations; ++i)
    f();

  auto best = std::chrono::nanoseconds::max();
  for (int sample = 0; sample < kBenchmarkSamples; ++sample) {
    const auto start = Clock::now();
    for (int i = 0; i < iterations; ++i)
      f();
    const auto end = Clock::now();
    best = std::min(best, std::chrono::duration_cast<std::chrono::nanoseconds>(
                              end - start));
  }
  return BenchResult{name, iterations, kBenchmarkSamples, best, bytes_per_iter};
}

class Arena {
 public:
  Arena() : arena_(upb_Arena_New()) {
    if (!arena_) std::abort();
  }
  ~Arena() { upb_Arena_Free(arena_); }
  Arena(const Arena &) = delete;
  Arena &operator=(const Arena &) = delete;
  upb_Arena *get() const { return arena_; }

 private:
  upb_Arena *arena_;
};

template <class Message>
std::string Serialize(const Message *msg, char *(*serialize)(const Message *,
                                                             upb_Arena *,
                                                             size_t *),
                      int options = 0) {
  Arena arena;
  size_t len = 0;
  char *ptr;
  if (options == 0) {
    ptr = serialize(msg, arena.get(), &len);
  } else {
    // The generated *_serialize_ex wrappers take an options argument; call the
    // underlying encoder directly to keep this helper generic.
    (void)options;
    ptr = serialize(msg, arena.get(), &len);
  }
  if (!ptr) std::abort();
  return std::string(ptr, len);
}

template <class Message>
std::string SerializeEx(const Message *msg, char *(*serialize_ex)(const Message *,
                                                                  int,
                                                                  upb_Arena *,
                                                                  size_t *),
                        int options) {
  Arena arena;
  size_t len = 0;
  char *ptr = serialize_ex(msg, options, arena.get(), &len);
  if (!ptr) std::abort();
  return std::string(ptr, len);
}

upb_StringView View(const char *data, std::size_t size) {
  return upb_StringView_FromDataAndSize(data, size);
}

upb_StringView View(const std::string &s) { return View(s.data(), s.size()); }

void AppendVarint(std::string *out, uint64_t value) {
  while (value >= 0x80) {
    out->push_back(static_cast<char>((value & 0x7f) | 0x80));
    value >>= 7;
  }
  out->push_back(static_cast<char>(value));
}

std::string MakeUnknownFieldPayload(const std::string &base) {
  std::string out = base;
  for (int i = 0; i < kUnknownFieldStressCount; ++i) {
    const int number =
        kUnknownFieldStressFirstNumber + (i % kUnknownFieldStressNumberSpan);
    AppendVarint(&out, (static_cast<uint64_t>(number) << 3) | 0);
    AppendVarint(&out, static_cast<uint64_t>(i + 1));
  }
  return out;
}

int ShuffledLargeMapIndex(int i) {
  return (i * kLargeMapShuffleMultiplier + kLargeMapShuffleIncrement) %
         kLargeMapEntryCount;
}

// Storage that keeps string/bytes payloads alive for fixture messages. upb
// string views are zero-copy, so the backing buffers must outlive the message.
struct FixtureStorage {
  std::vector<std::string> keys;
  std::vector<std::string> chunks;
  std::string payload;
  std::string title;
  std::string text_payload;
  std::vector<std::string> tags;
};

FixtureStorage g_storage;

upb_Arena *FixtureArena() {
  static upb_Arena *arena = [] {
    upb_Arena *a = upb_Arena_New();
    if (!a) std::abort();
    return a;
  }();
  return arena;
}

demo_Packed *MakePacked() {
  demo_Packed *msg = demo_Packed_new(FixtureArena());
  size_t size = 0;
  upb_Array *values =
      _demo_Packed_values_mutable_upb_array(msg, &size, FixtureArena());
  for (int i = 0; i < 1024; ++i) {
    upb_MessageValue v;
    v.int32_val = i % 4096;
    upb_Array_Append(values, v, FixtureArena());
  }
  return msg;
}

demo_FixedPacked *MakeFixedPacked() {
  demo_FixedPacked *msg = demo_FixedPacked_new(FixtureArena());
  size_t size = 0;
  upb_Array *values =
      _demo_FixedPacked_values_mutable_upb_array(msg, &size, FixtureArena());
  for (int i = 0; i < 1024; ++i) {
    upb_MessageValue v;
    v.uint32_val = static_cast<uint32_t>(i * 3 + 1);
    upb_Array_Append(values, v, FixtureArena());
  }
  return msg;
}

demo_Fixed64Packed *MakeFixed64Packed() {
  demo_Fixed64Packed *msg = demo_Fixed64Packed_new(FixtureArena());
  size_t size = 0;
  upb_Array *values =
      _demo_Fixed64Packed_values_mutable_upb_array(msg, &size, FixtureArena());
  for (int i = 0; i < 1024; ++i) {
    upb_MessageValue v;
    v.uint64_val = static_cast<uint64_t>(i) * 5 + 1;
    upb_Array_Append(values, v, FixtureArena());
  }
  return msg;
}

demo_SFixedPacked *MakeSFixedPacked() {
  demo_SFixedPacked *msg = demo_SFixedPacked_new(FixtureArena());
  size_t size = 0;
  upb_Array *values =
      _demo_SFixedPacked_values_mutable_upb_array(msg, &size, FixtureArena());
  for (int i = 0; i < 1024; ++i) {
    const int32_t magnitude = static_cast<int32_t>(i * 7 + 1);
    upb_MessageValue v;
    v.int32_val = (i & 1) == 0 ? magnitude : -magnitude;
    upb_Array_Append(values, v, FixtureArena());
  }
  return msg;
}

demo_SFixed64Packed *MakeSFixed64Packed() {
  demo_SFixed64Packed *msg = demo_SFixed64Packed_new(FixtureArena());
  size_t size = 0;
  upb_Array *values =
      _demo_SFixed64Packed_values_mutable_upb_array(msg, &size, FixtureArena());
  for (int i = 0; i < 1024; ++i) {
    const int64_t magnitude =
        (static_cast<int64_t>(i) << 20) + static_cast<int64_t>(i) * 11 + 1;
    upb_MessageValue v;
    v.int64_val = (i & 1) == 0 ? magnitude : -magnitude;
    upb_Array_Append(values, v, FixtureArena());
  }
  return msg;
}

demo_FloatPacked *MakeFloatPacked() {
  demo_FloatPacked *msg = demo_FloatPacked_new(FixtureArena());
  size_t size = 0;
  upb_Array *values =
      _demo_FloatPacked_values_mutable_upb_array(msg, &size, FixtureArena());
  for (int i = 0; i < 1024; ++i) {
    upb_MessageValue v;
    v.float_val = static_cast<float>(i) * 0.25f + 1.0f;
    upb_Array_Append(values, v, FixtureArena());
  }
  return msg;
}

demo_DoublePacked *MakeDoublePacked() {
  demo_DoublePacked *msg = demo_DoublePacked_new(FixtureArena());
  size_t size = 0;
  upb_Array *values =
      _demo_DoublePacked_values_mutable_upb_array(msg, &size, FixtureArena());
  for (int i = 0; i < 1024; ++i) {
    upb_MessageValue v;
    v.double_val = static_cast<double>(i) * 0.5 + 1.0;
    upb_Array_Append(values, v, FixtureArena());
  }
  return msg;
}

demo_UInt64Packed *MakeUInt64Packed() {
  demo_UInt64Packed *msg = demo_UInt64Packed_new(FixtureArena());
  size_t size = 0;
  upb_Array *values =
      _demo_UInt64Packed_values_mutable_upb_array(msg, &size, FixtureArena());
  for (int i = 0; i < 1024; ++i) {
    upb_MessageValue v;
    v.uint64_val =
        (static_cast<uint64_t>(i) << 21) + static_cast<uint64_t>(i) * 17 + 1;
    upb_Array_Append(values, v, FixtureArena());
  }
  return msg;
}

demo_UInt32Packed *MakeUInt32Packed() {
  demo_UInt32Packed *msg = demo_UInt32Packed_new(FixtureArena());
  size_t size = 0;
  upb_Array *values =
      _demo_UInt32Packed_values_mutable_upb_array(msg, &size, FixtureArena());
  for (int i = 0; i < 1024; ++i) {
    upb_MessageValue v;
    v.uint32_val = static_cast<uint32_t>((i << 12) + i * 3 + 1);
    upb_Array_Append(values, v, FixtureArena());
  }
  return msg;
}

demo_Int64Packed *MakeInt64Packed() {
  demo_Int64Packed *msg = demo_Int64Packed_new(FixtureArena());
  size_t size = 0;
  upb_Array *values =
      _demo_Int64Packed_values_mutable_upb_array(msg, &size, FixtureArena());
  for (int i = 0; i < 1024; ++i) {
    const int64_t magnitude =
        (static_cast<int64_t>(i) << 20) + static_cast<int64_t>(i) * 7 + 1;
    upb_MessageValue v;
    v.int64_val = (i & 1) == 0 ? magnitude : -magnitude;
    upb_Array_Append(values, v, FixtureArena());
  }
  return msg;
}

demo_SInt32Packed *MakeSInt32Packed() {
  demo_SInt32Packed *msg = demo_SInt32Packed_new(FixtureArena());
  size_t size = 0;
  upb_Array *values =
      _demo_SInt32Packed_values_mutable_upb_array(msg, &size, FixtureArena());
  for (int i = 0; i < 1024; ++i) {
    const int32_t magnitude = static_cast<int32_t>(i * 5 + 1);
    upb_MessageValue v;
    v.int32_val = (i & 1) == 0 ? magnitude : -magnitude;
    upb_Array_Append(values, v, FixtureArena());
  }
  return msg;
}

demo_SInt64Packed *MakeSInt64Packed() {
  demo_SInt64Packed *msg = demo_SInt64Packed_new(FixtureArena());
  size_t size = 0;
  upb_Array *values =
      _demo_SInt64Packed_values_mutable_upb_array(msg, &size, FixtureArena());
  for (int i = 0; i < 1024; ++i) {
    const int64_t magnitude =
        (static_cast<int64_t>(i) << 20) + static_cast<int64_t>(i) * 13 + 1;
    upb_MessageValue v;
    v.int64_val = (i & 1) == 0 ? magnitude : -magnitude;
    upb_Array_Append(values, v, FixtureArena());
  }
  return msg;
}

demo_BoolPacked *MakeBoolPacked() {
  demo_BoolPacked *msg = demo_BoolPacked_new(FixtureArena());
  size_t size = 0;
  upb_Array *values =
      _demo_BoolPacked_values_mutable_upb_array(msg, &size, FixtureArena());
  for (int i = 0; i < 1024; ++i) {
    upb_MessageValue v;
    v.bool_val = (i % 3) != 0;
    upb_Array_Append(values, v, FixtureArena());
  }
  return msg;
}

demo_EnumPacked *MakeEnumPacked() {
  demo_EnumPacked *msg = demo_EnumPacked_new(FixtureArena());
  size_t size = 0;
  upb_Array *values =
      _demo_EnumPacked_values_mutable_upb_array(msg, &size, FixtureArena());
  for (int i = 0; i < 1024; ++i) {
    upb_MessageValue v;
    v.int32_val = i % 3;
    upb_Array_Append(values, v, FixtureArena());
  }
  return msg;
}

demo_Person *MakePerson() {
  demo_Person *person = demo_Person_new(FixtureArena());
  demo_Person_set_id(person, 7);
  demo_Person_set_name(person, upb_StringView_FromString("Zig"));
  size_t size = 0;
  upb_Array *scores =
      _demo_Person_scores_mutable_upb_array(person, &size, FixtureArena());
  for (int score : {10, 20, 30, 40, 50, 60, 70, 80}) {
    upb_MessageValue v;
    v.int32_val = score;
    upb_Array_Append(scores, v, FixtureArena());
  }
  demo_Person_counts_set(person, upb_StringView_FromString("red"), 1,
                         FixtureArena());
  demo_Person_counts_set(person, upb_StringView_FromString("green"), 2,
                         FixtureArena());
  demo_Person_counts_set(person, upb_StringView_FromString("blue"), 3,
                         FixtureArena());
  return person;
}

demo_ScalarMix *MakeScalarMix() {
  demo_ScalarMix *msg = demo_ScalarMix_new(FixtureArena());
  demo_ScalarMix_set_active(msg, true);
  demo_ScalarMix_set_count(msg, 12345);
  demo_ScalarMix_set_total(msg, 9876543210ULL);
  demo_ScalarMix_set_delta(msg, -321);
  demo_ScalarMix_set_big_delta(msg, -9876543);
  demo_ScalarMix_set_checksum(msg, 0xdeadbeefU);
  demo_ScalarMix_set_token(msg, 0x0102030405060708ULL);
  demo_ScalarMix_set_signed_fixed(msg, -123456);
  demo_ScalarMix_set_signed_big_fixed(msg, -9876543210LL);
  demo_ScalarMix_set_ratio(msg, 1.25f);
  demo_ScalarMix_set_score(msg, 9.5);
  demo_ScalarMix_set_kind(msg, demo_BENCH_KIND_BETA);
  size_t size = 0;
  upb_Array *flags =
      _demo_ScalarMix_flags_mutable_upb_array(msg, &size, FixtureArena());
  for (bool flag : {true, false, true, true, false, true, false, false}) {
    upb_MessageValue v;
    v.bool_val = flag;
    upb_Array_Append(flags, v, FixtureArena());
  }
  upb_Array *ids =
      _demo_ScalarMix_ids_mutable_upb_array(msg, &size, FixtureArena());
  for (uint64_t id :
       {1ULL, 127ULL, 128ULL, 16384ULL, 1048576ULL, 9876543210ULL}) {
    upb_MessageValue v;
    v.uint64_val = id;
    upb_Array_Append(ids, v, FixtureArena());
  }
  return msg;
}

demo_TextBytes *MakeTextBytes() {
  demo_TextBytes *msg = demo_TextBytes_new(FixtureArena());
  demo_TextBytes_set_title(msg, upb_StringView_FromString(
                                     "ASCII title for protobuf"));
  demo_TextBytes_set_payload(
      msg, upb_StringView_FromString("0123456789abcdef0123456789abcdef"));
  size_t size = 0;
  upb_Array *tags =
      _demo_TextBytes_tags_mutable_upb_array(msg, &size, FixtureArena());
  for (const char *tag : {"alpha", "beta", "gamma", "delta"}) {
    upb_MessageValue v;
    v.str_val = upb_StringView_FromString(tag);
    upb_Array_Append(tags, v, FixtureArena());
  }
  upb_Array *chunks =
      _demo_TextBytes_chunks_mutable_upb_array(msg, &size, FixtureArena());
  for (const char *chunk :
       {"chunk-one", "chunk-two", "chunk-three", "chunk-four"}) {
    upb_MessageValue v;
    v.str_val = upb_StringView_FromString(chunk);
    upb_Array_Append(chunks, v, FixtureArena());
  }
  return msg;
}

demo_LargeBytes *MakeLargeBytes() {
  g_storage.payload.resize(64 * 1024);
  for (std::size_t i = 0; i < g_storage.payload.size(); ++i)
    g_storage.payload[i] = static_cast<char>((i * 31 + 7) & 0xff);
  g_storage.chunks.resize(16);
  for (int chunk_index = 0; chunk_index < 16; ++chunk_index) {
    std::string &chunk = g_storage.chunks[chunk_index];
    chunk.resize(4 * 1024);
    for (std::size_t i = 0; i < chunk.size(); ++i)
      chunk[i] = static_cast<char>((chunk_index * 17 + i * 13 + 3) & 0xff);
  }

  demo_LargeBytes *msg = demo_LargeBytes_new(FixtureArena());
  demo_LargeBytes_set_payload(msg, View(g_storage.payload));
  size_t size = 0;
  upb_Array *chunks =
      _demo_LargeBytes_chunks_mutable_upb_array(msg, &size, FixtureArena());
  for (const std::string &chunk : g_storage.chunks) {
    upb_MessageValue v;
    v.str_val = View(chunk);
    upb_Array_Append(chunks, v, FixtureArena());
  }
  return msg;
}

demo_PresenceMix_Child *MakePresenceChild(int32_t id, const char *label) {
  demo_PresenceMix_Child *child =
      demo_PresenceMix_Child_new(FixtureArena());
  demo_PresenceMix_Child_set_id(child, id);
  demo_PresenceMix_Child_set_label(child, upb_StringView_FromString(label));
  return child;
}

demo_PresenceMix *MakePresenceMix() {
  demo_PresenceMix *msg = demo_PresenceMix_new(FixtureArena());
  demo_PresenceMix_set_count(msg, 0);
  demo_PresenceMix_set_note(msg, upb_StringView_FromString(""));
  demo_PresenceMix_set_raw(msg, upb_StringView_FromString("presence-raw"));
  demo_PresenceMix_set_child(msg, MakePresenceChild(7, "child"));
  demo_PresenceMix_set_nested(msg, MakePresenceChild(11, "nested"));
  return msg;
}

demo_Complex_Audit *MakeAudit(const char *actor, int64_t at_unix) {
  demo_Complex_Audit *audit = demo_Complex_Audit_new(FixtureArena());
  demo_Complex_Audit_set_actor(audit, upb_StringView_FromString(actor));
  demo_Complex_Audit_set_at_unix(audit, at_unix);
  return audit;
}

demo_Complex *MakeComplex() {
  demo_Complex *complex = demo_Complex_new(FixtureArena());
  demo_Complex_set_id(complex, 42);
  demo_Complex_set_audit(complex, MakeAudit("tester", 12345));
  demo_Complex_add_history(complex, FixtureArena());
  {
    size_t size = 0;
    demo_Complex_Audit **history =
        demo_Complex_mutable_history(complex, &size);
    demo_Complex_Audit_set_actor(history[0], upb_StringView_FromString("creator"));
    demo_Complex_Audit_set_at_unix(history[0], 12345);
  }
  demo_Complex_add_history(complex, FixtureArena());
  {
    size_t size = 0;
    demo_Complex_Audit **history =
        demo_Complex_mutable_history(complex, &size);
    demo_Complex_Audit_set_actor(history[1],
                                 upb_StringView_FromString("reviewer"));
    demo_Complex_Audit_set_at_unix(history[1], 67890);
  }
  demo_Complex_audits_set(complex, upb_StringView_FromString("latest"),
                          MakeAudit("reviewer", 67890), FixtureArena());
  demo_Complex_audits_set(complex, upb_StringView_FromString("created"),
                          MakeAudit("creator", 12345), FixtureArena());
  demo_Complex_set_audit_subject(complex, MakeAudit("subject", 777));
  return complex;
}

demo_LargeMap *MakeLargeMap() {
  demo_LargeMap *msg = demo_LargeMap_new(FixtureArena());
  g_storage.keys.resize(kLargeMapEntryCount);
  for (int i = 0; i < kLargeMapEntryCount; ++i) {
    char key[16];
    std::snprintf(key, sizeof(key), "key-%04d", i);
    g_storage.keys[i] = key;
    demo_LargeMap_counts_set(msg, View(g_storage.keys[i]), (i % 4096) + 1,
                             FixtureArena());
  }
  return msg;
}

demo_LargeMap *MakeShuffledLargeMap() {
  demo_LargeMap *msg = demo_LargeMap_new(FixtureArena());
  g_storage.keys.resize(kLargeMapEntryCount);
  for (int i = 0; i < kLargeMapEntryCount; ++i) {
    const int key_index = ShuffledLargeMapIndex(i);
    char key[16];
    std::snprintf(key, sizeof(key), "key-%04d", key_index);
    g_storage.keys[i] = key;
    demo_LargeMap_counts_set(msg, View(g_storage.keys[i]),
                             (key_index % 4096) + 1, FixtureArena());
  }
  return msg;
}

template <class Message>
std::string EncodeRow(const Message *msg,
                      char *(*serialize)(const Message *, upb_Arena *, size_t *),
                      const char *name, int iterations) {
  std::string bytes = Serialize(msg, serialize);
  auto encode = RunTimed(name, iterations, bytes.size(), [&]() {
    std::string out = Serialize(msg, serialize);
    asm volatile("" : : "g"(out.data()) : "memory");
  });
  encode.Print();
  return bytes;
}

template <class Message>
std::string EncodeDeterministicRow(
    const Message *msg,
    char *(*serialize_ex)(const Message *, int, upb_Arena *, size_t *),
    const char *name, int iterations) {
  std::string bytes = SerializeEx(msg, serialize_ex,
                                  kUpb_EncodeOption_Deterministic);
  auto encode = RunTimed(name, iterations, bytes.size(), [&]() {
    std::string out =
        SerializeEx(msg, serialize_ex, kUpb_EncodeOption_Deterministic);
    asm volatile("" : : "g"(out.data()) : "memory");
  });
  encode.Print();
  return bytes;
}

template <class Message>
void DecodeRow(Message *(*parse)(const char *, size_t, upb_Arena *),
               const std::string &bytes, const char *name, int iterations) {
  auto decode = RunTimed(name, iterations, bytes.size(), [&]() {
    Arena arena;
    Message *decoded = parse(bytes.data(), bytes.size(), arena.get());
    if (!decoded) std::abort();
    asm volatile("" : : "g"(decoded) : "memory");
  });
  decode.Print();
}

template <class Message>
void BinaryPair(Message *msg,
                char *(*serialize)(const Message *, upb_Arena *, size_t *),
                Message *(*parse)(const char *, size_t, upb_Arena *),
                const char *encode_name, const char *decode_name,
                int iterations) {
  std::string bytes = EncodeRow(msg, serialize, encode_name, iterations);
  DecodeRow(parse, bytes, decode_name, iterations);
}

template <class Message>
void PackedPair(Message *msg,
                char *(*serialize)(const Message *, upb_Arena *, size_t *),
                Message *(*parse)(const char *, size_t, upb_Arena *),
                const char *label) {
  std::string encode_name = std::string("upb protobuf packed ") + label +
                            " encode";
  std::string decode_name = std::string("upb protobuf packed ") + label +
                            " decode";
  BinaryPair(msg, serialize, parse, encode_name.c_str(), decode_name.c_str(),
             g_iterations);
}

// Counts unknown varint fields whose number matches the stress target. upb
// exposes unknown fields as raw wire chunks, so this mirrors the public
// upb_Message_NextUnknown traversal a C user would write.
int CountUnknownFieldsByNumber(const upb_Message *msg) {
  upb_StringView data;
  uintptr_t iter = kUpb_Message_UnknownBegin;
  int count = 0;
  while (upb_Message_NextUnknown(msg, &data, &iter)) {
    const char *p = data.data;
    const char *end = p + data.size;
    while (p < end) {
      uint64_t tag = 0;
      int shift = 0;
      while (p < end && shift < 64) {
        const uint8_t byte = static_cast<uint8_t>(*p++);
        tag |= static_cast<uint64_t>(byte & 0x7f) << shift;
        if ((byte & 0x80) == 0) break;
        shift += 7;
      }
      const uint64_t number = tag >> 3;
      if (number == kUnknownFieldStressFirstNumber) {
        ++count;
      }
      const int wire_type = static_cast<int>(tag & 7);
      if (wire_type == 0) {
        while (p < end && (static_cast<uint8_t>(*p) & 0x80)) ++p;
        if (p < end) ++p;
      } else if (wire_type == 1) {
        p += 8;
      } else if (wire_type == 2) {
        uint64_t len = 0;
        shift = 0;
        while (p < end && shift < 64) {
          const uint8_t byte = static_cast<uint8_t>(*p++);
          len |= static_cast<uint64_t>(byte & 0x7f) << shift;
          if ((byte & 0x80) == 0) break;
          shift += 7;
        }
        p += len;
      } else if (wire_type == 5) {
        p += 4;
      } else {
        break;
      }
    }
  }
  return count;
}

std::string JsonStringify(const upb_Message *msg, const upb_MessageDef *def,
                          const upb_DefPool *pool, int options,
                          const char *name, int iterations) {
  upb_Status status;
  upb_Status_Clear(&status);
  char dummy = '\0';
  const size_t needed =
      upb_JsonEncode(msg, def, pool, options, &dummy, 0, &status);
  if (!upb_Status_IsOk(&status)) std::abort();
  std::string out(needed + 1, '\0');
  auto stringify = RunTimed(name, iterations, needed, [&]() {
    std::string buffer(needed + 1, '\0');
    upb_Status local;
    upb_Status_Clear(&local);
    const size_t len = upb_JsonEncode(msg, def, pool, options, buffer.data(),
                                      buffer.size(), &local);
    if (!upb_Status_IsOk(&local) || len != needed) std::abort();
    asm volatile("" : : "g"(buffer.data()) : "memory");
  });
  stringify.Print();
  out.resize(needed);
  upb_Status_Clear(&status);
  if (upb_JsonEncode(msg, def, pool, options, out.data(), out.size() + 1,
                     &status) != needed ||
      !upb_Status_IsOk(&status)) {
    std::abort();
  }
  return out;
}

template <class Message>
void JsonParse(const std::string &json, Message *(*create)(upb_Arena *),
               const upb_MessageDef *def, const upb_DefPool *pool,
               const char *name, int iterations) {
  auto parse = RunTimed(name, iterations, json.size(), [&]() {
    Arena arena;
    Message *msg = create(arena.get());
    upb_Status status;
    upb_Status_Clear(&status);
    if (!msg || !upb_JsonDecode(json.data(), json.size(), UPB_UPCAST(msg), def,
                                pool, 0, arena.get(), &status))
      std::abort();
    asm volatile("" : : "g"(msg) : "memory");
  });
  parse.Print();
}

int main() {
  if (const char *env = std::getenv("PBZ_BENCH_ITERATIONS")) {
    const int parsed = std::atoi(env);
    if (parsed > 0) g_iterations = parsed;
  }
  upb_DefPool *pool = upb_DefPool_New();
  if (!pool) std::abort();
  const upb_MessageDef *person_def = demo_Person_getmsgdef(pool);
  const upb_MessageDef *scalarmix_def = demo_ScalarMix_getmsgdef(pool);
  const upb_MessageDef *textbytes_def = demo_TextBytes_getmsgdef(pool);
  const upb_MessageDef *presencemix_def = demo_PresenceMix_getmsgdef(pool);
  const upb_MessageDef *complex_def = demo_Complex_getmsgdef(pool);
  const upb_MessageDef *large_map_def = demo_LargeMap_getmsgdef(pool);

  demo_Person *person = MakePerson();
  demo_ScalarMix *scalarmix = MakeScalarMix();
  demo_TextBytes *textbytes = MakeTextBytes();
  demo_LargeBytes *largebytes = MakeLargeBytes();
  demo_PresenceMix *presencemix = MakePresenceMix();
  demo_Complex *complex = MakeComplex();
  demo_LargeMap *large_map = MakeLargeMap();
  demo_LargeMap *shuffled_large_map = MakeShuffledLargeMap();

  demo_Packed *packed = MakePacked();
  demo_FixedPacked *fixed_packed = MakeFixedPacked();
  demo_Fixed64Packed *fixed64_packed = MakeFixed64Packed();
  demo_SFixedPacked *sfixed_packed = MakeSFixedPacked();
  demo_SFixed64Packed *sfixed64_packed = MakeSFixed64Packed();
  demo_FloatPacked *float_packed = MakeFloatPacked();
  demo_DoublePacked *double_packed = MakeDoublePacked();
  demo_UInt64Packed *uint64_packed = MakeUInt64Packed();
  demo_UInt32Packed *uint32_packed = MakeUInt32Packed();
  demo_Int64Packed *int64_packed = MakeInt64Packed();
  demo_SInt32Packed *sint32_packed = MakeSInt32Packed();
  demo_SInt64Packed *sint64_packed = MakeSInt64Packed();
  demo_BoolPacked *bool_packed = MakeBoolPacked();
  demo_EnumPacked *enum_packed = MakeEnumPacked();

  BinaryPair(person, demo_Person_serialize, demo_Person_parse,
             "upb protobuf binary encode", "upb protobuf binary decode",
             g_iterations);
  BinaryPair(scalarmix, demo_ScalarMix_serialize, demo_ScalarMix_parse,
             "upb protobuf scalarmix encode", "upb protobuf scalarmix decode",
             g_iterations);
  BinaryPair(textbytes, demo_TextBytes_serialize, demo_TextBytes_parse,
             "upb protobuf textbytes encode", "upb protobuf textbytes decode",
             g_iterations);
  BinaryPair(largebytes, demo_LargeBytes_serialize, demo_LargeBytes_parse,
             "upb protobuf largebytes encode", "upb protobuf largebytes decode",
             g_iterations);
  BinaryPair(presencemix, demo_PresenceMix_serialize, demo_PresenceMix_parse,
             "upb protobuf presencemix encode",
             "upb protobuf presencemix decode", g_iterations);
  BinaryPair(complex, demo_Complex_serialize, demo_Complex_parse,
             "upb protobuf complex encode", "upb protobuf complex decode",
             g_iterations);

  PackedPair(packed, demo_Packed_serialize, demo_Packed_parse, "int32");
  PackedPair(fixed_packed, demo_FixedPacked_serialize, demo_FixedPacked_parse,
             "fixed32");
  PackedPair(fixed64_packed, demo_Fixed64Packed_serialize,
             demo_Fixed64Packed_parse, "fixed64");
  PackedPair(sfixed_packed, demo_SFixedPacked_serialize,
             demo_SFixedPacked_parse, "sfixed32");
  PackedPair(sfixed64_packed, demo_SFixed64Packed_serialize,
             demo_SFixed64Packed_parse, "sfixed64");
  PackedPair(float_packed, demo_FloatPacked_serialize,
             demo_FloatPacked_parse, "float");
  PackedPair(double_packed, demo_DoublePacked_serialize,
             demo_DoublePacked_parse, "double");
  PackedPair(uint64_packed, demo_UInt64Packed_serialize,
             demo_UInt64Packed_parse, "uint64");
  PackedPair(uint32_packed, demo_UInt32Packed_serialize,
             demo_UInt32Packed_parse, "uint32");
  PackedPair(int64_packed, demo_Int64Packed_serialize,
             demo_Int64Packed_parse, "int64");
  PackedPair(sint32_packed, demo_SInt32Packed_serialize,
             demo_SInt32Packed_parse, "sint32");
  PackedPair(sint64_packed, demo_SInt64Packed_serialize,
             demo_SInt64Packed_parse, "sint64");
  PackedPair(bool_packed, demo_BoolPacked_serialize, demo_BoolPacked_parse,
             "bool");
  PackedPair(enum_packed, demo_EnumPacked_serialize, demo_EnumPacked_parse,
             "enum");

  BinaryPair(large_map, demo_LargeMap_serialize, demo_LargeMap_parse,
             "upb protobuf large map encode",
             "upb protobuf large map decode", g_iterations);

  EncodeDeterministicRow(
      person, demo_Person_serialize_ex,
      "upb protobuf deterministic binary encode", g_iterations);
  EncodeDeterministicRow(
      complex, demo_Complex_serialize_ex,
      "upb protobuf complex deterministic binary encode", g_iterations);
  EncodeDeterministicRow(
      shuffled_large_map, demo_LargeMap_serialize_ex,
      "upb protobuf shuffled large map deterministic binary encode",
      g_iterations);

  {
    const std::string person_bytes = Serialize(person, demo_Person_serialize);
    const std::string unknown_bytes = MakeUnknownFieldPayload(person_bytes);
    Arena unknown_arena;
    demo_Person *unknown_person = demo_Person_parse(
        unknown_bytes.data(), unknown_bytes.size(), unknown_arena.get());
    if (!unknown_person || !upb_Message_HasUnknown(UPB_UPCAST(unknown_person)))
      std::abort();
    const int count = CountUnknownFieldsByNumber(
        UPB_UPCAST(unknown_person));
    if (count != kUnknownFieldStressCountPerNumber) std::abort();
    auto unknown_count = RunTimed(
        "upb protobuf unknown fields count by number", g_iterations,
        unknown_bytes.size(), [&]() {
          const int local = CountUnknownFieldsByNumber(
              UPB_UPCAST(unknown_person));
          asm volatile("" : : "g"(local) : "memory");
        });
    unknown_count.Print();
  }

  {
    std::string json = JsonStringify(
        UPB_UPCAST(person), person_def, pool, 0, "upb protobuf JSON stringify",
        g_iterations);
    JsonParse(json, demo_Person_new, person_def, pool,
              "upb protobuf JSON parse", g_iterations);

    std::string scalarmix_json = JsonStringify(
        UPB_UPCAST(scalarmix), scalarmix_def, pool, 0,
        "upb protobuf ScalarMix JSON stringify",
        g_iterations);
    JsonParse(scalarmix_json, demo_ScalarMix_new, scalarmix_def, pool,
              "upb protobuf ScalarMix JSON parse", g_iterations);

    std::string textbytes_json = JsonStringify(
        UPB_UPCAST(textbytes), textbytes_def, pool, 0,
        "upb protobuf TextBytes JSON stringify",
        g_iterations);
    JsonParse(textbytes_json, demo_TextBytes_new, textbytes_def, pool,
              "upb protobuf TextBytes JSON parse", g_iterations);

    std::string presencemix_json = JsonStringify(
        UPB_UPCAST(presencemix), presencemix_def, pool, 0,
        "upb protobuf PresenceMix JSON stringify",
        g_iterations);
    JsonParse(presencemix_json, demo_PresenceMix_new, presencemix_def, pool,
              "upb protobuf PresenceMix JSON parse", g_iterations);

    std::string complex_json = JsonStringify(
        UPB_UPCAST(complex), complex_def, pool, 0,
        "upb protobuf complex JSON stringify",
        g_iterations);
    JsonParse(complex_json, demo_Complex_new, complex_def, pool,
              "upb protobuf complex JSON parse", g_iterations);

    std::string complex_proto_name_json = JsonStringify(
        UPB_UPCAST(complex), complex_def, pool, upb_JsonEncode_UseProtoNames,
        "upb protobuf Complex ProtoName JSON stringify",
        g_iterations);
    JsonParse(complex_proto_name_json, demo_Complex_new, complex_def, pool,
              "upb protobuf Complex ProtoName JSON parse", g_iterations);

    std::string large_map_json = JsonStringify(
        UPB_UPCAST(large_map), large_map_def, pool, 0,
        "upb protobuf LargeMap JSON stringify",
        g_iterations);
    JsonParse(large_map_json, demo_LargeMap_new, large_map_def, pool,
              "upb protobuf LargeMap JSON parse", g_iterations);

    demo_Person *empty_person = demo_Person_new(FixtureArena());
    JsonStringify(UPB_UPCAST(empty_person), person_def, pool,
                  upb_JsonEncode_EmitDefaults,
                  "upb protobuf AlwaysPrint JSON stringify", g_iterations);
    JsonStringify(UPB_UPCAST(scalarmix), scalarmix_def, pool,
                  upb_JsonEncode_UseProtoNames,
                  "upb protobuf ProtoName JSON stringify", g_iterations);
    JsonStringify(UPB_UPCAST(scalarmix), scalarmix_def, pool,
                  upb_JsonEncode_FormatEnumsAsIntegers,
                  "upb protobuf EnumNumber JSON stringify",
        g_iterations);
  }

  upb_DefPool_Free(pool);
  return 0;
}
