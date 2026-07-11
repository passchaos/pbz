#include <chrono>
#include <cstdint>
#include <algorithm>
#include <iostream>
#include <string>

#include <google/protobuf/text_format.h>
#include <google/protobuf/io/coded_stream.h>
#include <google/protobuf/io/zero_copy_stream_impl_lite.h>
#include <google/protobuf/util/json_util.h>

#include "person.pb.h"

using Clock = std::chrono::steady_clock;
constexpr int kBenchmarkSamples = 3;

struct BenchResult {
  const char* name;
  int iterations;
  int samples;
  std::chrono::nanoseconds elapsed;
  std::size_t bytes_per_iter;

  void Print() const {
    const double elapsed_ns = static_cast<double>(elapsed.count());
    const double ns_per_iter = elapsed_ns / static_cast<double>(iterations);
    const double ops_per_sec = static_cast<double>(iterations) * 1000000000.0 / elapsed_ns;
    const double mib_per_sec = static_cast<double>(bytes_per_iter * iterations) * 1000000000.0 / elapsed_ns / (1024.0 * 1024.0);
    std::cout << name << ": best of " << samples << " x " << iterations << " iters, " << bytes_per_iter
              << " bytes/iter, " << ns_per_iter << " ns/op, " << ops_per_sec
              << " ops/s, " << mib_per_sec << " MiB/s\n";
  }
};

template <class F>
BenchResult RunTimed(const char* name, int iterations, std::size_t bytes_per_iter, F&& f) {
  const int warmup_iterations = std::max(1, std::min(iterations / 10, 1000));
  for (int i = 0; i < warmup_iterations; ++i) f();

  auto best = std::chrono::nanoseconds::max();
  for (int sample = 0; sample < kBenchmarkSamples; ++sample) {
    const auto start = Clock::now();
    for (int i = 0; i < iterations; ++i) f();
    const auto end = Clock::now();
    best = std::min(best, std::chrono::duration_cast<std::chrono::nanoseconds>(end - start));
  }
  return BenchResult{name, iterations, kBenchmarkSamples, best, bytes_per_iter};
}

demo::Packed MakePacked() {
  demo::Packed packed;
  for (int i = 0; i < 1024; ++i) packed.add_values(i % 4096);
  return packed;
}

demo::FixedPacked MakeFixedPacked() {
  demo::FixedPacked packed;
  for (int i = 0; i < 1024; ++i) packed.add_values(i * 3 + 1);
  return packed;
}

demo::Fixed64Packed MakeFixed64Packed() {
  demo::Fixed64Packed packed;
  for (int i = 0; i < 1024; ++i) packed.add_values(static_cast<uint64_t>(i) * 5 + 1);
  return packed;
}

demo::Person MakePerson() {
  demo::Person person;
  person.set_id(7);
  person.set_name("Zig");
  for (int score : {10, 20, 30, 40, 50, 60, 70, 80}) person.add_scores(score);
  (*person.mutable_counts())["red"] = 1;
  (*person.mutable_counts())["green"] = 2;
  (*person.mutable_counts())["blue"] = 3;
  return person;
}


demo::Complex::Audit MakeAudit(const std::string& actor, int64_t at_unix) {
  demo::Complex::Audit audit;
  audit.set_actor(actor);
  audit.set_at_unix(at_unix);
  return audit;
}

demo::Complex MakeComplex() {
  demo::Complex complex;
  complex.set_id(42);
  *complex.mutable_audit() = MakeAudit("tester", 12345);
  *complex.add_history() = MakeAudit("creator", 12345);
  *complex.add_history() = MakeAudit("reviewer", 67890);
  (*complex.mutable_audits())["latest"] = MakeAudit("reviewer", 67890);
  (*complex.mutable_audits())["created"] = MakeAudit("creator", 12345);
  *complex.mutable_audit_subject() = MakeAudit("subject", 777);
  return complex;
}

int main() {
  constexpr int kIterations = 20000;
  const demo::Person person = MakePerson();
  const demo::Complex complex = MakeComplex();
  std::string bytes;
  person.SerializeToString(&bytes);
  std::string json;
  if (!google::protobuf::util::MessageToJsonString(person, &json).ok()) std::abort();
  std::string text;
  if (!google::protobuf::TextFormat::PrintToString(person, &text)) std::abort();
  std::string complex_bytes;
  complex.SerializeToString(&complex_bytes);
  const demo::Packed packed = MakePacked();
  std::string packed_bytes;
  packed.SerializeToString(&packed_bytes);
  const demo::FixedPacked fixed_packed = MakeFixedPacked();
  std::string fixed_packed_bytes;
  fixed_packed.SerializeToString(&fixed_packed_bytes);
  const demo::Fixed64Packed fixed64_packed = MakeFixed64Packed();
  std::string fixed64_packed_bytes;
  fixed64_packed.SerializeToString(&fixed64_packed_bytes);

  std::cout << "c++ protobuf benchmark baseline\n";
  std::cout << "payload size: " << bytes.size() << "\n";
  std::cout << "json payload size: " << json.size() << "\n";
  std::cout << "text payload size: " << text.size() << "\n";
  std::cout << "complex payload size: " << complex_bytes.size() << "\n";
  std::cout << "packed payload size: " << packed_bytes.size() << "\n";
  std::cout << "fixed32 packed payload size: " << fixed_packed_bytes.size() << "\n";
  std::cout << "fixed64 packed payload size: " << fixed64_packed_bytes.size() << "\n";

  auto encode = RunTimed("c++ protobuf binary encode", kIterations, bytes.size(), [&]() {
    std::string out;
    out.reserve(bytes.size());
    person.SerializeToString(&out);
    asm volatile("" : : "g"(out.data()) : "memory");
  });
  encode.Print();

  std::string reused;
  reused.reserve(bytes.size());
  auto encode_reuse = RunTimed("c++ protobuf binary encode reuse", kIterations, bytes.size(), [&]() {
    reused.clear();
    person.SerializeToString(&reused);
    asm volatile("" : : "g"(reused.data()) : "memory");
  });
  encode_reuse.Print();

  std::string array_buffer;
  array_buffer.resize(bytes.size());
  auto encode_array_reuse = RunTimed("c++ protobuf binary SerializeToArray reuse", kIterations, bytes.size(), [&]() {
    if (!person.SerializeToArray(array_buffer.data(), static_cast<int>(array_buffer.size()))) std::abort();
    asm volatile("" : : "g"(array_buffer.data()) : "memory");
  });
  encode_array_reuse.Print();

  std::string deterministic_buffer;
  deterministic_buffer.resize(bytes.size());
  auto deterministic_encode = RunTimed("c++ protobuf deterministic binary encode reuse", kIterations, bytes.size(), [&]() {
    google::protobuf::io::ArrayOutputStream array_stream(deterministic_buffer.data(), static_cast<int>(deterministic_buffer.size()));
    google::protobuf::io::CodedOutputStream coded_stream(&array_stream);
    coded_stream.SetSerializationDeterministic(true);
    person.SerializeWithCachedSizes(&coded_stream);
    coded_stream.Trim();
    if (coded_stream.HadError()) std::abort();
    asm volatile("" : : "g"(deterministic_buffer.data()) : "memory");
  });
  deterministic_encode.Print();

  auto decode = RunTimed("c++ protobuf binary decode", kIterations, bytes.size(), [&]() {
    demo::Person decoded;
    if (!decoded.ParseFromString(bytes)) std::abort();
    asm volatile("" : : "g"(&decoded) : "memory");
  });
  decode.Print();

  demo::Person reused_decoded;
  auto decode_reuse = RunTimed("c++ protobuf binary decode reuse", kIterations, bytes.size(), [&]() {
    reused_decoded.Clear();
    if (!reused_decoded.ParseFromString(bytes)) std::abort();
    asm volatile("" : : "g"(&reused_decoded) : "memory");
  });
  decode_reuse.Print();



  auto complex_encode = RunTimed("c++ protobuf complex encode", kIterations, complex_bytes.size(), [&]() {
    std::string out;
    out.reserve(complex_bytes.size());
    complex.SerializeToString(&out);
    asm volatile("" : : "g"(out.data()) : "memory");
  });
  complex_encode.Print();

  std::string reused_complex;
  reused_complex.reserve(complex_bytes.size());
  auto complex_encode_reuse = RunTimed("c++ protobuf complex encode reuse", kIterations, complex_bytes.size(), [&]() {
    reused_complex.clear();
    complex.SerializeToString(&reused_complex);
    asm volatile("" : : "g"(reused_complex.data()) : "memory");
  });
  complex_encode_reuse.Print();

  std::string complex_array_buffer;
  complex_array_buffer.resize(complex_bytes.size());
  auto complex_encode_array_reuse = RunTimed("c++ protobuf complex SerializeToArray reuse", kIterations, complex_bytes.size(), [&]() {
    if (!complex.SerializeToArray(complex_array_buffer.data(), static_cast<int>(complex_array_buffer.size()))) std::abort();
    asm volatile("" : : "g"(complex_array_buffer.data()) : "memory");
  });
  complex_encode_array_reuse.Print();

  auto complex_decode = RunTimed("c++ protobuf complex decode", kIterations, complex_bytes.size(), [&]() {
    demo::Complex decoded;
    if (!decoded.ParseFromString(complex_bytes)) std::abort();
    asm volatile("" : : "g"(&decoded) : "memory");
  });
  complex_decode.Print();

  demo::Complex reused_complex_decoded;
  auto complex_decode_reuse = RunTimed("c++ protobuf complex decode reuse", kIterations, complex_bytes.size(), [&]() {
    reused_complex_decoded.Clear();
    if (!reused_complex_decoded.ParseFromString(complex_bytes)) std::abort();
    asm volatile("" : : "g"(&reused_complex_decoded) : "memory");
  });
  complex_decode_reuse.Print();

  auto json_stringify = RunTimed("c++ protobuf JSON stringify", kIterations, json.size(), [&]() {
    std::string out;
    if (!google::protobuf::util::MessageToJsonString(person, &out).ok()) std::abort();
    asm volatile("" : : "g"(out.data()) : "memory");
  });
  json_stringify.Print();

  std::string reused_json;
  reused_json.reserve(json.size());
  auto json_stringify_reuse = RunTimed("c++ protobuf JSON stringify reuse", kIterations, json.size(), [&]() {
    reused_json.clear();
    if (!google::protobuf::util::MessageToJsonString(person, &reused_json).ok()) std::abort();
    asm volatile("" : : "g"(reused_json.data()) : "memory");
  });
  json_stringify_reuse.Print();

  auto json_parse = RunTimed("c++ protobuf JSON parse", kIterations, json.size(), [&]() {
    demo::Person decoded;
    if (!google::protobuf::util::JsonStringToMessage(json, &decoded).ok()) std::abort();
    asm volatile("" : : "g"(&decoded) : "memory");
  });
  json_parse.Print();

  demo::Person reused_json_decoded;
  auto json_parse_reuse = RunTimed("c++ protobuf JSON parse reuse", kIterations, json.size(), [&]() {
    reused_json_decoded.Clear();
    if (!google::protobuf::util::JsonStringToMessage(json, &reused_json_decoded).ok()) std::abort();
    asm volatile("" : : "g"(&reused_json_decoded) : "memory");
  });
  json_parse_reuse.Print();

  auto text_format = RunTimed("c++ protobuf TextFormat format", kIterations, text.size(), [&]() {
    std::string out;
    if (!google::protobuf::TextFormat::PrintToString(person, &out)) std::abort();
    asm volatile("" : : "g"(out.data()) : "memory");
  });
  text_format.Print();

  std::string reused_text;
  reused_text.reserve(text.size());
  auto text_format_reuse = RunTimed("c++ protobuf TextFormat format reuse", kIterations, text.size(), [&]() {
    reused_text.clear();
    if (!google::protobuf::TextFormat::PrintToString(person, &reused_text)) std::abort();
    asm volatile("" : : "g"(reused_text.data()) : "memory");
  });
  text_format_reuse.Print();

  auto text_parse = RunTimed("c++ protobuf TextFormat parse", kIterations, text.size(), [&]() {
    demo::Person decoded;
    if (!google::protobuf::TextFormat::ParseFromString(text, &decoded)) std::abort();
    asm volatile("" : : "g"(&decoded) : "memory");
  });
  text_parse.Print();

  demo::Person reused_text_decoded;
  auto text_parse_reuse = RunTimed("c++ protobuf TextFormat parse reuse", kIterations, text.size(), [&]() {
    reused_text_decoded.Clear();
    if (!google::protobuf::TextFormat::ParseFromString(text, &reused_text_decoded)) std::abort();
    asm volatile("" : : "g"(&reused_text_decoded) : "memory");
  });
  text_parse_reuse.Print();

  auto packed_encode = RunTimed("c++ protobuf packed encode", kIterations, packed_bytes.size(), [&]() {
    std::string out;
    out.reserve(packed_bytes.size());
    packed.SerializeToString(&out);
    asm volatile("" : : "g"(out.data()) : "memory");
  });
  packed_encode.Print();

  std::string reused_packed;
  reused_packed.reserve(packed_bytes.size());
  auto packed_encode_reuse = RunTimed("c++ protobuf packed encode reuse", kIterations, packed_bytes.size(), [&]() {
    reused_packed.clear();
    packed.SerializeToString(&reused_packed);
    asm volatile("" : : "g"(reused_packed.data()) : "memory");
  });
  packed_encode_reuse.Print();

  std::string packed_array_buffer;
  packed_array_buffer.resize(packed_bytes.size());
  auto packed_encode_array_reuse = RunTimed("c++ protobuf packed SerializeToArray reuse", kIterations, packed_bytes.size(), [&]() {
    if (!packed.SerializeToArray(packed_array_buffer.data(), static_cast<int>(packed_array_buffer.size()))) std::abort();
    asm volatile("" : : "g"(packed_array_buffer.data()) : "memory");
  });
  packed_encode_array_reuse.Print();

  auto packed_decode = RunTimed("c++ protobuf packed decode", kIterations, packed_bytes.size(), [&]() {
    demo::Packed decoded;
    if (!decoded.ParseFromString(packed_bytes)) std::abort();
    asm volatile("" : : "g"(&decoded) : "memory");
  });
  packed_decode.Print();

  demo::Packed reused_packed_decoded;
  auto packed_decode_reuse = RunTimed("c++ protobuf packed decode reuse", kIterations, packed_bytes.size(), [&]() {
    reused_packed_decoded.Clear();
    if (!reused_packed_decoded.ParseFromString(packed_bytes)) std::abort();
    asm volatile("" : : "g"(&reused_packed_decoded) : "memory");
  });
  packed_decode_reuse.Print();

  auto fixed_packed_encode = RunTimed("c++ protobuf fixed32 packed encode", kIterations, fixed_packed_bytes.size(), [&]() {
    std::string out;
    out.reserve(fixed_packed_bytes.size());
    fixed_packed.SerializeToString(&out);
    asm volatile("" : : "g"(out.data()) : "memory");
  });
  fixed_packed_encode.Print();

  std::string fixed_packed_array_buffer;
  fixed_packed_array_buffer.resize(fixed_packed_bytes.size());
  auto fixed_packed_encode_array_reuse = RunTimed("c++ protobuf fixed32 packed SerializeToArray reuse", kIterations, fixed_packed_bytes.size(), [&]() {
    if (!fixed_packed.SerializeToArray(fixed_packed_array_buffer.data(), static_cast<int>(fixed_packed_array_buffer.size()))) std::abort();
    asm volatile("" : : "g"(fixed_packed_array_buffer.data()) : "memory");
  });
  fixed_packed_encode_array_reuse.Print();

  auto fixed_packed_decode = RunTimed("c++ protobuf fixed32 packed decode", kIterations, fixed_packed_bytes.size(), [&]() {
    demo::FixedPacked decoded;
    if (!decoded.ParseFromString(fixed_packed_bytes)) std::abort();
    asm volatile("" : : "g"(&decoded) : "memory");
  });
  fixed_packed_decode.Print();

  demo::FixedPacked reused_fixed_packed_decoded;
  auto fixed_packed_decode_reuse = RunTimed("c++ protobuf fixed32 packed decode reuse", kIterations, fixed_packed_bytes.size(), [&]() {
    reused_fixed_packed_decoded.Clear();
    if (!reused_fixed_packed_decoded.ParseFromString(fixed_packed_bytes)) std::abort();
    asm volatile("" : : "g"(&reused_fixed_packed_decoded) : "memory");
  });
  fixed_packed_decode_reuse.Print();

  auto fixed64_packed_encode = RunTimed("c++ protobuf fixed64 packed encode", kIterations, fixed64_packed_bytes.size(), [&]() {
    std::string out;
    out.reserve(fixed64_packed_bytes.size());
    fixed64_packed.SerializeToString(&out);
    asm volatile("" : : "g"(out.data()) : "memory");
  });
  fixed64_packed_encode.Print();

  std::string fixed64_packed_array_buffer;
  fixed64_packed_array_buffer.resize(fixed64_packed_bytes.size());
  auto fixed64_packed_encode_array_reuse = RunTimed("c++ protobuf fixed64 packed SerializeToArray reuse", kIterations, fixed64_packed_bytes.size(), [&]() {
    if (!fixed64_packed.SerializeToArray(fixed64_packed_array_buffer.data(), static_cast<int>(fixed64_packed_array_buffer.size()))) std::abort();
    asm volatile("" : : "g"(fixed64_packed_array_buffer.data()) : "memory");
  });
  fixed64_packed_encode_array_reuse.Print();

  auto fixed64_packed_decode = RunTimed("c++ protobuf fixed64 packed decode", kIterations, fixed64_packed_bytes.size(), [&]() {
    demo::Fixed64Packed decoded;
    if (!decoded.ParseFromString(fixed64_packed_bytes)) std::abort();
    asm volatile("" : : "g"(&decoded) : "memory");
  });
  fixed64_packed_decode.Print();

  demo::Fixed64Packed reused_fixed64_packed_decoded;
  auto fixed64_packed_decode_reuse = RunTimed("c++ protobuf fixed64 packed decode reuse", kIterations, fixed64_packed_bytes.size(), [&]() {
    reused_fixed64_packed_decoded.Clear();
    if (!reused_fixed64_packed_decoded.ParseFromString(fixed64_packed_bytes)) std::abort();
    asm volatile("" : : "g"(&reused_fixed64_packed_decoded) : "memory");
  });
  fixed64_packed_decode_reuse.Print();

  return 0;
}
