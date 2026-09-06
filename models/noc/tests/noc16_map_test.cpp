#include <iostream>
#include <vector>

#include "networks/noc16_map.hpp"

static int NextRouter(int router, int output) {
  std::vector<Noc16Link> const links = Noc16Map::InternalLinks();
  for(size_t i = 0; i < links.size(); ++i)
    if(links[i].source_router == router && links[i].source_port == output &&
       links[i].source_lane == 0 && links[i].sink_router < Noc16Map::kL3Base)
      return links[i].sink_router;
  return -1;
}

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
  for(int source = 0; source < 16; ++source)
    for(int llch = 0; llch < 16; ++llch) {
      int router = Noc16Map::L2(source);
      int const destination = Noc16Map::LLCH(llch, 0);
      bool entered_l1 = false;
      for(int hop = 0; hop < 12; ++hop) {
        Noc16Endpoint const ep = Noc16Map::Endpoint(destination);
        if(router == ep.router) break;
        int const next = NextRouter(router,
            Noc16Map::RoutePort(router, destination));
        if(next < 0) return 1;
        if(next < Noc16Map::kL2Base) entered_l1 = true;
        if(entered_l1 && next >= Noc16Map::kL2Base) return 1;
        router = next;
        if(hop == 11) return 1;
      }
      if(router != Noc16Map::Endpoint(destination).router) return 1;
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
