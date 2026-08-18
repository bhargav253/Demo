#ifndef _NOC16C_MAP_HPP_
#define _NOC16C_MAP_HPP_

#include <string>
#include <vector>

struct Noc16CLink {
  int source_router, source_port, source_lane;
  int sink_router, sink_port, sink_lane;
  std::string name;
};

struct Noc16CEndpoint {
  enum Kind { PE, TDMA, TSRAM, CSRAM, CDMA, LLCH };
  int node;
  Kind kind;
  int instance, lane;
  int router, port, router_lane;
  std::string name;
};

class Noc16CMap {
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

  static int L1(int index) { return kL1Base + index; }
  static int L2(int cluster) { return kL2Base + cluster; }
  static int L3(int cluster, int tile) { return kL3Base + cluster * 4 + tile; }
  static int Shim(int cluster, int tile) { return kShimBase + cluster * 4 + tile; }
  static int PE(int cluster, int tile) { return kPeBase + cluster * 4 + tile; }
  static int TDMA(int cluster, int tile) { return kTdmaBase + cluster * 4 + tile; }
  static int TSRAM(int cluster, int tile) { return kTsramBase + cluster * 4 + tile; }
  static int CSRAM(int cluster, int tile) { return kCsramBase + cluster * 4 + tile; }
  static int CDMA(int cluster, int lane) { return kCdmaBase + cluster * 4 + lane; }
  static int LLCH(int llch, int lane) { return kLlchBase + llch * 4 + lane; }

  static std::vector<Noc16CLink> InternalLinks();
  static std::vector<Noc16CEndpoint> Endpoints();
  static Noc16CEndpoint Endpoint(int node);
  static int RoutePort(int router, int destination_node);
  static std::vector<std::vector<int> > GrantWeights(int router);
  static std::string RouterName(int router);
  static int RouterPorts(int router);
  static int RouterLanes(int router);
  static void Validate();
};

#endif
