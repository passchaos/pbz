#include <chrono>
#include <cstdint>
#include <iostream>
#include <string>

#include "person.pb.h"

using Clock = std::chrono::steady_clock;

struct BenchResult {
  const char* name;
  int iterations;
  std::chrono::nanoseconds elapsed;
  std::size_t bytes_per_iter;

  void Print() const {
    const double elapsed_ns = static_cast<double>(elapsed.count());
    const double ns_per_iter = elapsed_ns / static_cast<double>(iterations);
    const double ops_per_sec = static_cast<double>(iterations) * 1000000000.0 / elapsed_ns;
    const double mib_per_sec = static_cast<double>(bytes_per_iter * iterations) * 1000000000.0 / elapsed_ns / (1024.0 * 1024.0);
    std::cout << name << ": " << iterations << " iters, " << bytes_per_iter
              << " bytes/iter, " << ns_per_iter << " ns/op, " << ops_per_sec
              << " ops/s, " << mib_per_sec << " MiB/s\n";
  }
};

template <class F>
BenchResult RunTimed(const char* name, int iterations, std::size_t bytes_per_iter, F&& f) {
  const auto start = Clock::now();
  for (int i = 0; i < iterations; ++i) f();
  const auto end = Clock::now();
  return BenchResult{name, iterations, std::chrono::duration_cast<std::chrono::nanoseconds>(end - start), bytes_per_iter};
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

  std::cout << "c++ protobuf benchmark baseline\n";
  std::cout << "payload size: " << bytes.size() << "\n";

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

  auto decode = RunTimed("c++ protobuf binary decode", kIterations, bytes.size(), [&]() {
    demo::Person decoded;
    if (!decoded.ParseFromString(bytes)) std::abort();
    asm volatile("" : : "g"(&decoded) : "memory");
  });
  decode.Print();

  return 0;
}
