#ifndef _NOC16_MAP_HPP_
#define _NOC16_MAP_HPP_

#include <string>
#include <vector>

struct Noc16Link {
  int source_router;
  int source_port;
  int source_lane;
  int sink_router;
  int sink_port;
  int sink_lane;
  std::string name;
};

struct Noc16Endpoint {
  enum Kind { PE, TDMA, TSRAM, CSRAM, CDMA, LLCH };
  int node;
  Kind kind;
  int instance;
  int lane;
  int router;
  int port;
  int router_lane;
  std::string name;
};

// Stable, simulation-visible identity and wiring map for the 16-LLCH design.
// Routers and shims share one ID space because both are timed switching nodes.
class Noc16Map {
public:
  static int const kL1Base = 0;
  static int const kL2Base = 16;
  static int const kL3Base = 32;
  static int const kShimBase = 96;
  static int const kRouterCount = 160;

  static int const kPeBase = 0;
  static int const kTdmaBase = 64;
  static int const kTsramBase = 128;
  static int const kCsramBase = 192;
  static int const kCdmaBase = 256;
  static int const kLlchBase = 320;
  static int const kNodeCount = 384;

  static int L1(int cluster) { return kL1Base + cluster; }
  static int L2(int cluster) { return kL2Base + cluster; }
  static int L3(int cluster, int tile) { return kL3Base + cluster * 4 + tile; }
  static int Shim(int cluster, int tile) { return kShimBase + cluster * 4 + tile; }

  static int PE(int cluster, int tile) { return kPeBase + cluster * 4 + tile; }
  static int TDMA(int cluster, int tile) { return kTdmaBase + cluster * 4 + tile; }
  static int TSRAM(int cluster, int tile) { return kTsramBase + cluster * 4 + tile; }
  static int CSRAM(int cluster, int tile) { return kCsramBase + cluster * 4 + tile; }
  static int CDMA(int cluster, int lane) { return kCdmaBase + cluster * 4 + lane; }
  static int LLCH(int llch, int lane) { return kLlchBase + llch * 4 + lane; }

  // Lane-level unidirectional internal links. Every physical bidirectional
  // connection is represented by two entries.
  static std::vector<Noc16Link> InternalLinks();
  static std::vector<Noc16Endpoint> Endpoints();
  static Noc16Endpoint Endpoint(int node);
  // Deterministic logical output port. Shims use their own lane adapter and
  // are intentionally excluded.
  static int RoutePort(int router, int destination_node);
  // Per-input/per-output grant weights generated from one equal flow from
  // every L1 cluster to every LLCH. Absent flows retain a safe weight of one.
  static std::vector<std::vector<int> > L1GrantWeights(int cluster);
  static std::string RouterName(int router);
  static void Validate();
};

#endif
