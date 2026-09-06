#include <iostream>
#include <vector>
#include "networks/noc16c_map.hpp"
#define CHECK(c) do { if(!(c)) { std::cerr<<"noc16c check failed at line "<<__LINE__<<"\n"; return 1; } } while(0)
static bool Link(int sr,int sp,int dr,int dp) {
  std::vector<Noc16CLink> const links=Noc16CMap::InternalLinks();
  for(size_t i=0;i<links.size();++i) if(links[i].source_router==sr && links[i].source_port==sp &&
      links[i].source_lane==0 && links[i].sink_router==dr && links[i].sink_port==dp) return true;
  return false;
}
static int NextRouter(int router,int output) {
  std::vector<Noc16CLink> const links=Noc16CMap::InternalLinks();
  for(size_t i=0;i<links.size();++i) if(links[i].source_router==router &&
      links[i].source_port==output && links[i].source_lane==0 &&
      links[i].sink_router<Noc16CMap::kL3Base) return links[i].sink_router;
  return -1;
}
int main() {
  Noc16CMap::Validate();
  CHECK(Noc16CMap::RouterName(0)=="L1_00" && Noc16CMap::RouterName(16)=="L2_00");
  CHECK(Noc16CMap::RouterName(32)=="L3_00_00" && Noc16CMap::RouterName(96)=="SHIM_00_00");
  CHECK(Noc16CMap::Endpoints().size()==384 && Noc16CMap::RouterPorts(0)==8 && Noc16CMap::RouterPorts(16)==9);
  CHECK(Link(Noc16CMap::L1(0),0,Noc16CMap::L2(0),2));
  CHECK(Link(Noc16CMap::L1(0),2,Noc16CMap::L2(1),3));
  CHECK(Link(Noc16CMap::L1(0),4,Noc16CMap::L2(5),0));
  CHECK(Link(Noc16CMap::L1(0),6,Noc16CMap::L2(4),1));
  CHECK(Link(Noc16CMap::L2(5),0,Noc16CMap::L1(0),4));
  CHECK(Link(Noc16CMap::L2(5),1,Noc16CMap::L1(1),6));
  CHECK(Link(Noc16CMap::L2(5),2,Noc16CMap::L1(5),0));
  CHECK(Link(Noc16CMap::L2(5),3,Noc16CMap::L1(4),2));
  for(int llch=0;llch<16;++llch) for(int lane=0;lane<4;++lane) {
    Noc16CEndpoint const ep=Noc16CMap::Endpoint(Noc16CMap::LLCH(llch,lane));
    CHECK(ep.instance==llch && ep.lane==lane && ep.router_lane==lane);
  }
  CHECK(Noc16CMap::RoutePort(Noc16CMap::L1(5),Noc16CMap::LLCH(2,0))==3);
  CHECK(Noc16CMap::RoutePort(Noc16CMap::L1(4),Noc16CMap::LLCH(1,0))==3);
  for(int source=0;source<16;++source) for(int llch=0;llch<16;++llch) {
    int router=Noc16CMap::L2(source);
    int const destination=Noc16CMap::LLCH(llch,0);
    bool entered_l1=false;
    for(int hop=0;hop<16;++hop) {
      Noc16CEndpoint const ep=Noc16CMap::Endpoint(destination);
      if(router==ep.router) break;
      int const output=Noc16CMap::RoutePort(router,destination);
      int const next=NextRouter(router,output);
      CHECK(next>=0);
      if(next<Noc16CMap::kL2Base) entered_l1=true;
      if(entered_l1) CHECK(next<Noc16CMap::kL2Base);
      router=next;
      CHECK(hop<15);
    }
    CHECK(router==Noc16CMap::Endpoint(destination).router);
  }
  for(int r=0;r<Noc16CMap::kL3Base;++r) {
    std::vector<std::vector<int> > const w=Noc16CMap::GrantWeights(r);
    CHECK((int)w.size()==Noc16CMap::RouterPorts(r));
    for(size_t i=0;i<w.size();++i) for(size_t o=0;o<w[i].size();++o) CHECK(w[i][o]>=1);
  }
  std::cout<<"noc16c reciprocal graph, hierarchical L1-only transit routes, and generated weights passed\n";
}
