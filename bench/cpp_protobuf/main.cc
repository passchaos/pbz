#include <algorithm>
#include <chrono>
#include <cstdint>
#include <iostream>
#include <string>

#include <google/protobuf/io/coded_stream.h>
#include <google/protobuf/io/zero_copy_stream_impl_lite.h>
#include <google/protobuf/text_format.h>
#include <google/protobuf/util/json_util.h>

#include "person.pb.h"

using Clock = std::chrono::steady_clock;
constexpr int kBenchmarkSamples = 3;

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

demo::Packed MakePacked() {
  demo::Packed packed;
  for (int i = 0; i < 1024; ++i)
    packed.add_values(i % 4096);
  return packed;
}

demo::FixedPacked MakeFixedPacked() {
  demo::FixedPacked packed;
  for (int i = 0; i < 1024; ++i)
    packed.add_values(i * 3 + 1);
  return packed;
}

demo::Fixed64Packed MakeFixed64Packed() {
  demo::Fixed64Packed packed;
  for (int i = 0; i < 1024; ++i)
    packed.add_values(static_cast<uint64_t>(i) * 5 + 1);
  return packed;
}

demo::UInt64Packed MakeUInt64Packed() {
  demo::UInt64Packed packed;
  for (int i = 0; i < 1024; ++i)
    packed.add_values((static_cast<uint64_t>(i) << 21) +
                      static_cast<uint64_t>(i) * 17 + 1);
  return packed;
}

demo::SInt64Packed MakeSInt64Packed() {
  demo::SInt64Packed packed;
  for (int i = 0; i < 1024; ++i) {
    const int64_t magnitude =
        (static_cast<int64_t>(i) << 20) + static_cast<int64_t>(i) * 13 + 1;
    packed.add_values((i & 1) == 0 ? magnitude : -magnitude);
  }
  return packed;
}

demo::Person MakePerson() {
  demo::Person person;
  person.set_id(7);
  person.set_name("Zig");
  for (int score : {10, 20, 30, 40, 50, 60, 70, 80})
    person.add_scores(score);
  (*person.mutable_counts())["red"] = 1;
  (*person.mutable_counts())["green"] = 2;
  (*person.mutable_counts())["blue"] = 3;
  return person;
}

demo::ScalarMix MakeScalarMix() {
  demo::ScalarMix msg;
  msg.set_active(true);
  msg.set_count(12345);
  msg.set_total(9876543210ULL);
  msg.set_delta(-321);
  msg.set_big_delta(-9876543);
  msg.set_checksum(0xdeadbeefU);
  msg.set_token(0x0102030405060708ULL);
  msg.set_signed_fixed(-123456);
  msg.set_signed_big_fixed(-9876543210LL);
  msg.set_ratio(1.25f);
  msg.set_score(9.5);
  msg.set_kind(demo::BENCH_KIND_BETA);
  for (bool flag : {true, false, true, true, false, true, false, false})
    msg.add_flags(flag);
  for (uint64_t id :
       {1ULL, 127ULL, 128ULL, 16384ULL, 1048576ULL, 9876543210ULL})
    msg.add_ids(id);
  return msg;
}

demo::TextBytes MakeTextBytes() {
  demo::TextBytes msg;
  msg.set_title("ASCII title for protobuf");
  msg.set_payload("0123456789abcdef0123456789abcdef");
  for (const char *tag : {"alpha", "beta", "gamma", "delta"})
    msg.add_tags(tag);
  for (const char *chunk :
       {"chunk-one", "chunk-two", "chunk-three", "chunk-four"})
    msg.add_chunks(chunk);
  return msg;
}

demo::Complex::Audit MakeAudit(const std::string &actor, int64_t at_unix) {
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
  const demo::ScalarMix scalarmix = MakeScalarMix();
  const demo::TextBytes textbytes = MakeTextBytes();
  const demo::Complex complex = MakeComplex();
  std::string bytes;
  person.SerializeToString(&bytes);
  std::string json;
  if (!google::protobuf::util::MessageToJsonString(person, &json).ok())
    std::abort();
  std::string text;
  if (!google::protobuf::TextFormat::PrintToString(person, &text))
    std::abort();
  std::string scalarmix_bytes;
  scalarmix.SerializeToString(&scalarmix_bytes);
  std::string textbytes_bytes;
  textbytes.SerializeToString(&textbytes_bytes);
  std::string complex_bytes;
  complex.SerializeToString(&complex_bytes);
  std::string complex_json;
  if (!google::protobuf::util::MessageToJsonString(complex, &complex_json).ok())
    std::abort();
  std::string complex_text;
  if (!google::protobuf::TextFormat::PrintToString(complex, &complex_text))
    std::abort();
  const demo::Packed packed = MakePacked();
  std::string packed_bytes;
  packed.SerializeToString(&packed_bytes);
  const demo::FixedPacked fixed_packed = MakeFixedPacked();
  std::string fixed_packed_bytes;
  fixed_packed.SerializeToString(&fixed_packed_bytes);
  const demo::Fixed64Packed fixed64_packed = MakeFixed64Packed();
  std::string fixed64_packed_bytes;
  fixed64_packed.SerializeToString(&fixed64_packed_bytes);
  const demo::UInt64Packed uint64_packed = MakeUInt64Packed();
  std::string uint64_packed_bytes;
  uint64_packed.SerializeToString(&uint64_packed_bytes);
  const demo::SInt64Packed sint64_packed = MakeSInt64Packed();
  std::string sint64_packed_bytes;
  sint64_packed.SerializeToString(&sint64_packed_bytes);

  std::cout << "c++ protobuf benchmark baseline\n";
  std::cout << "payload size: " << bytes.size() << "\n";
  std::cout << "json payload size: " << json.size() << "\n";
  std::cout << "text payload size: " << text.size() << "\n";
  std::cout << "scalarmix payload size: " << scalarmix_bytes.size() << "\n";
  std::cout << "textbytes payload size: " << textbytes_bytes.size() << "\n";
  std::cout << "complex payload size: " << complex_bytes.size() << "\n";
  std::cout << "complex json payload size: " << complex_json.size() << "\n";
  std::cout << "complex text payload size: " << complex_text.size() << "\n";
  std::cout << "packed payload size: " << packed_bytes.size() << "\n";
  std::cout << "fixed32 packed payload size: " << fixed_packed_bytes.size()
            << "\n";
  std::cout << "fixed64 packed payload size: " << fixed64_packed_bytes.size()
            << "\n";
  std::cout << "uint64 packed payload size: " << uint64_packed_bytes.size()
            << "\n";
  std::cout << "sint64 packed payload size: " << sint64_packed_bytes.size()
            << "\n";

  auto encode =
      RunTimed("c++ protobuf binary encode", kIterations, bytes.size(), [&]() {
        std::string out;
        out.reserve(bytes.size());
        person.SerializeToString(&out);
        asm volatile("" : : "g"(out.data()) : "memory");
      });
  encode.Print();

  std::string reused;
  reused.reserve(bytes.size());
  auto encode_reuse = RunTimed(
      "c++ protobuf binary encode reuse", kIterations, bytes.size(), [&]() {
        reused.clear();
        person.SerializeToString(&reused);
        asm volatile("" : : "g"(reused.data()) : "memory");
      });
  encode_reuse.Print();

  std::string array_buffer;
  array_buffer.resize(bytes.size());
  auto encode_array_reuse = RunTimed(
      "c++ protobuf binary SerializeToArray reuse", kIterations, bytes.size(),
      [&]() {
        if (!person.SerializeToArray(array_buffer.data(),
                                     static_cast<int>(array_buffer.size())))
          std::abort();
        asm volatile("" : : "g"(array_buffer.data()) : "memory");
      });
  encode_array_reuse.Print();

  std::string deterministic_buffer;
  deterministic_buffer.resize(bytes.size());
  auto deterministic_encode = RunTimed(
      "c++ protobuf deterministic binary encode reuse", kIterations,
      bytes.size(), [&]() {
        google::protobuf::io::ArrayOutputStream array_stream(
            deterministic_buffer.data(),
            static_cast<int>(deterministic_buffer.size()));
        google::protobuf::io::CodedOutputStream coded_stream(&array_stream);
        coded_stream.SetSerializationDeterministic(true);
        person.SerializeWithCachedSizes(&coded_stream);
        coded_stream.Trim();
        if (coded_stream.HadError())
          std::abort();
        asm volatile("" : : "g"(deterministic_buffer.data()) : "memory");
      });
  deterministic_encode.Print();

  auto decode =
      RunTimed("c++ protobuf binary decode", kIterations, bytes.size(), [&]() {
        demo::Person decoded;
        if (!decoded.ParseFromString(bytes))
          std::abort();
        asm volatile("" : : "g"(&decoded) : "memory");
      });
  decode.Print();

  demo::Person reused_decoded;
  auto decode_reuse = RunTimed(
      "c++ protobuf binary decode reuse", kIterations, bytes.size(), [&]() {
        reused_decoded.Clear();
        if (!reused_decoded.ParseFromString(bytes))
          std::abort();
        asm volatile("" : : "g"(&reused_decoded) : "memory");
      });
  decode_reuse.Print();

  auto scalarmix_encode =
      RunTimed("c++ protobuf scalarmix encode", kIterations,
               scalarmix_bytes.size(), [&]() {
                 std::string out;
                 out.reserve(scalarmix_bytes.size());
                 scalarmix.SerializeToString(&out);
                 asm volatile("" : : "g"(out.data()) : "memory");
               });
  scalarmix_encode.Print();
  std::string scalarmix_array_buffer;
  scalarmix_array_buffer.resize(scalarmix_bytes.size());
  auto scalarmix_encode_array_reuse = RunTimed(
      "c++ protobuf scalarmix SerializeToArray reuse", kIterations,
      scalarmix_bytes.size(), [&]() {
        if (!scalarmix.SerializeToArray(
                scalarmix_array_buffer.data(),
                static_cast<int>(scalarmix_array_buffer.size())))
          std::abort();
        asm volatile("" : : "g"(scalarmix_array_buffer.data()) : "memory");
      });
  scalarmix_encode_array_reuse.Print();
  auto scalarmix_decode =
      RunTimed("c++ protobuf scalarmix decode", kIterations,
               scalarmix_bytes.size(), [&]() {
                 demo::ScalarMix decoded;
                 if (!decoded.ParseFromString(scalarmix_bytes))
                   std::abort();
                 asm volatile("" : : "g"(&decoded) : "memory");
               });
  scalarmix_decode.Print();
  demo::ScalarMix reused_scalarmix_decoded;
  auto scalarmix_decode_reuse =
      RunTimed("c++ protobuf scalarmix decode reuse", kIterations,
               scalarmix_bytes.size(), [&]() {
                 reused_scalarmix_decoded.Clear();
                 if (!reused_scalarmix_decoded.ParseFromString(scalarmix_bytes))
                   std::abort();
                 asm volatile("" : : "g"(&reused_scalarmix_decoded) : "memory");
               });
  scalarmix_decode_reuse.Print();

  auto textbytes_encode =
      RunTimed("c++ protobuf textbytes encode", kIterations,
               textbytes_bytes.size(), [&]() {
                 std::string out;
                 out.reserve(textbytes_bytes.size());
                 textbytes.SerializeToString(&out);
                 asm volatile("" : : "g"(out.data()) : "memory");
               });
  textbytes_encode.Print();

  std::string reused_textbytes;
  reused_textbytes.reserve(textbytes_bytes.size());
  auto textbytes_encode_reuse =
      RunTimed("c++ protobuf textbytes encode reuse", kIterations,
               textbytes_bytes.size(), [&]() {
                 reused_textbytes.clear();
                 textbytes.SerializeToString(&reused_textbytes);
                 asm volatile("" : : "g"(reused_textbytes.data()) : "memory");
               });
  textbytes_encode_reuse.Print();

  std::string textbytes_array_buffer;
  textbytes_array_buffer.resize(textbytes_bytes.size());
  auto textbytes_encode_array_reuse = RunTimed(
      "c++ protobuf textbytes SerializeToArray reuse", kIterations,
      textbytes_bytes.size(), [&]() {
        if (!textbytes.SerializeToArray(
                textbytes_array_buffer.data(),
                static_cast<int>(textbytes_array_buffer.size())))
          std::abort();
        asm volatile("" : : "g"(textbytes_array_buffer.data()) : "memory");
      });
  textbytes_encode_array_reuse.Print();

  auto textbytes_decode =
      RunTimed("c++ protobuf textbytes decode", kIterations,
               textbytes_bytes.size(), [&]() {
                 demo::TextBytes decoded;
                 if (!decoded.ParseFromString(textbytes_bytes))
                   std::abort();
                 asm volatile("" : : "g"(&decoded) : "memory");
               });
  textbytes_decode.Print();

  demo::TextBytes reused_textbytes_decoded;
  auto textbytes_decode_reuse =
      RunTimed("c++ protobuf textbytes decode reuse", kIterations,
               textbytes_bytes.size(), [&]() {
                 reused_textbytes_decoded.Clear();
                 if (!reused_textbytes_decoded.ParseFromString(textbytes_bytes))
                   std::abort();
                 asm volatile("" : : "g"(&reused_textbytes_decoded) : "memory");
               });
  textbytes_decode_reuse.Print();

  auto complex_encode = RunTimed(
      "c++ protobuf complex encode", kIterations, complex_bytes.size(), [&]() {
        std::string out;
        out.reserve(complex_bytes.size());
        complex.SerializeToString(&out);
        asm volatile("" : : "g"(out.data()) : "memory");
      });
  complex_encode.Print();

  std::string reused_complex;
  reused_complex.reserve(complex_bytes.size());
  auto complex_encode_reuse =
      RunTimed("c++ protobuf complex encode reuse", kIterations,
               complex_bytes.size(), [&]() {
                 reused_complex.clear();
                 complex.SerializeToString(&reused_complex);
                 asm volatile("" : : "g"(reused_complex.data()) : "memory");
               });
  complex_encode_reuse.Print();

  std::string complex_array_buffer;
  complex_array_buffer.resize(complex_bytes.size());
  auto complex_encode_array_reuse = RunTimed(
      "c++ protobuf complex SerializeToArray reuse", kIterations,
      complex_bytes.size(), [&]() {
        if (!complex.SerializeToArray(
                complex_array_buffer.data(),
                static_cast<int>(complex_array_buffer.size())))
          std::abort();
        asm volatile("" : : "g"(complex_array_buffer.data()) : "memory");
      });
  complex_encode_array_reuse.Print();

  std::string complex_deterministic_buffer;
  complex_deterministic_buffer.resize(complex_bytes.size());
  auto complex_deterministic_encode = RunTimed(
      "c++ protobuf complex deterministic binary encode reuse", kIterations,
      complex_bytes.size(), [&]() {
        google::protobuf::io::ArrayOutputStream array_stream(
            complex_deterministic_buffer.data(),
            static_cast<int>(complex_deterministic_buffer.size()));
        google::protobuf::io::CodedOutputStream coded_stream(&array_stream);
        coded_stream.SetSerializationDeterministic(true);
        complex.SerializeWithCachedSizes(&coded_stream);
        coded_stream.Trim();
        if (coded_stream.HadError())
          std::abort();
        asm volatile(""
                     :
                     : "g"(complex_deterministic_buffer.data())
                     : "memory");
      });
  complex_deterministic_encode.Print();

  auto complex_decode = RunTimed(
      "c++ protobuf complex decode", kIterations, complex_bytes.size(), [&]() {
        demo::Complex decoded;
        if (!decoded.ParseFromString(complex_bytes))
          std::abort();
        asm volatile("" : : "g"(&decoded) : "memory");
      });
  complex_decode.Print();

  demo::Complex reused_complex_decoded;
  auto complex_decode_reuse =
      RunTimed("c++ protobuf complex decode reuse", kIterations,
               complex_bytes.size(), [&]() {
                 reused_complex_decoded.Clear();
                 if (!reused_complex_decoded.ParseFromString(complex_bytes))
                   std::abort();
                 asm volatile("" : : "g"(&reused_complex_decoded) : "memory");
               });
  complex_decode_reuse.Print();

  auto complex_json_stringify = RunTimed(
      "c++ protobuf complex JSON stringify", kIterations, complex_json.size(),
      [&]() {
        std::string out;
        if (!google::protobuf::util::MessageToJsonString(complex, &out).ok())
          std::abort();
        asm volatile("" : : "g"(out.data()) : "memory");
      });
  complex_json_stringify.Print();

  std::string reused_complex_json;
  reused_complex_json.reserve(complex_json.size());
  auto complex_json_stringify_reuse = RunTimed(
      "c++ protobuf complex JSON stringify reuse", kIterations,
      complex_json.size(), [&]() {
        reused_complex_json.clear();
        if (!google::protobuf::util::MessageToJsonString(complex,
                                                         &reused_complex_json)
                 .ok())
          std::abort();
        asm volatile("" : : "g"(reused_complex_json.data()) : "memory");
      });
  complex_json_stringify_reuse.Print();

  auto complex_json_parse = RunTimed(
      "c++ protobuf complex JSON parse", kIterations, complex_json.size(),
      [&]() {
        demo::Complex decoded;
        if (!google::protobuf::util::JsonStringToMessage(complex_json, &decoded)
                 .ok())
          std::abort();
        asm volatile("" : : "g"(&decoded) : "memory");
      });
  complex_json_parse.Print();

  demo::Complex reused_complex_json_decoded;
  auto complex_json_parse_reuse = RunTimed(
      "c++ protobuf complex JSON parse reuse", kIterations, complex_json.size(),
      [&]() {
        reused_complex_json_decoded.Clear();
        if (!google::protobuf::util::JsonStringToMessage(
                 complex_json, &reused_complex_json_decoded)
                 .ok())
          std::abort();
        asm volatile("" : : "g"(&reused_complex_json_decoded) : "memory");
      });
  complex_json_parse_reuse.Print();

  auto complex_text_format = RunTimed(
      "c++ protobuf complex TextFormat format", kIterations,
      complex_text.size(), [&]() {
        std::string out;
        if (!google::protobuf::TextFormat::PrintToString(complex, &out))
          std::abort();
        asm volatile("" : : "g"(out.data()) : "memory");
      });
  complex_text_format.Print();

  std::string reused_complex_text;
  reused_complex_text.reserve(complex_text.size());
  auto complex_text_format_reuse = RunTimed(
      "c++ protobuf complex TextFormat format reuse", kIterations,
      complex_text.size(), [&]() {
        reused_complex_text.clear();
        if (!google::protobuf::TextFormat::PrintToString(complex,
                                                         &reused_complex_text))
          std::abort();
        asm volatile("" : : "g"(reused_complex_text.data()) : "memory");
      });
  complex_text_format_reuse.Print();

  auto complex_text_parse =
      RunTimed("c++ protobuf complex TextFormat parse", kIterations,
               complex_text.size(), [&]() {
                 demo::Complex decoded;
                 if (!google::protobuf::TextFormat::ParseFromString(
                         complex_text, &decoded))
                   std::abort();
                 asm volatile("" : : "g"(&decoded) : "memory");
               });
  complex_text_parse.Print();

  demo::Complex reused_complex_text_decoded;
  auto complex_text_parse_reuse = RunTimed(
      "c++ protobuf complex TextFormat parse reuse", kIterations,
      complex_text.size(), [&]() {
        reused_complex_text_decoded.Clear();
        if (!google::protobuf::TextFormat::ParseFromString(
                complex_text, &reused_complex_text_decoded))
          std::abort();
        asm volatile("" : : "g"(&reused_complex_text_decoded) : "memory");
      });
  complex_text_parse_reuse.Print();

  auto json_stringify =
      RunTimed("c++ protobuf JSON stringify", kIterations, json.size(), [&]() {
        std::string out;
        if (!google::protobuf::util::MessageToJsonString(person, &out).ok())
          std::abort();
        asm volatile("" : : "g"(out.data()) : "memory");
      });
  json_stringify.Print();

  std::string reused_json;
  reused_json.reserve(json.size());
  auto json_stringify_reuse = RunTimed(
      "c++ protobuf JSON stringify reuse", kIterations, json.size(), [&]() {
        reused_json.clear();
        if (!google::protobuf::util::MessageToJsonString(person, &reused_json)
                 .ok())
          std::abort();
        asm volatile("" : : "g"(reused_json.data()) : "memory");
      });
  json_stringify_reuse.Print();

  auto json_parse =
      RunTimed("c++ protobuf JSON parse", kIterations, json.size(), [&]() {
        demo::Person decoded;
        if (!google::protobuf::util::JsonStringToMessage(json, &decoded).ok())
          std::abort();
        asm volatile("" : : "g"(&decoded) : "memory");
      });
  json_parse.Print();

  demo::Person reused_json_decoded;
  auto json_parse_reuse = RunTimed(
      "c++ protobuf JSON parse reuse", kIterations, json.size(), [&]() {
        reused_json_decoded.Clear();
        if (!google::protobuf::util::JsonStringToMessage(json,
                                                         &reused_json_decoded)
                 .ok())
          std::abort();
        asm volatile("" : : "g"(&reused_json_decoded) : "memory");
      });
  json_parse_reuse.Print();

  auto text_format = RunTimed(
      "c++ protobuf TextFormat format", kIterations, text.size(), [&]() {
        std::string out;
        if (!google::protobuf::TextFormat::PrintToString(person, &out))
          std::abort();
        asm volatile("" : : "g"(out.data()) : "memory");
      });
  text_format.Print();

  std::string reused_text;
  reused_text.reserve(text.size());
  auto text_format_reuse = RunTimed(
      "c++ protobuf TextFormat format reuse", kIterations, text.size(), [&]() {
        reused_text.clear();
        if (!google::protobuf::TextFormat::PrintToString(person, &reused_text))
          std::abort();
        asm volatile("" : : "g"(reused_text.data()) : "memory");
      });
  text_format_reuse.Print();

  auto text_parse = RunTimed(
      "c++ protobuf TextFormat parse", kIterations, text.size(), [&]() {
        demo::Person decoded;
        if (!google::protobuf::TextFormat::ParseFromString(text, &decoded))
          std::abort();
        asm volatile("" : : "g"(&decoded) : "memory");
      });
  text_parse.Print();

  demo::Person reused_text_decoded;
  auto text_parse_reuse = RunTimed(
      "c++ protobuf TextFormat parse reuse", kIterations, text.size(), [&]() {
        reused_text_decoded.Clear();
        if (!google::protobuf::TextFormat::ParseFromString(
                text, &reused_text_decoded))
          std::abort();
        asm volatile("" : : "g"(&reused_text_decoded) : "memory");
      });
  text_parse_reuse.Print();

  auto packed_encode = RunTimed(
      "c++ protobuf packed encode", kIterations, packed_bytes.size(), [&]() {
        std::string out;
        out.reserve(packed_bytes.size());
        packed.SerializeToString(&out);
        asm volatile("" : : "g"(out.data()) : "memory");
      });
  packed_encode.Print();

  std::string reused_packed;
  reused_packed.reserve(packed_bytes.size());
  auto packed_encode_reuse =
      RunTimed("c++ protobuf packed encode reuse", kIterations,
               packed_bytes.size(), [&]() {
                 reused_packed.clear();
                 packed.SerializeToString(&reused_packed);
                 asm volatile("" : : "g"(reused_packed.data()) : "memory");
               });
  packed_encode_reuse.Print();

  std::string packed_array_buffer;
  packed_array_buffer.resize(packed_bytes.size());
  auto packed_encode_array_reuse = RunTimed(
      "c++ protobuf packed SerializeToArray reuse", kIterations,
      packed_bytes.size(), [&]() {
        if (!packed.SerializeToArray(
                packed_array_buffer.data(),
                static_cast<int>(packed_array_buffer.size())))
          std::abort();
        asm volatile("" : : "g"(packed_array_buffer.data()) : "memory");
      });
  packed_encode_array_reuse.Print();

  auto packed_decode = RunTimed("c++ protobuf packed decode", kIterations,
                                packed_bytes.size(), [&]() {
                                  demo::Packed decoded;
                                  if (!decoded.ParseFromString(packed_bytes))
                                    std::abort();
                                  asm volatile("" : : "g"(&decoded) : "memory");
                                });
  packed_decode.Print();

  demo::Packed reused_packed_decoded;
  auto packed_decode_reuse =
      RunTimed("c++ protobuf packed decode reuse", kIterations,
               packed_bytes.size(), [&]() {
                 reused_packed_decoded.Clear();
                 if (!reused_packed_decoded.ParseFromString(packed_bytes))
                   std::abort();
                 asm volatile("" : : "g"(&reused_packed_decoded) : "memory");
               });
  packed_decode_reuse.Print();

  auto fixed_packed_encode =
      RunTimed("c++ protobuf fixed32 packed encode", kIterations,
               fixed_packed_bytes.size(), [&]() {
                 std::string out;
                 out.reserve(fixed_packed_bytes.size());
                 fixed_packed.SerializeToString(&out);
                 asm volatile("" : : "g"(out.data()) : "memory");
               });
  fixed_packed_encode.Print();

  std::string fixed_packed_array_buffer;
  fixed_packed_array_buffer.resize(fixed_packed_bytes.size());
  auto fixed_packed_encode_array_reuse = RunTimed(
      "c++ protobuf fixed32 packed SerializeToArray reuse", kIterations,
      fixed_packed_bytes.size(), [&]() {
        if (!fixed_packed.SerializeToArray(
                fixed_packed_array_buffer.data(),
                static_cast<int>(fixed_packed_array_buffer.size())))
          std::abort();
        asm volatile("" : : "g"(fixed_packed_array_buffer.data()) : "memory");
      });
  fixed_packed_encode_array_reuse.Print();

  auto fixed_packed_decode =
      RunTimed("c++ protobuf fixed32 packed decode", kIterations,
               fixed_packed_bytes.size(), [&]() {
                 demo::FixedPacked decoded;
                 if (!decoded.ParseFromString(fixed_packed_bytes))
                   std::abort();
                 asm volatile("" : : "g"(&decoded) : "memory");
               });
  fixed_packed_decode.Print();

  demo::FixedPacked reused_fixed_packed_decoded;
  auto fixed_packed_decode_reuse = RunTimed(
      "c++ protobuf fixed32 packed decode reuse", kIterations,
      fixed_packed_bytes.size(), [&]() {
        reused_fixed_packed_decoded.Clear();
        if (!reused_fixed_packed_decoded.ParseFromString(fixed_packed_bytes))
          std::abort();
        asm volatile("" : : "g"(&reused_fixed_packed_decoded) : "memory");
      });
  fixed_packed_decode_reuse.Print();

  auto fixed64_packed_encode =
      RunTimed("c++ protobuf fixed64 packed encode", kIterations,
               fixed64_packed_bytes.size(), [&]() {
                 std::string out;
                 out.reserve(fixed64_packed_bytes.size());
                 fixed64_packed.SerializeToString(&out);
                 asm volatile("" : : "g"(out.data()) : "memory");
               });
  fixed64_packed_encode.Print();

  std::string fixed64_packed_array_buffer;
  fixed64_packed_array_buffer.resize(fixed64_packed_bytes.size());
  auto fixed64_packed_encode_array_reuse = RunTimed(
      "c++ protobuf fixed64 packed SerializeToArray reuse", kIterations,
      fixed64_packed_bytes.size(), [&]() {
        if (!fixed64_packed.SerializeToArray(
                fixed64_packed_array_buffer.data(),
                static_cast<int>(fixed64_packed_array_buffer.size())))
          std::abort();
        asm volatile("" : : "g"(fixed64_packed_array_buffer.data()) : "memory");
      });
  fixed64_packed_encode_array_reuse.Print();

  auto fixed64_packed_decode =
      RunTimed("c++ protobuf fixed64 packed decode", kIterations,
               fixed64_packed_bytes.size(), [&]() {
                 demo::Fixed64Packed decoded;
                 if (!decoded.ParseFromString(fixed64_packed_bytes))
                   std::abort();
                 asm volatile("" : : "g"(&decoded) : "memory");
               });
  fixed64_packed_decode.Print();

  demo::Fixed64Packed reused_fixed64_packed_decoded;
  auto fixed64_packed_decode_reuse = RunTimed(
      "c++ protobuf fixed64 packed decode reuse", kIterations,
      fixed64_packed_bytes.size(), [&]() {
        reused_fixed64_packed_decoded.Clear();
        if (!reused_fixed64_packed_decoded.ParseFromString(
                fixed64_packed_bytes))
          std::abort();
        asm volatile("" : : "g"(&reused_fixed64_packed_decoded) : "memory");
      });
  fixed64_packed_decode_reuse.Print();

  auto uint64_packed_encode =
      RunTimed("c++ protobuf uint64 packed encode", kIterations,
               uint64_packed_bytes.size(), [&]() {
                 std::string out;
                 out.reserve(uint64_packed_bytes.size());
                 uint64_packed.SerializeToString(&out);
                 asm volatile("" : : "g"(out.data()) : "memory");
               });
  uint64_packed_encode.Print();

  std::string uint64_packed_array_buffer;
  uint64_packed_array_buffer.resize(uint64_packed_bytes.size());
  auto uint64_packed_encode_array_reuse = RunTimed(
      "c++ protobuf uint64 packed SerializeToArray reuse", kIterations,
      uint64_packed_bytes.size(), [&]() {
        if (!uint64_packed.SerializeToArray(
                uint64_packed_array_buffer.data(),
                static_cast<int>(uint64_packed_array_buffer.size())))
          std::abort();
        asm volatile("" : : "g"(uint64_packed_array_buffer.data()) : "memory");
      });
  uint64_packed_encode_array_reuse.Print();

  auto uint64_packed_decode =
      RunTimed("c++ protobuf uint64 packed decode", kIterations,
               uint64_packed_bytes.size(), [&]() {
                 demo::UInt64Packed decoded;
                 if (!decoded.ParseFromString(uint64_packed_bytes))
                   std::abort();
                 asm volatile("" : : "g"(&decoded) : "memory");
               });
  uint64_packed_decode.Print();

  demo::UInt64Packed reused_uint64_packed_decoded;
  auto uint64_packed_decode_reuse = RunTimed(
      "c++ protobuf uint64 packed decode reuse", kIterations,
      uint64_packed_bytes.size(), [&]() {
        reused_uint64_packed_decoded.Clear();
        if (!reused_uint64_packed_decoded.ParseFromString(uint64_packed_bytes))
          std::abort();
        asm volatile("" : : "g"(&reused_uint64_packed_decoded) : "memory");
      });
  uint64_packed_decode_reuse.Print();

  auto sint64_packed_encode =
      RunTimed("c++ protobuf sint64 packed encode", kIterations,
               sint64_packed_bytes.size(), [&]() {
                 std::string out;
                 out.reserve(sint64_packed_bytes.size());
                 sint64_packed.SerializeToString(&out);
                 asm volatile("" : : "g"(out.data()) : "memory");
               });
  sint64_packed_encode.Print();

  std::string sint64_packed_array_buffer;
  sint64_packed_array_buffer.resize(sint64_packed_bytes.size());
  auto sint64_packed_encode_array_reuse = RunTimed(
      "c++ protobuf sint64 packed SerializeToArray reuse", kIterations,
      sint64_packed_bytes.size(), [&]() {
        if (!sint64_packed.SerializeToArray(
                sint64_packed_array_buffer.data(),
                static_cast<int>(sint64_packed_array_buffer.size())))
          std::abort();
        asm volatile("" : : "g"(sint64_packed_array_buffer.data()) : "memory");
      });
  sint64_packed_encode_array_reuse.Print();

  auto sint64_packed_decode =
      RunTimed("c++ protobuf sint64 packed decode", kIterations,
               sint64_packed_bytes.size(), [&]() {
                 demo::SInt64Packed decoded;
                 if (!decoded.ParseFromString(sint64_packed_bytes))
                   std::abort();
                 asm volatile("" : : "g"(&decoded) : "memory");
               });
  sint64_packed_decode.Print();

  demo::SInt64Packed reused_sint64_packed_decoded;
  auto sint64_packed_decode_reuse = RunTimed(
      "c++ protobuf sint64 packed decode reuse", kIterations,
      sint64_packed_bytes.size(), [&]() {
        reused_sint64_packed_decoded.Clear();
        if (!reused_sint64_packed_decoded.ParseFromString(sint64_packed_bytes))
          std::abort();
        asm volatile("" : : "g"(&reused_sint64_packed_decoded) : "memory");
      });
  sint64_packed_decode_reuse.Print();

  return 0;
}
