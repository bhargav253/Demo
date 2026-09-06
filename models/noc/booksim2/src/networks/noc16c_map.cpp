#include "booksim.hpp"

#include <algorithm>
#include <cassert>
#include <map>
#include <queue>
#include <set>
#include <sstream>
#include <utility>

#include "noc16c_map.hpp"

using namespace std;

namespace {
void AddDirected(vector<Noc16CLink> &links, int sr, int sp, int sl,
                 int dr, int dp, int dl, string const &name) {
  ostringstream unique;
  unique << name << "_r" << sr << "p" << sp << "l" << sl
         << "_r" << dr << "p" << dp << "l" << dl;
  Noc16CLink link = {sr, sp, sl, dr, dp, dl, unique.str()};
  links.push_back(link);
}
void AddBidirectional(vector<Noc16CLink> &links, int ar, int ap, int al,
                      int br, int bp, int bl, string const &name) {
  AddDirected(links, ar, ap, al, br, bp, bl, name + "_a_to_b");
  AddDirected(links, br, bp, bl, ar, ap, al, name + "_b_to_a");
}
string IndexName(char const *prefix, int a, int b = -1) {
  ostringstream out; out << prefix;
  if(a < 10) out << '0';
  out << a;
  if(b >= 0) { out << '_'; if(b < 10) out << '0'; out << b; }
  return out.str();
}
void AddEndpoint(vector<Noc16CEndpoint> &result, int node,
                 Noc16CEndpoint::Kind kind, int instance, int lane,
                 int router, int port, int router_lane, string const &name) {
  Noc16CEndpoint ep = {node, kind, instance, lane, router, port, router_lane, name};
  result.push_back(ep);
}

struct Edge { int next, out_port, in_port; };
vector<vector<Edge> > const &CoreGraph() {
  static vector<vector<Edge> > graph;
  if(!graph.empty()) return graph;
  graph.resize(Noc16CMap::kL3Base);
  vector<Noc16CLink> const links = Noc16CMap::InternalLinks();
  for(size_t i = 0; i < links.size(); ++i) {
    Noc16CLink const &l = links[i];
    if(l.source_lane || l.sink_lane || l.source_router >= Noc16CMap::kL3Base ||
       l.sink_router >= Noc16CMap::kL3Base) continue;
    Edge e = {l.sink_router, l.source_port, l.sink_port};
    graph[l.source_router].push_back(e);
  }
  return graph;
}
pair<int,int> Coord(int router) {
  if(router < Noc16CMap::kL2Base) {
    int const i = router - Noc16CMap::kL1Base;
    return make_pair(2 * (i % 4) + 1, 2 * (i / 4) + 1);
  }
  int const i = router - Noc16CMap::kL2Base;
  return make_pair(2 * (i % 4), 2 * (i / 4));
}
int TargetRouter(Noc16CEndpoint const &ep) {
  if(ep.kind == Noc16CEndpoint::LLCH) return ep.router;
  if(ep.kind == Noc16CEndpoint::CDMA) return Noc16CMap::L2(ep.instance);
  return Noc16CMap::L2(ep.instance / 4);
}
} // namespace

int Noc16CMap::RouterPorts(int router) {
  if(router < kL2Base) return 8;
  if(router < kL3Base) return 9;
  return 5;
}
int Noc16CMap::RouterLanes(int router) { return router < kL3Base ? 4 : 1; }

vector<Noc16CLink> Noc16CMap::InternalLinks() {
  vector<Noc16CLink> links;
  bool connected[32][9] = {{false}};
  // L1 cardinal mesh: p1=N, p3=E, p5=S, p7=W.
  for(int row=0;row<4;++row) for(int col=0;col<4;++col) {
    int const here=row*4+col;
    if(col<3) for(int lane=0;lane<4;++lane) {
      AddBidirectional(links,L1(here),3,lane,L1(here+1),7,lane,"l1_ew");
      connected[here][3]=connected[here+1][7]=true;
    }
    if(row<3) for(int lane=0;lane<4;++lane) {
      AddBidirectional(links,L1(here),5,lane,L1(here+4),1,lane,"l1_ns");
      connected[here][5]=connected[here+4][1]=true;
    }
  }
  // L2[r,c] connects existing L1s at its NW, NE, SE, SW corners.
  int const dr[4]={-1,-1,0,0}, dc[4]={-1,0,0,-1};
  int const l1port[4]={4,6,0,2};
  for(int row=0;row<4;++row) for(int col=0;col<4;++col) {
    int const cluster=row*4+col;
    for(int corner=0;corner<4;++corner) {
      int const lr=row+dr[corner],lc=col+dc[corner];
      if(lr<0||lr>=4||lc<0||lc>=4) continue;
      int const l1=lr*4+lc;
      connected[l1][l1port[corner]]=true;
      connected[16+cluster][corner]=true;
      for(int lane=0;lane<4;++lane)
        AddBidirectional(links,L1(l1),l1port[corner],lane,
                         L2(cluster),corner,lane,"l1_l2");
    }
  }
  // Inert loops fill physically absent even L1 ports and clipped L2 corners.
  for(int l1=0;l1<16;++l1) for(int port=0;port<8;++port) {
    if(connected[l1][port] || (port&1)) continue;
    for(int lane=0;lane<4;++lane)
      AddDirected(links,L1(l1),port,lane,L1(l1),port,lane,"l1_absent_inert");
  }
  for(int cluster=0;cluster<16;++cluster) for(int port=0;port<4;++port) {
    if(connected[16+cluster][port]) continue;
    for(int lane=0;lane<4;++lane)
      AddDirected(links,L2(cluster),port,lane,L2(cluster),port,lane,"l2_absent_inert");
  }
  // L2 tile ports p4..p7 connect through 4:1 shims to L3 p0.
  int tile_port[4] = {4, 5, 6, 7};
  for(int cluster = 0; cluster < 16; ++cluster) for(int tile = 0; tile < 4; ++tile) {
    int const shim = Shim(cluster, tile);
    for(int lane = 0; lane < 4; ++lane)
      AddBidirectional(links, L2(cluster), tile_port[tile], lane,
                       shim, 1 + lane, 0, "l2_shim");
    AddBidirectional(links, shim, 0, 0, L3(cluster, tile), 0, 0, "shim_l3");
  }
  return links;
}

vector<Noc16CEndpoint> Noc16CMap::Endpoints() {
  vector<Noc16CEndpoint> result;
  for(int cluster = 0; cluster < 16; ++cluster) {
    for(int tile = 0; tile < 4; ++tile) {
      int const l3 = L3(cluster, tile), instance = cluster * 4 + tile;
      AddEndpoint(result, PE(cluster,tile), Noc16CEndpoint::PE, instance, 0,
                  l3, 1, 0, IndexName("PE_",cluster,tile));
      AddEndpoint(result, TDMA(cluster,tile), Noc16CEndpoint::TDMA, instance, 0,
                  l3, 2, 0, IndexName("TDMA_",cluster,tile));
      AddEndpoint(result, TSRAM(cluster,tile), Noc16CEndpoint::TSRAM, instance, 0,
                  l3, 3, 0, IndexName("TSRAM_",cluster,tile));
      AddEndpoint(result, CSRAM(cluster,tile), Noc16CEndpoint::CSRAM, instance, 0,
                  l3, 4, 0, IndexName("CSRAM_",cluster,tile));
    }
    for(int lane = 0; lane < 4; ++lane)
      AddEndpoint(result, CDMA(cluster,lane), Noc16CEndpoint::CDMA, cluster, lane,
                  L2(cluster), 8, lane, IndexName("CDMA_",cluster));
  }
  int routers[16] = {0,1,2,3,3,7,11,15,15,14,13,12,12,8,4,0};
  int ports[16] = {1,1,1,1,3,3,3,3,5,5,5,5,7,7,7,7};
  for(int llch = 0; llch < 16; ++llch) for(int lane = 0; lane < 4; ++lane)
    AddEndpoint(result, LLCH(llch,lane), Noc16CEndpoint::LLCH, llch, lane,
                L1(routers[llch]), ports[llch], lane, IndexName("LLCH_",llch));
  assert(result.size() == kNodeCount);
  return result;
}

Noc16CEndpoint Noc16CMap::Endpoint(int node) {
  static vector<Noc16CEndpoint> const eps = Endpoints();
  for(size_t i=0;i<eps.size();++i) if(eps[i].node==node) return eps[i];
  assert(false && "missing noc16c endpoint"); return eps[0];
}

int Noc16CMap::RoutePort(int router, int destination_node) {
  assert(router >= 0 && router < kShimBase);
  Noc16CEndpoint const ep = Endpoint(destination_node);
  if(router >= kL3Base) return ep.router == router ? ep.port : 0;
  int const target = TargetRouter(ep);
  if(router == target) {
    if(ep.kind == Noc16CEndpoint::LLCH) return ep.port;
    if(ep.kind == Noc16CEndpoint::CDMA) return 8;
    int tile_port[4] = {4,5,6,7};
    return tile_port[(ep.instance % 4)];
  }

  // L2 routers are injection/ejection points, not transit routers.  Select one
  // adjacent L1 when leaving a source L2.  Once in L1, remain on the cardinal
  // L1 mesh and use deterministic X-then-Y routing.  Non-LLCH traffic enters
  // only its final L2, through that L2's southeast (same-index) L1 gateway.
  int const target_l1 = (ep.kind == Noc16CEndpoint::LLCH) ?
      ep.router : L1(target - kL2Base);
  vector<vector<Edge> > const &graph = CoreGraph();

  if(router < kL2Base) {
    if(router == target_l1) {
      if(ep.kind == Noc16CEndpoint::LLCH) return ep.port;
      for(size_t i = 0; i < graph[router].size(); ++i)
        if(graph[router][i].next == target) return graph[router][i].out_port;
      assert(false && "destination L2 is not attached to its L1 gateway");
    }
    pair<int,int> const here = Coord(router);
    pair<int,int> const there = Coord(target_l1);
    if(here.first < there.first) return 3;  // east
    if(here.first > there.first) return 7;  // west
    if(here.second < there.second) return 5; // south
    if(here.second > there.second) return 1; // north
    assert(false && "unreachable L1 routing state");
  }

  pair<int,int> const there = Coord(target_l1);
  Edge best = {-1,-1,-1};
  int best_distance = 999;
  for(size_t i = 0; i < graph[router].size(); ++i) {
    Edge const &e = graph[router][i];
    if(e.next >= kL2Base) continue;
    pair<int,int> const next = Coord(e.next);
    int const distance = abs(there.first - next.first) +
                         abs(there.second - next.second);
    if((distance < best_distance) ||
       ((distance == best_distance) && (e.out_port < best.out_port))) {
      best = e;
      best_distance = distance;
    }
  }
  assert(best.next >= 0);
  return best.out_port;
}

vector<vector<int> > Noc16CMap::GrantWeights(int wanted_router) {
  assert(wanted_router >= 0 && wanted_router < kL3Base);
  int const ports=RouterPorts(wanted_router);
  vector<vector<int> > weights(ports,vector<int>(ports,1));
  vector<vector<int> > demand(ports,vector<int>(ports,0));
  vector<Noc16CLink> const links=InternalLinks();
  int tile_port[4]={4,5,6,7};
  for(int source=0;source<16;++source) for(int tile=0;tile<4;++tile)
    for(int llch=0;llch<16;++llch) {
    int router=L2(source), input=tile_port[tile];
    int const destination=LLCH(llch,0);
    while(true) {
      int const output=RoutePort(router,destination);
      if(router==wanted_router) ++demand[input][output];
      Noc16CEndpoint const endpoint=Endpoint(destination);
      if(router==endpoint.router) break;
      bool found=false;
      for(size_t i=0;i<links.size();++i) {
        Noc16CLink const &l=links[i];
        if(l.source_router==router && l.source_port==output && l.source_lane==0 &&
           l.sink_router<kL3Base) {
          router=l.sink_router; input=l.sink_port; found=true; break;
        }
      }
      assert(found);
    }
  }
  for(int o=0;o<ports;++o) {
    int divisor=0;
    for(int i=0;i<ports;++i) if(demand[i][o]>0) {
      int a=divisor,b=demand[i][o];
      while(b){int const t=a%b;a=b;b=t;}
      divisor=a;
    }
    if(divisor<1) divisor=1;
    for(int i=0;i<ports;++i)
      if(demand[i][o]>0) weights[i][o]=demand[i][o]/divisor;
  }
  return weights;
}

string Noc16CMap::RouterName(int router) {
  if(router<kL2Base) return IndexName("L1_",router-kL1Base);
  if(router<kL3Base) return IndexName("L2_",router-kL2Base);
  if(router<kShimBase) {int i=router-kL3Base;return IndexName("L3_",i/4,i%4);}
  if(router<kRouterCount){int i=router-kShimBase;return IndexName("SHIM_",i/4,i%4);}
  assert(false); return "";
}

void Noc16CMap::Validate() {
  vector<Noc16CEndpoint> const eps=Endpoints();
  vector<Noc16CLink> const links=InternalLinks();
  set<int> nodes; set<pair<int,int> > inports,outports;
  for(size_t i=0;i<eps.size();++i) {
    assert(nodes.insert(eps[i].node).second);
    int const flat=eps[i].port*RouterLanes(eps[i].router)+eps[i].router_lane;
    assert(inports.insert(make_pair(eps[i].router,flat)).second);
    assert(outports.insert(make_pair(eps[i].router,flat)).second);
  }
  assert(nodes.size()==kNodeCount);
  set<pair<pair<int,int>,pair<int,int> > > directed;
  for(size_t i=0;i<links.size();++i) {
    Noc16CLink const &l=links[i];
    int const sf=l.source_port*RouterLanes(l.source_router)+l.source_lane;
    int const df=l.sink_port*RouterLanes(l.sink_router)+l.sink_lane;
    assert(directed.insert(make_pair(make_pair(l.source_router,sf),
                                    make_pair(l.sink_router,df))).second);
  }
  for(set<pair<pair<int,int>,pair<int,int> > >::const_iterator i=directed.begin();i!=directed.end();++i)
    assert(directed.count(make_pair(i->second,i->first))==1);
  for(int router=0;router<kShimBase;++router) for(int node=0;node<kNodeCount;++node)
    (void)RoutePort(router,node);
}
