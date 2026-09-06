// SPDX-License-Identifier: Apache-2.0

#include <cstring>
#include <memory>

#include "Vnoc_islip_arbiter_tb.h"
#include "verilated.h"
#include "verilated_cov.h"

int main(int argc, char** argv) {
  constexpr const char* prefix = "+AXON_COVERAGE_FILE=";
  const char* coverage_file = nullptr;
  for (int index = 1; index < argc; ++index) {
    if (std::strncmp(argv[index], prefix, std::strlen(prefix)) == 0) {
      coverage_file = argv[index] + std::strlen(prefix);
    }
  }
  if (coverage_file == nullptr || coverage_file[0] == '\0') {
    VL_PRINTF("%%Error: +AXON_COVERAGE_FILE=<path> is required\n");
    return 2;
  }

  const std::unique_ptr<VerilatedContext> context{new VerilatedContext};
  context->commandArgs(argc, argv);
  const std::unique_ptr<Vnoc_islip_arbiter_tb> top{
      new Vnoc_islip_arbiter_tb{context.get()}};

  while (!context->gotFinish()) {
    top->eval();
    if (!top->eventsPending()) {
      break;
    }
    context->time(top->nextTimeSlot());
  }
  top->final();
  context->coveragep()->write(coverage_file);
  return context->gotFinish() ? 0 : 1;
}
