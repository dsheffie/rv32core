#ifndef __tophh__
#define __tophh__

#include <cstdint>
#include <cstdlib>
#include <cstdint>
#include <vector>
#include <cmath>
#include <tuple>
#include <map>

#include <sys/time.h>

#include <sys/mman.h>
#include <unistd.h>
#include <fstream>
#include <sys/stat.h>
#include <fcntl.h>
#include <fenv.h>
#include <verilated.h>
#include "Vcore_l1d_l1i.h"
#include "loadelf.hh"
#include "helper.hh"
#include "interpret.hh"
#include "globals.hh"
#include "disassemble.hh"
#include "saveState.hh"

#include "Vcore_l1d_l1i__Dpi.h"
#include "svdpi.h"


struct dbl {
  uint64_t f : 52;
  uint64_t e : 11;
  uint64_t s : 1;
} __attribute__((packed));

union double_ {
  static const uint32_t bias = 1023;
  dbl dd;
  double d;
  double_(double x) : d(x) {
    static_assert(sizeof(dbl)==sizeof(uint64_t), "bad size");
  };
};

template <typename T>
static inline T round_to_alignment(T x, T m) {
  return ((x+m-1) / m) * m;
}

static inline uint32_t get_insn(uint32_t pc, const state_t *s) {
  return *reinterpret_cast<uint32_t*>(&s->mem[pc]);
}


static inline uint32_t to_uint32(float f) {
  return *reinterpret_cast<uint32_t*>(&f);
}

static inline uint64_t to_uint64(double d) {
  return *reinterpret_cast<uint64_t*>(&d);
}

static inline float to_float(uint32_t u) {
  return *reinterpret_cast<float*>(&u);
}

static inline double to_double(uint64_t u) {
  return *reinterpret_cast<double*>(&u);
}

static inline uint32_t mem_r32(const state_t*s, uint64_t ea) {
  assert(ea < (1UL<<32));
  return *reinterpret_cast<uint32_t*>(&s->mem[ea]);
}

static inline uint64_t mem_r64(const state_t*s, uint64_t ea) {
  assert(ea < (1UL<<32));
  return *reinterpret_cast<uint64_t*>(&s->mem[ea]);
}

static inline void mem_w32(state_t*s, uint64_t ea, uint32_t x) {
  assert(ea < (1UL<<32));  
  *reinterpret_cast<uint32_t*>(&s->mem[ea]) = x;
}

static inline void mem_w64(state_t*s, uint64_t ea, uint64_t x) {
  assert(ea < (1UL<<32));
  *reinterpret_cast<uint64_t*>(&s->mem[ea]) = x;
}

static inline uint8_t *mmap4G() {
  #ifdef __linux__
  void* mempt = mmap(nullptr, 1UL<<32, PROT_READ | PROT_WRITE,
#ifdef __amd64__
		     (21 << MAP_HUGE_SHIFT) |
#endif
		     MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
#else
  void* mempt = mmap(nullptr, 1UL<<32, PROT_READ | PROT_WRITE,
		     MAP_PRIVATE | MAP_ANONYMOUS , -1, 0);
#endif
  assert(mempt != reinterpret_cast<void*>(-1));
  assert(madvise(mempt, 1UL<<32, MADV_DONTNEED)==0);
  
  return reinterpret_cast<uint8_t*>(mempt);
}

static inline
void reset_core(std::unique_ptr<Vcore_l1d_l1i> &tb, uint64_t &cycle,
		uint32_t init_pc) {
  for(; (cycle < 4) && !Verilated::gotFinish(); ++cycle) {
    tb->mem_rsp_valid = 0;
    tb->monitor_ack = 0;
    tb->reset = 1;
    tb->extern_irq = 0;
    tb->clk = 1;
    tb->eval();
    tb->clk = 0;
    tb->eval();
    ++cycle;
  }
  //deassert reset
  tb->reset = 0;
  tb->clk = 1;
  tb->eval();
  tb->clk = 0;
  tb->eval();

  tb->resume_pc = init_pc;
  while(!tb->ready_for_resume) {
    ++cycle;  
    tb->clk = 1;
    tb->eval();
    tb->clk = 0;
    tb->eval();
  }
  
  ++cycle;
  tb->resume = 1;

  tb->clk = 1;
  tb->eval();
  tb->clk = 0;
  tb->eval();
  
  ++cycle;  
  tb->resume = 0;
  tb->clk = 1;
  tb->eval();
  tb->clk = 0;
  tb->eval();
}




#endif
