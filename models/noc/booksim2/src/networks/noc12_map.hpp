#ifndef _NOC12_MAP_HPP_
#define _NOC12_MAP_HPP_

#include <string>
#include <vector>

struct Noc12Link {
  int source_router, source_port, source_lane;
  int sink_router, sink_port, sink_lane;
  std::string name;
};

struct Noc12Endpoint {
  enum Kind { PE, TDMA, TSRAM, CSRAM, CDMA, LLCH };
  int node;
  Kind kind;
  int instance, lane;
  int router, port, router_lane;
  std::string name;
};

class Noc12Map {
public:
  static int const kL1Base = 0;
  static int const kL2Base = 9;
  static int const kL3Base = 25;
  static int const kShimBase = 89;
  static int const kRouterCount = 153;

  static int const kPeBase = 0;
  static int const kTdmaBase = 64;
  static int const kTsramBase = 128;
  static int const kCsramBase = 192;
  static int const kCdmaBase = 256;
  static int const kLlchBase = 320;
  static int const kNodeCount = 368;

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

  static std::vector<Noc12Link> InternalLinks();
  static std::vector<Noc12Endpoint> Endpoints();
  static Noc12Endpoint Endpoint(int node);
  static int RoutePort(int router, int destination_node);
  static std::vector<std::vector<int> > GrantWeights(int router);
  static std::string RouterName(int router);
  static int RouterPorts(int router);
  static int RouterLanes(int router);
  static void Validate();
};

#endif
