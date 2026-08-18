#include "booksim.hpp"

#include <cassert>
#include <map>
#include <set>
#include <sstream>

#include "noc16.hpp"
#include "noc16_map.hpp"
#include "routefunc.hpp"
#include "routers/lane_voq_router.hpp"
#include "routers/noc_lane_shim.hpp"

using namespace std;

namespace {
vector<map<int, int> > gNoc16Routes;

int RouterLanes(int router) {
  return router < Noc16Map::kL3Base ? 4 : 1;
}
int RouterPorts(int router) {
  if(router < Noc16Map::kL2Base) return 5;
  if(router < Noc16Map::kL3Base) return 6;
  return 5;
}
int FlatPort(int router, int port, int lane) {
  return port * RouterLanes(router) + lane;
}
long long Activity(FlitChannel const *channel) {
  vector<int> const &a = channel->GetActivity();
  long long total = 0;
  for(size_t i = 0; i < a.size(); ++i) total += a[i];
  return total;
}

void min_noc16(Router const *router, Flit const *flit, int in_channel,
               OutputSet *outputs, bool inject) {
  (void)in_channel;
  outputs->Clear();
  if(inject) {
    outputs->AddRange(-1, 0, gNumVCs - 1);
    return;
  }
  assert(router);
  int const id = router->GetID();
  assert(id >= 0 && id < static_cast<int>(gNoc16Routes.size()));
  map<int,int>::const_iterator const it = gNoc16Routes[id].find(flit->dest);
  assert(it != gNoc16Routes[id].end());
  outputs->AddRange(it->second, flit->vc, flit->vc);
}
} // namespace

Noc16::Noc16(Configuration const &config, string const &name)
  : Network(config, name), _telemetry(NULL),
    _telemetry_interval(config.GetInt("noc_telemetry_interval")) {
  _ComputeSize(config);
  _Alloc();
  _BuildNet(config);
  _BuildRoutingTable();
  string const file = config.GetStr("noc_telemetry_file");
  if(!file.empty() && _telemetry_interval > 0) {
    _telemetry = new ofstream(file.c_str());
    assert(_telemetry->good());
    *_telemetry << "cycle,kind,id,name,port,arrivals,departures,occupancy,"
                   "request_cycles,grant_cycles,allocator_loss_cycles,"
                   "contention_cycles,credit_stall_cycles,queue_wait_samples,"
                   "queue_wait_cycles,residence_samples,residence_cycles,"
                   "avg_queue_wait,avg_residence\n";
  }
  _previous_router_in.assign(_size, 0);
  _previous_router_out.assign(_size, 0);
  _previous_channel.assign(_channels, 0);
  _previous_inject.assign(_nodes, 0);
  _previous_eject.assign(_nodes, 0);
}

Noc16::~Noc16() { delete _telemetry; }

void Noc16::_ComputeSize(Configuration const &config) {
  (void)config;
  Noc16Map::Validate();
  _size = Noc16Map::kRouterCount;
  _nodes = Noc16Map::kNodeCount;
  _channels = Noc16Map::InternalLinks().size();
}

void Noc16::_BuildNet(Configuration const &config) {
  vector<vector<FlitChannel *> > inputs(_size), outputs(_size);
  vector<vector<CreditChannel *> > input_credits(_size), output_credits(_size);
  for(int router = 0; router < _size; ++router) {
    int const count = RouterPorts(router) * RouterLanes(router);
    inputs[router].assign(count, NULL);
    outputs[router].assign(count, NULL);
    input_credits[router].assign(count, NULL);
    output_credits[router].assign(count, NULL);
  }

  vector<Noc16Link> const links = Noc16Map::InternalLinks();
  assert(static_cast<int>(links.size()) == _channels);
  for(int channel = 0; channel < _channels; ++channel) {
    Noc16Link const &link = links[channel];
    int const source = FlatPort(link.source_router, link.source_port,
                                link.source_lane);
    int const sink = FlatPort(link.sink_router, link.sink_port,
                              link.sink_lane);
    assert(!outputs[link.source_router][source]);
    assert(!inputs[link.sink_router][sink]);
    outputs[link.source_router][source] = _chan[channel];
    output_credits[link.source_router][source] = _chan_cred[channel];
    inputs[link.sink_router][sink] = _chan[channel];
    input_credits[link.sink_router][sink] = _chan_cred[channel];
    _chan[channel]->SetLatency(1);
    _chan_cred[channel]->SetLatency(1);
  }

  vector<Noc16Endpoint> const endpoints = Noc16Map::Endpoints();
  for(size_t i = 0; i < endpoints.size(); ++i) {
    Noc16Endpoint const &ep = endpoints[i];
    int const flat = FlatPort(ep.router, ep.port, ep.router_lane);
    assert(!inputs[ep.router][flat] && !outputs[ep.router][flat]);
    inputs[ep.router][flat] = _inject[ep.node];
    input_credits[ep.router][flat] = _inject_cred[ep.node];
    outputs[ep.router][flat] = _eject[ep.node];
    output_credits[ep.router][flat] = _eject_cred[ep.node];
    _inject[ep.node]->SetLatency(1);
    _inject_cred[ep.node]->SetLatency(1);
    _eject[ep.node]->SetLatency(1);
    _eject_cred[ep.node]->SetLatency(1);
  }

  for(int router = 0; router < _size; ++router) {
    string const name = Noc16Map::RouterName(router);
    if(router < Noc16Map::kL2Base)
      _routers[router] = new LaneVOQRouter(config, this, name, router,
                                           20, 20, 5, 4, 48);
    else if(router < Noc16Map::kL3Base)
      _routers[router] = new LaneVOQRouter(config, this, name, router,
                                           24, 24, 6, 4, 48);
    else if(router < Noc16Map::kShimBase)
      _routers[router] = new LaneVOQRouter(config, this, name, router,
                                           5, 5, 5, 1, 12);
    else
      _routers[router] = new NocLaneShim(config, this, name, router);
    if((router < Noc16Map::kL2Base) &&
       (config.GetStr("voq_grant_policy") == "weighted")) {
      LaneVOQRouter *l1 = dynamic_cast<LaneVOQRouter *>(_routers[router]);
      assert(l1);
      l1->SetGrantWeights(Noc16Map::L1GrantWeights(router));
    }
    _timed_modules.push_back(_routers[router]);

    int const count = RouterPorts(router) * RouterLanes(router);
    for(int input = 0; input < count; ++input) {
      assert(inputs[router][input] && input_credits[router][input]);
      _routers[router]->AddInputChannel(inputs[router][input],
                                         input_credits[router][input]);
    }
    for(int output = 0; output < count; ++output) {
      assert(outputs[router][output] && output_credits[router][output]);
      _routers[router]->AddOutputChannel(outputs[router][output],
                                          output_credits[router][output]);
    }
  }
}

void Noc16::_BuildRoutingTable() {
  gNoc16Routes.assign(_size, map<int,int>());
  for(int router = 0; router < Noc16Map::kShimBase; ++router)
    for(int node = 0; node < _nodes; ++node)
      gNoc16Routes[router][node] = Noc16Map::RoutePort(router, node);
}

void Noc16::RegisterRoutingFunctions() {
  gRoutingFunctionMap["min_noc16"] = &min_noc16;
}

void Noc16::WriteOutputs() {
  Network::WriteOutputs();
  if(!_telemetry || (GetSimTime() % _telemetry_interval)) return;
  for(int router = 0; router < _size; ++router) {
    int const count = RouterPorts(router) * RouterLanes(router);
    long long in = 0, out = 0;
    int occupancy = 0;
    for(int i = 0; i < count; ++i) {
      in += Activity(_routers[router]->GetInputChannel(i));
      out += Activity(_routers[router]->GetOutputChannel(i));
    }
    long long contention = 0, stalls = 0;
    NocLaneShim const *shim = dynamic_cast<NocLaneShim const *>(_routers[router]);
    if(shim) {
      for(int i = 0; i < count; ++i) occupancy += shim->GetBufferOccupancy(i);
      contention = shim->ContentionCycles(); stalls = shim->CreditStallCycles();
    } else {
      for(int port = 0; port < RouterPorts(router); ++port)
        occupancy += _routers[router]->GetBufferOccupancy(
            port * RouterLanes(router));
    }
    *_telemetry << GetSimTime() << ',' << (shim ? "shim" : "router") << ','
      << router << ',' << Noc16Map::RouterName(router) << ",-1,"
      << in - _previous_router_in[router] << ','
      << out - _previous_router_out[router] << ',' << occupancy
      << ",0,0,0," << contention << ',' << stalls
      << ",0,0,0,0,0,0\n";
    _previous_router_in[router] = in;
    _previous_router_out[router] = out;

    LaneVOQRouter *voq = dynamic_cast<LaneVOQRouter *>(_routers[router]);
    if(voq) {
      for(int port = 0; port < voq->NumLogicalPorts(); ++port) {
        LaneVOQRouter::LogicalPortTelemetry const p =
            voq->TakeLogicalPortTelemetry(port);
        double const avg_queue = p.queue_wait_samples ?
            static_cast<double>(p.queue_wait_cycles) / p.queue_wait_samples : 0.0;
        double const avg_residence = p.residence_samples ?
            static_cast<double>(p.residence_cycles) / p.residence_samples : 0.0;
        *_telemetry << GetSimTime() << ",port," << router << ','
          << Noc16Map::RouterName(router) << ',' << port << ','
          << p.arrivals << ',' << p.departures << ','
          << voq->LogicalPortOccupancy(port) << ','
          << p.request_cycles << ',' << p.grant_cycles << ','
          << p.allocator_loss_cycles << ",0," << p.credit_stall_cycles << ','
          << p.queue_wait_samples << ',' << p.queue_wait_cycles << ','
          << p.residence_samples << ',' << p.residence_cycles << ','
          << avg_queue << ',' << avg_residence << '\n';
      }
    }
  }
  vector<Noc16Link> const links = Noc16Map::InternalLinks();
  for(int c = 0; c < _channels; ++c) {
    long long const active = Activity(_chan[c]);
    *_telemetry << GetSimTime() << ",link," << c << ',' << links[c].name
      << ",-1,0," << active - _previous_channel[c]
      << ",0,0,0,0,0,0,0,0,0,0,0,0\n";
    _previous_channel[c] = active;
  }
  vector<Noc16Endpoint> const eps = Noc16Map::Endpoints();
  for(size_t i = 0; i < eps.size(); ++i) {
    int const node = eps[i].node;
    long long const injected = Activity(_inject[node]);
    long long const ejected = Activity(_eject[node]);
    *_telemetry << GetSimTime() << ",endpoint," << node << ',' << eps[i].name
      << ",-1," << injected - _previous_inject[node] << ','
      << ejected - _previous_eject[node]
      << ",0,0,0,0,0,0,0,0,0,0,0,0\n";
    _previous_inject[node] = injected;
    _previous_eject[node] = ejected;
  }
  _telemetry->flush();
}
