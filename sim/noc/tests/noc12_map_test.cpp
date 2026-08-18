#include <iostream>
#include <vector>
#include "networks/noc12_map.hpp"

#define CHECK(condition) do { if(!(condition)) { \
  std::cerr << "noc12 map check failed at line " << __LINE__ << "\n"; return 1; \
} } while(0)

int main() {
  Noc12Map::Validate();
  CHECK(Noc12Map::RouterName(0)=="L1_00" && Noc12Map::RouterName(9)=="L2_00" &&
        Noc12Map::RouterName(25)=="L3_00_00" && Noc12Map::RouterName(89)=="SHIM_00_00");
  CHECK(Noc12Map::Endpoints().size()==368 && Noc12Map::RouterPorts(0)==8 &&
        Noc12Map::RouterPorts(9)==9 && Noc12Map::RouterPorts(25)==5);
  for(int llch=0;llch<12;++llch) for(int lane=0;lane<4;++lane) {
    Noc12Endpoint const ep=Noc12Map::Endpoint(Noc12Map::LLCH(llch,lane));
    CHECK(ep.instance==llch && ep.lane==lane && ep.router_lane==lane);
  }
  // Representative deterministic routes through L2 and the 3x3 L1 mesh.
  CHECK(Noc12Map::RoutePort(Noc12Map::L2(0),Noc12Map::LLCH(0,0))==4);
  CHECK(Noc12Map::RoutePort(Noc12Map::L1(0),Noc12Map::LLCH(0,0))==2);
  CHECK(Noc12Map::RoutePort(Noc12Map::L1(8),Noc12Map::LLCH(0,0))==0);
  CHECK(Noc12Map::RoutePort(Noc12Map::L2(15),Noc12Map::LLCH(6,0))==0);

  std::vector<std::vector<int> > const l1=Noc12Map::GrantWeights(Noc12Map::L1(0));
  std::vector<std::vector<int> > const l2=Noc12Map::GrantWeights(Noc12Map::L2(5));
  CHECK(l1[1][4]==7 && l1[7][4]==3 && l1[4][6]==2 && l1[6][0]==8);
  CHECK(l2[1][0]==1 && l2[1][2]==1 && l2[1][4]==1 && l2[1][7]==1 && l2[7][2]==4);
  for(size_t i=0;i<l1.size();++i)for(size_t o=0;o<l1.size();++o)CHECK(l1[i][o]>=1);
  for(size_t i=0;i<l2.size();++i)for(size_t o=0;o<l2.size();++o)CHECK(l2[i][o]>=1);
  std::cout<<"noc12 graph, routing, and positive generated weights passed\n";
  return 0;
}
