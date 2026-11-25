// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#include <cstddef>
#include <cstdio>
#include <cstdlib>

extern "C" int inner(int), abi_enter(int);
extern "C" {
unsigned frame_size;
int cleanup_count;
}
struct Observation {
  unsigned address, returns, any_nonzero, words[24], reasons;
};
static_assert(sizeof(Observation) == 112, "assembly observation stride");
static_assert(offsetof(Observation, words) == 12, "assembly snapshot offset");
extern "C" Observation private_observations[2];
extern "C" unsigned private_boundary_bytes[49];
static int token;

extern "C" [[noreturn]] void private_bounds_failure() {
  std::puts("FAIL reason=private-bounds");
  std::_Exit(77);
}

extern "C" void action(int) { throw &token; }
extern "C" int outer(int value) {
  try {
    inner(value);
  } catch (int *) {
    std::puts("FAIL reason=missed-private-observer");
  }
  return 88;
}

static unsigned print_private(unsigned index) {
  const auto &snapshot = private_observations[index];
  if (!snapshot.returns || snapshot.address + 96 > private_boundary_bytes[48])
    private_bounds_failure();
  std::printf("PRIVATE index=%u bytes=96 hex=", index);
  const auto *bytes = reinterpret_cast<const unsigned char *>(snapshot.words);
  unsigned residue = snapshot.any_nonzero;
  for (unsigned i = 0; i != 96; ++i) {
    std::printf("%02x", bytes[i]);
    residue |= bytes[i];
  }
  std::printf(" returns=%u OR=%x\n", snapshot.returns, residue);
  return residue;
}

extern "C" [[noreturn]] void boundary_probe(unsigned residue, unsigned,
                                            const unsigned *frame) {
  if (cleanup_count != 1 || frame[-4] != 0x1919)
    private_bounds_failure();
  std::printf("FRAME bytes=%u hex=", frame_size);
  const auto *bytes = reinterpret_cast<const unsigned char *>(frame);
  for (unsigned i = 0; i != frame_size; ++i)
    std::printf("%02x", bytes[i]);
  std::puts("");
  if (residue) {
    std::puts("FAIL reason=original-residue");
    std::_Exit(78);
  }
  unsigned private_residue = print_private(0);
  private_residue |= print_private(1);
  if (private_residue) {
    std::puts("FAIL reason=private-residue");
    std::_Exit(79);
  }
  for (unsigned i = 0; i != 48; ++i) {
    if (private_boundary_bytes[i] == 0x77335511U) {
      std::puts("FAIL reason=protected-copy");
      std::_Exit(80);
    }
  }
  std::puts("PASS mode=private");
  std::_Exit(0);
}

int main(int argc, char **argv) {
  if (argc != 2)
    private_bounds_failure();
  frame_size = std::strtoul(argv[1], nullptr, 0);
  if (frame_size != 32)
    private_bounds_failure();
  std::setvbuf(stdout, nullptr, _IONBF, 0);
  return abi_enter(7);
}
