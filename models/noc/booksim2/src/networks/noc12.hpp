#ifndef _NOC12_HPP_
#define _NOC12_HPP_

#include "network.hpp"
#include <fstream>

class Noc12 : public Network {
  std::ofstream *_telemetry;
  int _telemetry_interval;
  std::vector<long long> _previous_router_in, _previous_router_out;
  std::vector<long long> _previous_channel, _previous_inject, _previous_eject;
  void _ComputeSize(Configuration const &config);
  void _BuildNet(Configuration const &config);
  void _BuildRoutingTable();
public:
  Noc12(Configuration const &config, std::string const &name);
  virtual ~Noc12();
  virtual void WriteOutputs();
  static void RegisterRoutingFunctions();
};

#endif
