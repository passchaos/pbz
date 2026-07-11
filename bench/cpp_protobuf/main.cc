#include <chrono>
#include <cstdint>
#include <algorithm>
#include <iostream>
#include <string>

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

int main() {
  constexpr int kIterations = 20000;
  const demo::Person person = MakePerson();
  std::string bytes;
  person.SerializeToString(&bytes);
  const demo::Packed packed = MakePacked();
  std::string packed_bytes;
  packed.SerializeToString(&packed_bytes);

  std::cout << "c++ protobuf benchmark baseline\n";
  std::cout << "payload size: " << bytes.size() << "\n";
  std::cout << "packed payload size: " << packed_bytes.size() << "\n";

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

  auto decode = RunTimed("c++ protobuf binary decode", kIterations, bytes.size(), [&]() {
    demo::Person decoded;
    if (!decoded.ParseFromString(bytes)) std::abort();
    asm volatile("" : : "g"(&decoded) : "memory");
  });
  decode.Print();

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

  return 0;
}
