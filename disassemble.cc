#include "helper.hh"
#include "interpret.hh"
#include "disassemble.hh"

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <array>
#include <map>
#include <string>

#include "disassemble.hh"

static const std::array<std::string,32> regNames = {
  "zero","ra", "sp", "gp","tp", "t0", "t1", "t2",
    "s0", "s1", "a0", "a1","a2", "a3", "a4", "a5",
    "a6", "a7", "s2", "s3","s4", "s5", "s6", "s7",
    "s8", "s9", "s10", "s11","t3", "t4", "t5", "t6"
    };

static const std::array<std::string,16> condNames = {
  "f", "un", "eq", "ueq", "olt", "ult", "ole", "ule",
  "sf", "ngle", "seq", "ngl", "lt", "nge", "le", "ngt"
};

const std::string &getCondName(uint32_t c) {
  return condNames[c&15];
}

const std::string &getGPRName(uint32_t r) {
  return regNames[r&31];
}



void disassemble(std::ostream &out, uint32_t inst, uint32_t addr) {
  out << getAsmString(inst,addr);
}
void initCapstone() {}

void stopCapstone() {
}

std::string getAsmString(uint32_t inst, uint32_t addr) {
  return "huh";
}



