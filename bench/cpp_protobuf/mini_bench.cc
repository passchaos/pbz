#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdint>
#include <iostream>
#include <limits>
#include <string>
#include <vector>

#include "person.pb.h"

using Clock = std::chrono::steady_clock;
constexpr int kBenchmarkSamples = 3;
constexpr int kIterations = 20000;
constexpr int kLargeBytesPayloadLen = 64 * 1024;
constexpr int kLargeBytesChunkCount = 16;
constexpr int kLargeBytesChunkLen = 4 * 1024;

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
  for (int i = 0; i < warmup_iterations; ++i) f();

  auto best = std::chrono::nanoseconds::max();
  for (int sample = 0; sample < kBenchmarkSamples; ++sample) {
    const auto start = Clock::now();
    for (int i = 0; i < iterations; ++i) f();
    const auto end = Clock::now();
    best = std::min(best, std::chrono::duration_cast<std::chrono::nanoseconds>(
                              end - start));
  }
  return BenchResult{name, iterations, kBenchmarkSamples, best, bytes_per_iter};
}

demo::Person MakePerson() {
  demo::Person person;
  person.set_id(7);
  person.set_name("Zig");
  for (int value : {10, 20, 30, 40, 50, 60, 70, 80}) {
    person.add_scores(value);
  }
  (*person.mutable_counts())["red"] = 1;
  (*person.mutable_counts())["green"] = 2;
  (*person.mutable_counts())["blue"] = 3;
  return person;
}

demo::LargeBytes MakeLargeBytes() {
  demo::LargeBytes message;
  std::string payload(kLargeBytesPayloadLen, static_cast<char>(0x5a));
  message.set_payload(payload);
  for (int i = 0; i < kLargeBytesChunkCount; ++i) {
    message.add_chunks(std::string(kLargeBytesChunkLen, static_cast<char>(0x33)));
  }
  return message;
}

demo::FixedPacked MakeFixedPacked() {
  demo::FixedPacked message;
  for (int i = 0; i < 1024; ++i) message.add_values(i * 3 + 1);
  return message;
}

int main() {
  const demo::Person person = MakePerson();
  const demo::LargeBytes largebytes = MakeLargeBytes();
  const demo::FixedPacked fixed_packed = MakeFixedPacked();

  std::string bytes;
  person.SerializeToString(&bytes);
  std::string largebytes_bytes;
  largebytes.SerializeToString(&largebytes_bytes);
  std::string fixed_packed_bytes;
  fixed_packed.SerializeToString(&fixed_packed_bytes);

  std::string reused;
  reused.resize(bytes.size());
  std::vector<char> array_buffer(bytes.size());
  RunTimed("c++ protobuf binary encode", kIterations, bytes.size(), [&]() {
    std::string out;
    person.SerializeToString(&out);
    asm volatile("" : : "g"(out.data()) : "memory");
  }).Print();
  RunTimed("c++ protobuf binary encode reuse", kIterations, bytes.size(), [&]() {
    person.SerializeToString(&reused);
    asm volatile("" : : "g"(reused.data()) : "memory");
  }).Print();
  RunTimed("c++ protobuf binary SerializeToArray reuse", kIterations,
           bytes.size(), [&]() {
             person.SerializeToArray(array_buffer.data(), array_buffer.size());
             asm volatile("" : : "g"(array_buffer.data()) : "memory");
           }).Print();
  RunTimed("c++ protobuf binary decode", kIterations, bytes.size(), [&]() {
    demo::Person decoded;
    if (!decoded.ParseFromString(bytes)) std::abort();
    asm volatile("" : : "g"(&decoded) : "memory");
  }).Print();
  demo::Person reused_decoded;
  RunTimed("c++ protobuf binary decode reuse", kIterations, bytes.size(), [&]() {
    if (!reused_decoded.ParseFromString(bytes)) std::abort();
    asm volatile("" : : "g"(&reused_decoded) : "memory");
  }).Print();

  std::string largebytes_reused;
  largebytes_reused.resize(largebytes_bytes.size());
  std::vector<char> largebytes_array(largebytes_bytes.size());
  RunTimed("c++ protobuf largebytes encode", kIterations,
           largebytes_bytes.size(), [&]() {
             std::string out;
             largebytes.SerializeToString(&out);
             asm volatile("" : : "g"(out.data()) : "memory");
           }).Print();
  RunTimed("c++ protobuf largebytes encode reuse", kIterations,
           largebytes_bytes.size(), [&]() {
             largebytes.SerializeToString(&largebytes_reused);
             asm volatile("" : : "g"(largebytes_reused.data()) : "memory");
           }).Print();
  RunTimed("c++ protobuf largebytes SerializeToArray reuse", kIterations,
           largebytes_bytes.size(), [&]() {
             largebytes.SerializeToArray(largebytes_array.data(),
                                         largebytes_array.size());
             asm volatile("" : : "g"(largebytes_array.data()) : "memory");
           }).Print();
  RunTimed("c++ protobuf largebytes decode", kIterations,
           largebytes_bytes.size(), [&]() {
             demo::LargeBytes decoded;
             if (!decoded.ParseFromString(largebytes_bytes)) std::abort();
             asm volatile("" : : "g"(&decoded) : "memory");
           }).Print();
  demo::LargeBytes largebytes_reused_decoded;
  RunTimed("c++ protobuf largebytes decode reuse", kIterations,
           largebytes_bytes.size(), [&]() {
             if (!largebytes_reused_decoded.ParseFromString(largebytes_bytes))
               std::abort();
             asm volatile("" : : "g"(&largebytes_reused_decoded) : "memory");
           }).Print();

  std::string fixed_packed_reused;
  fixed_packed_reused.resize(fixed_packed_bytes.size());
  std::vector<char> fixed_packed_array(fixed_packed_bytes.size());
  RunTimed("c++ protobuf fixed32 packed encode", kIterations,
           fixed_packed_bytes.size(), [&]() {
             std::string out;
             fixed_packed.SerializeToString(&out);
             asm volatile("" : : "g"(out.data()) : "memory");
           }).Print();
  RunTimed("c++ protobuf fixed32 packed SerializeToArray reuse", kIterations,
           fixed_packed_bytes.size(), [&]() {
             fixed_packed.SerializeToArray(fixed_packed_array.data(),
                                           fixed_packed_array.size());
             asm volatile("" : : "g"(fixed_packed_array.data()) : "memory");
           }).Print();
  RunTimed("c++ protobuf fixed32 packed decode", kIterations,
           fixed_packed_bytes.size(), [&]() {
             demo::FixedPacked decoded;
             if (!decoded.ParseFromString(fixed_packed_bytes)) std::abort();
             asm volatile("" : : "g"(&decoded) : "memory");
           }).Print();
  demo::FixedPacked fixed_packed_reused_decoded;
  RunTimed("c++ protobuf fixed32 packed decode reuse", kIterations,
           fixed_packed_bytes.size(), [&]() {
             if (!fixed_packed_reused_decoded.ParseFromString(fixed_packed_bytes))
               std::abort();
             asm volatile("" : : "g"(&fixed_packed_reused_decoded) : "memory");
           }).Print();

  return 0;
}
