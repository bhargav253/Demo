// SPDX-License-Identifier: Apache-2.0
// Bus-level RAM harness. No hierarchical register access or simulator backdoors.
#include "Vriscv_core.h"
#include "verilated.h"
#include "verilated_fst_c.h"
#if VM_COVERAGE
#include "verilated_cov.h"
#endif
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr uint32_t RamBase = 0x80000000, RamSize = 0x100000;
constexpr uint32_t ExitAddr = 0x10000000, ConsoleAddr = 0x10000004;
std::vector<uint8_t> ram(RamSize);
bool mapped(uint32_t addr, uint64_t size) {
  return addr >= RamBase && uint64_t(addr - RamBase) + size <= RamSize;
}
uint32_t word(uint32_t addr) {
  if (!mapped(addr, 4)) throw std::runtime_error("RAM read out of bounds");
  size_t p = addr - RamBase;
  return uint32_t(ram[p]) | uint32_t(ram[p+1]) << 8 |
         uint32_t(ram[p+2]) << 16 | uint32_t(ram[p+3]) << 24;
}
uint32_t load_elf(const std::string &path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) throw std::runtime_error("Cannot open ELF: " + path);
  std::vector<uint8_t> b((std::istreambuf_iterator<char>(in)), {});
  auto read = [&](uint64_t off, unsigned size) {
    if (off + size > b.size()) throw std::runtime_error("Truncated ELF");
    uint32_t v = 0;
    for (unsigned i = 0; i < size; ++i) v |= uint32_t(b[off+i]) << (8*i);
    return v;
  };
  if (b.size() < 52 || read(0,4) != 0x464c457f || b[4] != 1 || b[5] != 1 ||
      b[6] != 1 || read(16,2) != 2 || read(18,2) != 243 || read(20,4) != 1)
    throw std::runtime_error("Expected executable little-endian ELF32 RISC-V");
  // ACT alignment macros set EF_RISCV_RVC even for RV32I/M tests. This flag
  // permits linker relaxation; it does not assert that executed code uses C.
  // The RTL still has no compressed decoder; manifest scope owns the ISA claim.
  uint32_t entry = read(24,4), phoff = read(28,4), entsz = read(42,2);
  if (entsz < 32) throw std::runtime_error("Invalid ELF program header size");
  bool executable_entry = false;
  for (unsigned i = 0; i < read(44,2); ++i) {
    uint64_t h = uint64_t(phoff) + uint64_t(i)*entsz;
    if (read(h,4) != 1) continue;
    uint32_t off = read(h+4,4), va = read(h+8,4), pa = read(h+12,4);
    uint32_t fs = read(h+16,4), ms = read(h+20,4), flags = read(h+24,4);
    if (va != pa || fs > ms || uint64_t(off)+fs > b.size() || !mapped(pa,ms))
      throw std::runtime_error("ELF segment violates flat RAM platform");
    for (uint64_t j = 0; j < ms; ++j) ram[pa-RamBase+j] = j < fs ? b[off+j] : 0;
    executable_entry |= (flags & 1) && entry >= pa && uint64_t(entry) < uint64_t(pa)+ms;
  }
  if (!mapped(entry,4) || (entry & 3) || !executable_entry)
    throw std::runtime_error("Invalid ELF entry point");
  return entry;
}
}

int main(int argc, char **argv) {
  try {
    VerilatedContext context;
    context.commandArgs(argc, argv);
    std::string elf, test = "smoke", wave, coverage;
    uint64_t cycles = 100000;
    unsigned seed = 1, delay = 0;
    for (int i = 1; i < argc; ++i) {
      std::string a(argv[i]);
      auto value = [&](const std::string &prefix) { return a.substr(prefix.size()); };
      if (a.rfind("+ELF=",0)==0) elf=value("+ELF=");
      else if (a.rfind("+TEST=",0)==0) test=value("+TEST=");
      else if (a.rfind("+CYCLES=",0)==0) cycles=std::stoull(value("+CYCLES="));
      else if (a.rfind("+SEED=",0)==0) seed=std::stoul(value("+SEED="));
      else if (a.rfind("+WAIT=",0)==0) delay=std::stoul(value("+WAIT="));
      else if (a.rfind("+WAVE=",0)==0) wave=value("+WAVE=");
      // Compatibility with the legacy generic simulation runner.
      else if (a.rfind("+AXON_WAVE_FILE=",0)==0) wave=value("+AXON_WAVE_FILE=");
      else if (a.rfind("+COVERAGE=",0)==0) coverage=value("+COVERAGE=");
      else throw std::runtime_error("Unknown argument: " + a);
    }
    if (!cycles || delay > 1000) throw std::runtime_error("Invalid cycle/wait limit");
#if !VM_COVERAGE
    if (!coverage.empty()) throw std::runtime_error("Coverage requires the coverage build target");
#endif
    uint32_t entry = RamBase;
    if (!elf.empty()) entry = load_elf(elf);
    else {
      if (test != "smoke") throw std::runtime_error("ELF required for this test");
      // addi x1,0,1; lui x2,0x10000; sw x1,0(x2); jal x0,0.
      const uint32_t code[] = {0x00100093,0x10000137,0x00112023,0x0000006f};
      for (unsigned i=0;i<4;++i)
        for (unsigned j=0;j<4;++j) ram[4*i+j]=(code[i]>>(8*j))&255;
    }
    context.traceEverOn(!wave.empty());
    Vriscv_core dut(&context);
    std::unique_ptr<VerilatedFstC> trace;
    if (!wave.empty()) {
      trace=std::make_unique<VerilatedFstC>(); dut.trace(trace.get(), 8); trace->open(wave.c_str());
    }
    auto eval = [&] { dut.eval(); if(trace) trace->dump(context.time()); context.timeInc(1); };
    dut.clk_i=0; dut.rst_ni=0; dut.reset_vector_i=entry; dut.cpu_id_i=0; dut.intr_i=0;
    dut.mem_i_accept_i=0; dut.mem_i_valid_i=0; dut.mem_i_error_i=0;
    dut.mem_i_inst_i=0; dut.mem_i_inst_pc_i=0;
    dut.mem_d_accept_i=0; dut.mem_d_ack_i=0; dut.mem_d_error_i=0;
    dut.mem_d_data_rd_i=0; dut.mem_d_resp_tag_i=0;
    for (unsigned i=0;i<5;++i) { dut.clk_i=0; eval(); dut.clk_i=1; eval(); }
#if VM_COVERAGE
    context.coveragep()->zero();  // Exclude reset initialization from measured activity.
#endif
    auto write_coverage = [&] {
#if VM_COVERAGE
      if (!coverage.empty()) context.coveragep()->write(coverage.c_str());
#endif
    };
    struct Reply { bool valid=false, error=false; uint32_t data=0, pc=0, tag=0; } ir, dr;
    std::cout << "TEST=" << test << " SEED=" << seed << " WAIT=" << delay << " ELF=" << elf << '\n';
    for (uint64_t cycle=0;cycle<cycles;++cycle) {
      dut.clk_i=0; dut.rst_ni=1;
      // Independent deterministic instruction/data backpressure; one-cycle responses.
      dut.mem_i_accept_i=((cycle+seed)%(delay+1)==0);
      dut.mem_d_accept_i=((cycle+seed+1)%(delay+1)==0);
      dut.mem_i_valid_i=ir.valid; dut.mem_i_error_i=ir.error;
      dut.mem_i_inst_i=ir.data; dut.mem_i_inst_pc_i=ir.pc;
      dut.mem_d_ack_i=dr.valid; dut.mem_d_error_i=dr.error;
      dut.mem_d_data_rd_i=dr.data; dut.mem_d_resp_tag_i=dr.tag;
      eval(); ir={}; dr={};
      if (dut.mem_i_rd_o && dut.mem_i_accept_i) {
        ir.valid=true; ir.pc=dut.mem_i_pc_o;
        ir.error=!mapped(ir.pc,4) || (ir.pc&3);
        ir.data=ir.error ? 0 : word(ir.pc);
      }
      bool done=false; uint32_t status=0;
      if (dut.mem_d_accept_i && (dut.mem_d_rd_o || dut.mem_d_wr_o ||
          dut.mem_d_flush_o || dut.mem_d_invalidate_o)) {
        uint32_t addr=dut.mem_d_addr_o;
        dr.valid=true; dr.tag=dut.mem_d_req_tag_o;
        if (dut.mem_d_wr_o && addr==ExitAddr) {
          if (dut.mem_d_wr_o!=15) throw std::runtime_error("Exit requires a word store");
          done=true; status=dut.mem_d_data_wr_o;
        } else if (dut.mem_d_wr_o && addr==ConsoleAddr) {
          if (dut.mem_d_wr_o&1) std::cout << char(dut.mem_d_data_wr_o&255) << std::flush;
        } else if (dut.mem_d_rd_o || dut.mem_d_wr_o) {
          dr.error=!mapped(addr,4) || (addr&3);
          if (!dr.error) {
            dr.data=word(addr);
            for (unsigned b=0;b<4;++b) if ((dut.mem_d_wr_o>>b)&1)
              ram[addr-RamBase+b]=(dut.mem_d_data_wr_o>>(8*b))&255;
          }
        }
      }
      dut.clk_i=1; eval();
      if (done) {
        dut.final(); if(trace) trace->close(); write_coverage();
        std::cout << (status==1 ? "PASS" : "FAIL") << " status=" << status << " cycles=" << cycle+1 << '\n';
        return status==1 ? 0 : 1;
      }
      if (context.gotFinish()) throw std::runtime_error("Unexpected RTL termination");
    }
    dut.final(); if(trace) trace->close(); write_coverage();
    throw std::runtime_error("TIMEOUT without platform pass/fail store");
  } catch (const std::exception &e) {
    std::cerr << "FAIL: " << e.what() << '\n'; return 1;
  }
}
