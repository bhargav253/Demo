#include <iostream>
#include <vector>
#include "networks/noc12_map.hpp"

#define CHECK(condition) do { if(!(condition)) { \
  std::cerr << "noc12 map check failed at line " << __LINE__ << "\n"; return 1; \
} } while(0)

static int NextRouter(int router,int output) {
  std::vector<Noc12Link> const links=Noc12Map::InternalLinks();
  for(size_t i=0;i<links.size();++i) if(links[i].source_router==router &&
      links[i].source_port==output && links[i].source_lane==0 &&
      links[i].sink_router<Noc12Map::kL3Base) return links[i].sink_router;
  return -1;
}

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

  for(int source=0;source<16;++source) for(int llch=0;llch<12;++llch) {
    int router=Noc12Map::L2(source);
    int const destination=Noc12Map::LLCH(llch,0);
    bool entered_l1=false;
    for(int hop=0;hop<12;++hop) {
      Noc12Endpoint const ep=Noc12Map::Endpoint(destination);
      if(router==ep.router) break;
      int const next=NextRouter(router,Noc12Map::RoutePort(router,destination));
      CHECK(next>=0);
      if(next<Noc12Map::kL2Base) entered_l1=true;
      if(entered_l1) CHECK(next<Noc12Map::kL2Base);
      router=next;
      CHECK(hop<11);
    }
    CHECK(router==Noc12Map::Endpoint(destination).router);
  }

  std::vector<std::vector<int> > const l1=Noc12Map::GrantWeights(Noc12Map::L1(0));
  std::vector<std::vector<int> > const l2=Noc12Map::GrantWeights(Noc12Map::L2(5));
  CHECK(l1[1][4]==7 && l1[7][4]==3 && l1[4][6]==2 && l1[6][0]==8);
  for(size_t i=0;i<l2.size();++i)for(size_t o=0;o<l2.size();++o)CHECK(l2[i][o]==1);
  for(size_t i=0;i<l1.size();++i)for(size_t o=0;o<l1.size();++o)CHECK(l1[i][o]>=1);
  for(size_t i=0;i<l2.size();++i)for(size_t o=0;o<l2.size();++o)CHECK(l2[i][o]>=1);
  std::cout<<"noc12 graph, hierarchical L1-only transit routing, and positive generated weights passed\n";
  return 0;
}
