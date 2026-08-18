#include <iostream>
#include <vector>

#include "networks/noc16_map.hpp"

int main() {
  Noc16Map::Validate();
  if(Noc16Map::RouterName(Noc16Map::L1(0)) != "L1_00") return 1;
  if(Noc16Map::RouterName(Noc16Map::L2(15)) != "L2_15") return 1;
  if(Noc16Map::RouterName(Noc16Map::L3(15, 3)) != "L3_15_03") return 1;
  if(Noc16Map::RouterName(Noc16Map::Shim(0, 0)) != "SHIM_00_00") return 1;
  int const far_llch = Noc16Map::LLCH(8, 0);
  if(Noc16Map::RoutePort(Noc16Map::L3(0, 0), far_llch) != 0) return 1;
  if(Noc16Map::RoutePort(Noc16Map::L2(0), far_llch) != 0) return 1;
  if(Noc16Map::RoutePort(Noc16Map::L1(0), far_llch) != 2) return 1;
  if(Noc16Map::RoutePort(Noc16Map::L1(3), far_llch) != 3) return 1;
  if(Noc16Map::RoutePort(Noc16Map::L1(15), far_llch) != 3) return 1;
  int const pe_15_3 = Noc16Map::PE(15, 3);
  if(Noc16Map::RoutePort(Noc16Map::L1(0), pe_15_3) != 2) return 1;
  if(Noc16Map::RoutePort(Noc16Map::L1(15), pe_15_3) != 0) return 1;
  if(Noc16Map::RoutePort(Noc16Map::L2(15), pe_15_3) != 4) return 1;
  if(Noc16Map::RoutePort(Noc16Map::L3(15, 3), pe_15_3) != 1) return 1;
  for(int llch = 0; llch < 16; ++llch)
    for(int lane = 0; lane < 4; ++lane) {
      Noc16Endpoint const ep = Noc16Map::Endpoint(Noc16Map::LLCH(llch, lane));
      if(ep.instance != llch || ep.lane != lane || ep.router_lane != lane) return 1;
    }
  std::vector<std::vector<int> > const w00 = Noc16Map::L1GrantWeights(0);
  // L1_00: local p0 contributes 1:10:4:1; east p2 contributes
  // 3:0:12:3; south p3 contributes 12:0:0:12. Missing workload flows
  // retain the safe default weight one.
  int expected[5][5] = {
    { 1, 1, 10, 4, 1 },
    { 1, 1,  1, 1, 1 },
    { 1, 3,  1,12, 3 },
    { 1,12,  1, 1,12 },
    { 1, 1,  1, 1, 1 }
  };
  for(int input = 0; input < 5; ++input)
    for(int output = 0; output < 5; ++output)
      if(w00[input][output] != expected[input][output]) return 1;
  std::cout << "noc16 ID and lane-level graph validation passed\n";
  return 0;
}
