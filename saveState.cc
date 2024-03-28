#include <cstdint>
#include <cassert>
#include <cstring>
#include <iostream>
#include <unistd.h>
#include <fcntl.h>
#include "interpret.hh"
#include "globals.hh"

struct page {
  uint32_t va;
  uint8_t data[4096];
} __attribute__((packed));

static const uint64_t MAGICNUM = 0x64646464beefd00dUL;

struct header {
  uint64_t magic;
  uint64_t pc;
  int64_t gpr[32];
  uint64_t icnt;
  uint32_t num_nz_pages;
  uint64_t tohost_addr;
  uint64_t fromhost_addr;  
  header() {}
} __attribute__((packed));

void dumpState(const state_t &s, const std::string &filename) {}

void loadState(state_t &s, const std::string &filename) {
  header h;
  int fd = ::open(filename.c_str(), O_RDONLY, 0600);
  assert(fd != -1);
  size_t sz = read(fd, &h, sizeof(h));
  assert(sz == sizeof(h));
  //std::cout << "got magic number of " << std::hex << h.magic << std::dec << "\n";
  //std::cout << "got pc of " << std::hex << h.pc << std::dec << "\n";
  //assert(h.magic == MAGICNUM);
  s.pc = h.pc;
  memcpy(&s.gpr,&h.gpr,sizeof(s.gpr));
  s.icnt = h.icnt;
  globals::tohost_addr = h.tohost_addr;
  globals::fromhost_addr = h.fromhost_addr;
  for(uint32_t i = 0; i < h.num_nz_pages; i++) {
    page p;
    sz = read(fd, &p, sizeof(p));
    //std::cout << "sz = " << sz << "\n";
    assert(sz == sizeof(p));
    memcpy(s.mem+p.va, p.data, 4096);
  }
  close(fd);
}

static void emitGprValue(state_t &s, uint64_t &pc, int i, uint64_t u) {
  int addi = 0, slli = 0;
  slli = ((8) << 20) | (i<<15) | 1 << 12 | (i<<7) | 0x13;
  for(int j = 56; j >= 0; j-=8) {
    uint8_t v = (u>>j) & 0x0ff;
    if(v) {
      addi = ((v) << 20) | (i<<15) | 0 << 12 | (i<<7) | 0x13;
      *reinterpret_cast<int*>(&s.mem[pc]) = addi;
      pc += 4;	
    }
    
    if(j != 0) {
      *reinterpret_cast<int*>(&s.mem[pc]) = slli;
      pc += 4;
    }
  }  
}


void emitCodeForInitialRegisterValues(state_t &s, uint64_t pc) {

  for(int i = 1; i < 32; i++) {
    uint64_t u = *reinterpret_cast<uint64_t*>(&s.gpr[i]);
    emitGprValue(s, pc, i, u);
  }
  
  *reinterpret_cast<int*>(&s.mem[pc]) = 0x73;
  pc += 4;
  for(int i = 0; i < 128; i++) {
    *reinterpret_cast<int*>(&s.mem[pc]) = 0x13;
    pc += 4;
  }
}
