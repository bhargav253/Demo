#ifndef _NOC16_HPP_
#define _NOC16_HPP_

#include "network.hpp"
#include <fstream>

class Noc16 : public Network {
  std::ofstream *_telemetry;
  int _telemetry_interval;
  std::vector<long long> _previous_router_in;
  std::vector<long long> _previous_router_out;
  std::vector<long long> _previous_channel;
  std::vector<long long> _previous_inject;
  std::vector<long long> _previous_eject;
  void _ComputeSize(Configuration const &config);
  void _BuildNet(Configuration const &config);
  void _BuildRoutingTable();
public:
  Noc16(Configuration const &config, std::string const &name);
  virtual ~Noc16();
  virtual void WriteOutputs();
  static void RegisterRoutingFunctions();
};

#endif
