#include "booksim.hpp"

#include <cassert>
#include <map>
#include <set>
#include <sstream>
#include <utility>

#include "noc16_map.hpp"

using namespace std;

namespace {

void AddDirected(vector<Noc16Link> &links, int sr, int sp, int sl,
                 int dr, int dp, int dl, string const &name) {
  ostringstream unique;
  unique << name << "_r" << sr << "p" << sp << "l" << sl
         << "_r" << dr << "p" << dp << "l" << dl;
  Noc16Link link = { sr, sp, sl, dr, dp, dl, unique.str() };
  links.push_back(link);
}

void AddBidirectional(vector<Noc16Link> &links, int ar, int ap, int al,
                      int br, int bp, int bl, string const &name) {
  AddDirected(links, ar, ap, al, br, bp, bl, name + "_a_to_b");
  AddDirected(links, br, bp, bl, ar, ap, al, name + "_b_to_a");
}

string IndexName(char const *prefix, int a, int b = -1) {
  ostringstream out;
  out << prefix;
  if(a < 10) out << '0';
  out << a;
  if(b >= 0) {
    out << '_';
    if(b < 10) out << '0';
    out << b;
  }
  return out.str();
}

void AddEndpoint(vector<Noc16Endpoint> &result, int node,
                 Noc16Endpoint::Kind kind, int instance, int lane,
                 int router, int port, int router_lane,
                 string const &name) {
  Noc16Endpoint endpoint = { node, kind, instance, lane, router, port,
                             router_lane, name };
  result.push_back(endpoint);
}

} // namespace

vector<Noc16Link> Noc16Map::InternalLinks() {
  vector<Noc16Link> links;

  // L1 p0 <-> local L2 p0, four lane-preserving planes.
  for(int cluster = 0; cluster < 16; ++cluster)
    for(int lane = 0; lane < 4; ++lane)
      AddBidirectional(links, L1(cluster), 0, lane, L2(cluster), 0, lane,
                       "l1_l2");

  // L1 cardinal mesh: p1=N, p2=E, p3=S, p4=W.
  for(int row = 0; row < 4; ++row) {
    for(int col = 0; col < 4; ++col) {
      int const here = row * 4 + col;
      if(col < 3)
        for(int lane = 0; lane < 4; ++lane)
          AddBidirectional(links, L1(here), 2, lane, L1(here + 1), 4, lane,
                           "l1_east_west");
      if(row < 3)
        for(int lane = 0; lane < 4; ++lane)
          AddBidirectional(links, L1(here), 3, lane, L1(here + 4), 1, lane,
                           "l1_south_north");
    }
  }

  // Each L2 tile port p1..p4 attaches to a dedicated shim. Shim port 0 is
  // its one-lane L3 side; ports 1..4 are the four L2 lanes.
  for(int cluster = 0; cluster < 16; ++cluster) {
    for(int tile = 0; tile < 4; ++tile) {
      int const shim = Shim(cluster, tile);
      int const l2_port = 1 + tile;
      for(int lane = 0; lane < 4; ++lane)
        AddBidirectional(links, L2(cluster), l2_port, lane,
                         shim, 1 + lane, 0, "l2_shim");
      AddBidirectional(links, shim, 0, 0, L3(cluster, tile), 0, 0,
                       "shim_l3");
    }
  }

  assert(links.size() == 960);
  return links;
}

vector<Noc16Endpoint> Noc16Map::Endpoints() {
  vector<Noc16Endpoint> result;
  for(int cluster = 0; cluster < 16; ++cluster) {
    for(int tile = 0; tile < 4; ++tile) {
      int const l3 = L3(cluster, tile);
      int const instance = cluster * 4 + tile;
      AddEndpoint(result, PE(cluster, tile), Noc16Endpoint::PE, instance, 0,
                  l3, 1, 0, IndexName("PE_", cluster, tile));
      AddEndpoint(result, TDMA(cluster, tile), Noc16Endpoint::TDMA, instance, 0,
                  l3, 2, 0, IndexName("TDMA_", cluster, tile));
      AddEndpoint(result, TSRAM(cluster, tile), Noc16Endpoint::TSRAM, instance, 0,
                  l3, 3, 0, IndexName("TSRAM_", cluster, tile));
      AddEndpoint(result, CSRAM(cluster, tile), Noc16Endpoint::CSRAM, instance, 0,
                  l3, 4, 0, IndexName("CSRAM_", cluster, tile));
    }
    for(int lane = 0; lane < 4; ++lane)
      AddEndpoint(result, CDMA(cluster, lane), Noc16Endpoint::CDMA, cluster, lane,
                  L2(cluster), 5, lane, IndexName("CDMA_", cluster));
  }

  // Clockwise perimeter map: north 0..3, east 4..7, south 8..11 in
  // right-to-left order, and west 12..15 in bottom-to-top order.
  int llch_router[16] = { 0, 1, 2, 3, 3, 7, 11, 15,
                          15, 14, 13, 12, 12, 8, 4, 0 };
  int llch_port[16] = { 1, 1, 1, 1, 2, 2, 2, 2,
                        3, 3, 3, 3, 4, 4, 4, 4 };
  for(int llch = 0; llch < 16; ++llch)
    for(int lane = 0; lane < 4; ++lane)
      AddEndpoint(result, LLCH(llch, lane), Noc16Endpoint::LLCH, llch, lane,
                  L1(llch_router[llch]), llch_port[llch], lane,
                  IndexName("LLCH_", llch));

  assert(result.size() == kNodeCount);
  return result;
}

Noc16Endpoint Noc16Map::Endpoint(int node) {
  assert(node >= 0 && node < kNodeCount);
  vector<Noc16Endpoint> const endpoints = Endpoints();
  for(size_t i = 0; i < endpoints.size(); ++i)
    if(endpoints[i].node == node) return endpoints[i];
  assert(false && "Missing noc16 endpoint");
  return endpoints[0];
}

int Noc16Map::RoutePort(int router, int destination_node) {
  assert(router >= 0 && router < kShimBase);
  Noc16Endpoint const ep = Endpoint(destination_node);

  if(router < kL2Base) {
    int target_cluster = -1;
    int target_l1 = -1;
    if(ep.kind == Noc16Endpoint::LLCH) {
      target_l1 = ep.router;
    } else {
      target_cluster = (ep.kind == Noc16Endpoint::CDMA) ? ep.instance
                                                        : ep.instance / 4;
      target_l1 = L1(target_cluster);
    }
    if(router == target_l1)
      return ep.kind == Noc16Endpoint::LLCH ? ep.port : 0;
    int const here = router - kL1Base;
    int const target = target_l1 - kL1Base;
    int const here_col = here % 4, target_col = target % 4;
    int const here_row = here / 4, target_row = target / 4;
    if(here_col < target_col) return 2; // east
    if(here_col > target_col) return 4; // west
    if(here_row < target_row) return 3; // south
    assert(here_row > target_row);
    return 1; // north
  }

  if(router < kL3Base) {
    int const cluster = router - kL2Base;
    if(ep.kind == Noc16Endpoint::CDMA && ep.instance == cluster) return 5;
    if(ep.router >= kL3Base && ep.router < kShimBase &&
       ((ep.router - kL3Base) / 4) == cluster)
      return 1 + ((ep.router - kL3Base) % 4);
    return 0;
  }

  // L3: a directly attached PE/TDMA/TSRAM/CSRAM exits locally; all other
  // destinations go through p0 to the shim.
  if(ep.router == router) return ep.port;
  return 0;
}

vector<vector<int> > Noc16Map::L1GrantWeights(int cluster) {
  assert(cluster >= 0 && cluster < 16);
  vector<vector<int> > weights(5, vector<int>(5, 1));
  vector<vector<int> > demand(5, vector<int>(5, 0));

  for(int source = 0; source < 16; ++source) {
    for(int llch = 0; llch < 16; ++llch) {
      int router = L1(source);
      int input_port = 0;
      int const destination = LLCH(llch, 0);
      while(true) {
        int const output_port = RoutePort(router, destination);
        if(router == L1(cluster)) ++demand[input_port][output_port];
        Noc16Endpoint const endpoint = Endpoint(destination);
        if(router == endpoint.router) break;

        int const index = router - kL1Base;
        int row = index / 4, col = index % 4;
        if(output_port == 1) { --row; input_port = 3; }
        else if(output_port == 2) { ++col; input_port = 4; }
        else if(output_port == 3) { ++row; input_port = 1; }
        else if(output_port == 4) { --col; input_port = 2; }
        else assert(false && "PE-to-LLCH path left the L1 mesh early");
        router = L1(row * 4 + col);
      }
    }
  }
  for(int input = 0; input < 5; ++input)
    for(int output = 0; output < 5; ++output)
      if(demand[input][output] > 0) weights[input][output] = demand[input][output];
  return weights;
}

string Noc16Map::RouterName(int router) {
  if(router >= kL1Base && router < kL2Base)
    return IndexName("L1_", router - kL1Base);
  if(router >= kL2Base && router < kL3Base)
    return IndexName("L2_", router - kL2Base);
  if(router >= kL3Base && router < kShimBase) {
    int const index = router - kL3Base;
    return IndexName("L3_", index / 4, index % 4);
  }
  if(router >= kShimBase && router < kRouterCount) {
    int const index = router - kShimBase;
    return IndexName("SHIM_", index / 4, index % 4);
  }
  assert(false && "Invalid noc16 router ID");
  return "";
}

void Noc16Map::Validate() {
  vector<Noc16Link> const links = InternalLinks();
  vector<Noc16Endpoint> const endpoints = Endpoints();
  set<int> nodes;
  set<pair<int, int> > endpoint_inputs;
  set<pair<int, int> > endpoint_outputs;
  for(size_t i = 0; i < endpoints.size(); ++i) {
    assert(nodes.insert(endpoints[i].node).second);
    int const flat = endpoints[i].port *
        ((endpoints[i].router < kL3Base) ? 4 : 1) + endpoints[i].router_lane;
    assert(endpoint_inputs.insert(make_pair(endpoints[i].router, flat)).second);
    assert(endpoint_outputs.insert(make_pair(endpoints[i].router, flat)).second);
  }
  assert(nodes.size() == kNodeCount);

  set<pair<pair<int,int>, pair<int,int> > > directed;
  for(size_t i = 0; i < links.size(); ++i) {
    Noc16Link const &l = links[i];
    assert(l.source_router >= 0 && l.source_router < kRouterCount);
    assert(l.sink_router >= 0 && l.sink_router < kRouterCount);
    pair<pair<int,int>, pair<int,int> > const edge(
        make_pair(l.source_router, l.source_port * 4 + l.source_lane),
        make_pair(l.sink_router, l.sink_port * 4 + l.sink_lane));
    assert(directed.insert(edge).second);
  }
  for(set<pair<pair<int,int>, pair<int,int> > >::const_iterator it =
      directed.begin(); it != directed.end(); ++it)
    assert(directed.count(make_pair(it->second, it->first)) == 1);
}
