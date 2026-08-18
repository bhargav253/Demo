#include "booksim.hpp"

#include <cassert>
#include <sstream>

#include "allocators/allocator.hpp"
#include "buffer_state.hpp"
#include "lane_voq_router.hpp"
#include "allocators/islip.hpp"

using namespace std;

static bool _MaximumAugment(int input, vector<vector<int> > const &edges,
                            vector<bool> &seen_output,
                            vector<int> &output_to_input)
{
  for(size_t e = 0; e < edges[input].size(); ++e) {
    int const output = edges[input][e];
    if(seen_output[output]) continue;
    seen_output[output] = true;
    if((output_to_input[output] < 0) ||
       _MaximumAugment(output_to_input[output], edges, seen_output,
                       output_to_input)) {
      output_to_input[output] = input;
      return true;
    }
  }
  return false;
}

LaneVOQRouter::LaneVOQRouter(Configuration const &config, Module *parent,
                             string const &name, int id, int inputs, int outputs,
                             int logical_ports, int lanes,
                             int total_buffer_size)
  : Router(config, parent, name, id, inputs, outputs),
    _ports(logical_ports > 0 ? logical_ports : config.GetInt("voq_ports")),
    _lanes(lanes > 0 ? lanes : config.GetInt("voq_lanes")),
    _private_depth(config.GetInt("vc_buf_size")),
    _shared_capacity(config.GetInt("voq_shared_buf_size")),
    _ideal_output(config.GetInt("voq_ideal_output") != 0),
    _lane_credit_first((config.GetStr("voq_credit_policy") == "lane_first") ||
                       (config.GetStr("voq_credit_policy") == "reserved_first")),
    _bypass_enabled(config.GetInt("voq_bypass") != 0),
    _storage(config.GetStr("voq_storage")),
    _bank_policy(config.GetStr("voq_bank_policy")),
    _banked(_storage != "flop"),
    _fixed_lane_banks(_storage == "sram_fixed"),
    _banks(_lanes),
    _bank_depth((total_buffer_size > 0 ? total_buffer_size :
                 config.GetInt("voq_total_buf_size")) / _lanes),
    _alloc_iters(config.GetInt("alloc_iters")),
    _lookaside_limit(config.GetInt("voq_lookaside_size")),
    _vc_sharing(config.GetInt("voq_vc_sharing") != 0),
    _vcs(config.GetInt("num_vcs")),
    _reserved_per_vc(config.GetInt("voq_reserved_per_vc")),
    _allocator_policy(config.GetStr("voq_allocator")),
    _grant_policy(config.GetStr("voq_grant_policy")),
    _read_latency(config.GetInt("voq_read_latency")),
    _rf(NULL),
    _bank_read_requests(0),
    _bank_read_conflicts(0),
    _bank_read_matches(0),
    _bank_write_count(0),
    _lookaside_high_water(0),
    _trace(NULL)
{
  if((_ports <= 1) || (_lanes <= 0) ||
     (_inputs != _ports * _lanes) || (_outputs != _ports * _lanes) ||
     (_private_depth <= 0) || (_shared_capacity < 0)) {
    Error("Invalid lane_voq router dimensions or buffer sizes.");
  }
  string const credit_policy = config.GetStr("voq_credit_policy");
  if((credit_policy != "strict_pool") && (credit_policy != "lane_first") &&
     (credit_policy != "shared_first") &&
     (credit_policy != "reserved_first")) {
    Error("invalid voq_credit_policy.");
  if((_allocator_policy != "islip") && (_allocator_policy != "max_size"))
    Error("voq_allocator must be islip or max_size.");
  if((_grant_policy != "rr") && (_grant_policy != "weighted"))
    Error("voq_grant_policy must be rr or weighted.");
  if(_read_latency < 1) Error("voq_read_latency must be at least one cycle.");
  }
  if((_storage != "flop") && (_storage != "sram_fixed") &&
     (_storage != "sram_shared"))
    Error("voq_storage must be flop, sram_fixed, or sram_shared.");
  if(_banked && (_bank_policy != "rr") && (_bank_policy != "pressure") &&
     (_bank_policy != "fixed"))
    Error("voq_bank_policy must be fixed, rr, or pressure.");
  int const configured_total = total_buffer_size > 0 ? total_buffer_size :
                               config.GetInt("voq_total_buf_size");
  if(_banked && ((_bank_depth < _private_depth) ||
     (configured_total % _banks) ||
     (!_vc_sharing && (config.GetInt("voq_tagged_credits") == 0))))
    Error("Banked VOQ requires one bank per lane and valid depth/reservations.");

  // The original single-router experiments encode the local physical output
  // directly in Flit::dest.  Complete networks instead use BookSim's routing
  // function to select a logical output port at every hop.
  if(config.GetStr("topology") != "fly") {
    string const rf_name = config.GetStr("routing_function") + "_" +
                           config.GetStr("topology");
    map<string, tRoutingFunction>::const_iterator const rf_it =
        gRoutingFunctionMap.find(rf_name);
    if(rf_it == gRoutingFunctionMap.end())
      Error("Invalid lane_voq routing function: " + rf_name);
    _rf = rf_it->second;
  }

  _voq.resize(_inputs,
      vector<vector<deque<Entry> > >(_ports, vector<deque<Entry> >(_vcs)));
  _vc_rr.assign(_inputs, vector<int>(_ports, 0));
  _occupancy.assign(_ports, 0);
  _shared_free.assign(_ports, _shared_capacity);
  _borrowed_shared.assign(_inputs, 0);
  _withheld_lane.assign(_inputs, 0);
  if(_vc_sharing) {
    if(!_fixed_lane_banks || _vcs < 1 || _reserved_per_vc < 1 ||
       (_vcs * _reserved_per_vc > _bank_depth))
      Error("VC sharing requires valid reservations in fixed lane banks.");
    _vc_shared_used.assign(_inputs, vector<int>(_vcs, 0));
    _vc_withheld.assign(_inputs, vector<int>(_vcs, 0));
    _vc_reserved_embedded.assign(_inputs, vector<int>(_vcs, 0));
    _vc_shared_inflight.assign(_inputs, vector<int>(_vcs, 0));
    _lane_shared_free.assign(_inputs,
      _bank_depth - _vcs * _reserved_per_vc);
  }
  if(_banked) {
    _private_unreserved.assign(_ports, vector<int>(_banks, 0));
    _shared_unreserved.assign(_ports, vector<int>(_banks,
                                  _bank_depth - _private_depth));
    _private_reserved.assign(_ports, vector<int>(_banks, _private_depth));
    _shared_reserved.assign(_ports, vector<int>(_banks, 0));
    _spill_rr.assign(_ports, 0);
    _bank_read_rr.assign(_ports, vector<int>(_banks, 0));
    _bank_gptr.assign(_lanes, vector<int>(_ports, 0));
    _bank_weighted_gptr.assign(_lanes, vector<int>(_ports, 0));
    _bank_aptr.assign(_lanes, vector<int>(_ports, 0));
  }
  _output_buffer.resize(_outputs);
  _credit_buffer.resize(_inputs);
  _port_telemetry.resize(_ports);
  _port_requests_this_cycle.assign(_ports, 0);
  _port_grants_this_cycle.assign(_ports, 0);

  for(int lane = 0; lane < _lanes; ++lane) {
    ostringstream alloc_name;
    alloc_name << "lane_" << lane << "_islip";
    Allocator *allocator = Allocator::NewAllocator(
      this, alloc_name.str(), _banked ? "islip(1)" : "islip",
      _ports, _ports, &config);
    assert(allocator);
    _allocators.push_back(allocator);

    ostringstream bypass_name;
    bypass_name << "lane_" << lane << "_bypass_islip";
    Allocator *bypass_allocator = Allocator::NewAllocator(
      this, bypass_name.str(), "islip", _ports, _ports, &config);
    assert(bypass_allocator);
    _bypass_allocators.push_back(bypass_allocator);
  }
  for(int output = 0; output < _outputs; ++output) {
    ostringstream buffer_name;
    buffer_name << "next_buffer_" << output;
    _downstream.push_back(new BufferState(config, this, buffer_name.str()));
  }
  string const trace_file = config.GetStr("voq_trace_file");
  if(!trace_file.empty()) {
    _trace = new ofstream(trace_file.c_str());
    if(!_trace->is_open()) Error("Unable to open VOQ CSV trace file.");
    *_trace << "cycle,event,router,packet,source,destination,"
            << "input_port,lane,output_port,port_occupancy,shared_free,"
            << "lane_shared_debt,credit_action,vc\n";
  }
}

void LaneVOQRouter::SetGrantWeights(vector<vector<int> > const &weights)
{
  assert(static_cast<int>(weights.size()) == _ports);
  _grant_weights = weights;
  _grant_schedules.assign(_ports, vector<int>());
  for(int output = 0; output < _ports; ++output) {
    for(int input = 0; input < _ports; ++input) {
      assert(static_cast<int>(weights[input].size()) == _ports);
      assert(weights[input][output] > 0);
      for(int slot = 0; slot < weights[input][output]; ++slot)
        _grant_schedules[output].push_back(input);
    }
  }
  for(size_t lane = 0; lane < _allocators.size(); ++lane) {
    iSLIP_Sparse *main_alloc = dynamic_cast<iSLIP_Sparse *>(_allocators[lane]);
    iSLIP_Sparse *bypass_alloc =
        dynamic_cast<iSLIP_Sparse *>(_bypass_allocators[lane]);
    if(main_alloc) main_alloc->SetGrantWeights(weights);
    assert(bypass_alloc);
    bypass_alloc->SetGrantWeights(weights);
  }
}

LaneVOQRouter::~LaneVOQRouter()
{
  if(_banked) {
    cout << "BANK_STATS router=" << _id
         << " storage=" << _storage
         << " policy=" << _bank_policy
         << " read_requests=" << _bank_read_requests
         << " read_matches=" << _bank_read_matches
         << " read_conflicts=" << _bank_read_conflicts
         << " writes=" << _bank_write_count
         << " lookaside_high_water=" << _lookaside_high_water << endl;
  }
  for(size_t i = 0; i < _allocators.size(); ++i) delete _allocators[i];
  for(size_t i = 0; i < _bypass_allocators.size(); ++i)
    delete _bypass_allocators[i];
  for(size_t i = 0; i < _downstream.size(); ++i) delete _downstream[i];
  delete _trace;
}

void LaneVOQRouter::_Trace(char const *event, Flit const *flit, int input,
                           int output, char const *credit_action)
{
  if(!_trace || !flit) return;
  int const input_port = (input >= 0) ? input / _lanes : flit->src / _lanes;
  int const lane = (input >= 0) ? input % _lanes : flit->src % _lanes;
  int const output_port = (output >= 0) ? output / _lanes : flit->dest / _lanes;
  *_trace << GetSimTime() << ',' << event << ',' << _id << ',' << flit->pid
          << ',' << flit->src << ',' << flit->dest << ','
          << input_port << ',' << lane << ',' << output_port << ','
          << _occupancy[input_port] << ',' << _shared_free[input_port] << ",\"[";
  for(int l = 0; l < _lanes; ++l) {
    if(l) *_trace << ';';
    *_trace << _borrowed_shared[input_port * _lanes + l];
  }
  *_trace << "]\"," << credit_action << ',' << flit->vc << '\n';
}

void LaneVOQRouter::AddOutputChannel(FlitChannel *channel,
                                     CreditChannel *backchannel)
{
  int const output = _output_channels.size();
  _downstream[output]->SetMinLatency(channel->GetLatency() +
                                     backchannel->GetLatency() +
                                     _credit_delay + 1);
  Router::AddOutputChannel(channel, backchannel);
}

void LaneVOQRouter::ReadInputs()
{
  _ReceiveFlits();
  _ReceiveCredits();
}

void LaneVOQRouter::_ReceiveFlits()
{
  for(int input = 0; input < _inputs; ++input) {
    Flit *f = _input_channels[input]->Receive();
    if(f) {
      assert(_arrivals.count(input) == 0);
      f->voq_router_arrival_time = GetSimTime();
      int const output_port = _OutputFor(f, input) / _lanes;
      assert(output_port >= 0 && output_port < _ports);
      ++_port_telemetry[output_port].arrivals;
      _arrivals[input] = f;
    }
  }
}

void LaneVOQRouter::_BeginPortArbitrationTelemetry()
{
  fill(_port_requests_this_cycle.begin(),
       _port_requests_this_cycle.end(), 0);
  fill(_port_grants_this_cycle.begin(),
       _port_grants_this_cycle.end(), 0);
  for(int output_port = 0; output_port < _ports; ++output_port) {
    for(int lane = 0; lane < _lanes; ++lane) {
      bool ready = false;
      for(int input_port = 0; input_port < _ports && !ready; ++input_port) {
        if(input_port == output_port) continue;
        int const input = input_port * _lanes + lane;
        for(int vc = 0; vc < _vcs; ++vc) {
          if(_voq[input][output_port][vc].empty()) continue;
          Entry const &entry = _voq[input][output_port][vc].front();
          if(entry.payload_ready && entry.ready_time <= GetSimTime()) {
            ready = true;
            break;
          }
        }
      }
      if(!ready) continue;
      int const output = output_port * _lanes + lane;
      if(!_ideal_output && _downstream[output]->IsFullFor(0))
        ++_port_telemetry[output_port].credit_stall_cycles;
      else
        ++_port_requests_this_cycle[output_port];
    }
    _port_telemetry[output_port].request_cycles +=
        _port_requests_this_cycle[output_port];
  }
}

void LaneVOQRouter::_FinishPortArbitrationTelemetry()
{
  for(int output_port = 0; output_port < _ports; ++output_port) {
    assert(_port_grants_this_cycle[output_port] <=
           _port_requests_this_cycle[output_port]);
    _port_telemetry[output_port].allocator_loss_cycles +=
        _port_requests_this_cycle[output_port] -
        _port_grants_this_cycle[output_port];
  }
}

void LaneVOQRouter::_RecordPortGrant(int output_port, Flit const *flit)
{
  assert(output_port >= 0 && output_port < _ports);
  assert(flit && flit->voq_router_arrival_time >= 0);
  ++_port_grants_this_cycle[output_port];
  ++_port_telemetry[output_port].grant_cycles;
  ++_port_telemetry[output_port].queue_wait_samples;
  _port_telemetry[output_port].queue_wait_cycles +=
      GetSimTime() - flit->voq_router_arrival_time;
}

void LaneVOQRouter::_RecordPortDeparture(int output_port, Flit const *flit)
{
  assert(output_port >= 0 && output_port < _ports);
  assert(flit && flit->voq_router_arrival_time >= 0);
  ++_port_telemetry[output_port].departures;
  ++_port_telemetry[output_port].residence_samples;
  _port_telemetry[output_port].residence_cycles +=
      GetSimTime() - flit->voq_router_arrival_time;
}

void LaneVOQRouter::_ReceiveCredits()
{
  for(int output = 0; output < _outputs; ++output) {
    Credit *c = _output_credits[output]->Receive();
    if(c) {
      if(!_ideal_output) _downstream[output]->ProcessCredit(c);
      c->Free();
    }
  }
}

void LaneVOQRouter::_QueueCredit(int input, int vc, int reservation_type,
                                 int reservation_bank)
{
  Credit *c = Credit::New();
  c->vc.insert(vc);
  c->voq_reservation_type = reservation_type;
  c->voq_reservation_bank = reservation_bank;
  _credit_buffer[input].push(c);
}

int LaneVOQRouter::_ReserveSharedBank(int input)
{
  int const port = input / _lanes;
  int const lane = input % _lanes;
  if(_fixed_lane_banks) {
    if(_shared_unreserved[port][lane] <= 0) return -1;
    --_shared_unreserved[port][lane];
    ++_shared_reserved[port][lane];
    return lane;
  }

  int selected = -1;
  if(_shared_unreserved[port][lane] > 0) {
    selected = lane;
  } else if(_bank_policy == "rr") {
    for(int offset = 0; offset < _banks; ++offset) {
      int const bank = (_spill_rr[port] + offset) % _banks;
      if(_shared_unreserved[port][bank] > 0) {
        selected = bank;
        break;
      }
    }
  } else {
    int best_pressure = 1 << 30;
    for(int bank = 0; bank < _banks; ++bank) {
      if(_shared_unreserved[port][bank] <= 0) continue;
      int pressure = 0;
      for(int l = 0; l < _lanes; ++l) {
        int const in = port * _lanes + l;
        for(int out = 0; out < _ports; ++out) {
          for(int vc = 0; vc < _vcs; ++vc)
            if(!_voq[in][out][vc].empty() &&
               (_voq[in][out][vc].front().bank == bank)) ++pressure;
        }
      }
      if(pressure < best_pressure) {
        best_pressure = pressure;
        selected = bank;
      }
    }
  }
  if(selected < 0) return -1;
  --_shared_unreserved[port][selected];
  ++_shared_reserved[port][selected];
  _spill_rr[port] = (selected + 1) % _banks;
  return selected;
}

void LaneVOQRouter::_CheckInvariants() const
{
  vector<int> stored(_ports, 0);
  vector<vector<int> > private_entries(_ports, vector<int>(_banks, 0));
  vector<vector<int> > shared_entries(_ports, vector<int>(_banks, 0));
  for(int input = 0; input < _inputs; ++input) {
    int const input_port = input / _lanes;
    assert(_borrowed_shared[input] >= 0);
    assert(_withheld_lane[input] >= 0);
    for(int output_port = 0; output_port < _ports; ++output_port) {
      for(int vc = 0; vc < _vcs; ++vc) {
      stored[input_port] += _voq[input][output_port][vc].size();
      for(deque<Entry>::const_iterator entry = _voq[input][output_port][vc].begin();
          entry != _voq[input][output_port][vc].end(); ++entry) {
        if(_rf && _lanes > 1)
          assert(entry->flit->noc_lane == (input % _lanes));
        else assert((entry->flit->src % _lanes) ==
                    (entry->flit->dest % _lanes));
        if(_banked && !_vc_sharing) {
          assert((entry->bank >= 0) && (entry->bank < _banks));
          if(entry->reservation_type == 0)
            ++private_entries[input_port][entry->bank];
          else {
            assert(entry->reservation_type == 1);
            ++shared_entries[input_port][entry->bank];
          }
        }
      }
      }
    }
  }
  for(deque<PendingRead>::const_iterator read = _read_pipe.begin();
      read != _read_pipe.end(); ++read) {
    assert(!read->bypass);
    ++stored[read->input / _lanes];
    if(_banked && !_vc_sharing) {
      int const port = read->input / _lanes;
      if(read->entry.reservation_type == 0)
        ++private_entries[port][read->entry.bank];
      else
        ++shared_entries[port][read->entry.bank];
    }
  }
  for(int port = 0; port < _ports; ++port) {
    int debt = 0;
    for(int lane = 0; lane < _lanes; ++lane)
      debt += _borrowed_shared[port * _lanes + lane];
    assert(_shared_free[port] >= 0);
    assert(_shared_free[port] <= _shared_capacity);
    assert(_shared_free[port] + debt == _shared_capacity);
    assert(_occupancy[port] == stored[port]);
    assert(_occupancy[port] >= 0);
    assert(_occupancy[port] <= (_vc_sharing ? _lanes * _bank_depth :
           (_lanes * _private_depth + _shared_capacity)));
    if(_vc_sharing) {
      for(int lane = 0; lane < _lanes; ++lane) {
        int const input = port * _lanes + lane;
        int shared = _lane_shared_free[input];
        for(int vc = 0; vc < _vcs; ++vc) {
          assert(_vc_withheld[input][vc] >= 0);
          assert(_vc_reserved_embedded[input][vc] >= 0 &&
                 _vc_reserved_embedded[input][vc] <= _reserved_per_vc);
          assert(_vc_shared_used[input][vc] >= 0);
          assert(_vc_shared_inflight[input][vc] >= 0);
          shared += _vc_shared_used[input][vc];
        }
        assert(shared == _bank_depth - _vcs * _reserved_per_vc);
      }
    }
    if(_banked && !_vc_sharing) {
      for(int bank = 0; bank < _banks; ++bank) {
        assert(_private_unreserved[port][bank] >= 0);
        assert(_shared_unreserved[port][bank] >= 0);
        assert(_private_reserved[port][bank] >= 0);
        assert(_shared_reserved[port][bank] >= 0);
        assert(_private_unreserved[port][bank] +
               _private_reserved[port][bank] +
               private_entries[port][bank] == _private_depth);
        assert(_shared_unreserved[port][bank] +
               _shared_reserved[port][bank] +
               shared_entries[port][bank] ==
               (_bank_depth - _private_depth));
      }
    }
  }
}

void LaneVOQRouter::_EnqueueArrivals()
{
  for(map<int, Flit *>::iterator it = _arrivals.begin();
      it != _arrivals.end(); ++it) {
    int const input = it->first;
    Flit *f = it->second;
    int const input_port = input / _lanes;
    int const lane = input % _lanes;
    int const output = _OutputFor(f, input);
    int const output_port = output / _lanes;
    int const output_lane = output % _lanes;

    assert(f->head && f->tail && (f->vc >= 0) && (f->vc < _vcs));
    assert(output_lane == lane);
    assert(output_port != input_port);
    assert(_occupancy[input_port] < (_vc_sharing ? _lanes * _bank_depth :
           (_lanes * _private_depth + _shared_capacity)));

    if(_vc_sharing) {
      int const vc = f->vc;
      Entry entry = { f, GetSimTime() + 1, lane, -1, false };
      _voq[input][output_port][vc].push_back(entry);
      ++_occupancy[input_port];
      _Trace("S0_ENQUEUE", f, input, output, "HOLD_UNTIL_RELEASE");
      continue;
    }

    int reservation_type = -1;
    int reservation_bank = -1;
    if(_banked) {
      reservation_type = f->voq_reservation_type;
      reservation_bank = f->voq_reservation_bank;
      assert((reservation_type == 0) || (reservation_type == 1));
      assert((reservation_bank >= 0) && (reservation_bank < _banks));
      if(reservation_type == 0) {
        assert(reservation_bank == lane);
        assert(_private_reserved[input_port][reservation_bank] > 0);
        --_private_reserved[input_port][reservation_bank];
      } else {
        if(_fixed_lane_banks) assert(reservation_bank == lane);
        assert(_shared_reserved[input_port][reservation_bank] > 0);
        --_shared_reserved[input_port][reservation_bank];
      }
    }

    bool immediate_credit = false;
    int returned_bank = -1;
    if(_banked) returned_bank = _ReserveSharedBank(input);
    if((!_banked && (_shared_free[input_port] > 0)) ||
       (_banked && (returned_bank >= 0))) {
      --_shared_free[input_port];
      ++_borrowed_shared[input];
      _QueueCredit(input, f->vc, _banked ? 1 : -1, returned_bank);
      immediate_credit = true;
    } else {
      ++_withheld_lane[input];
    }
    Entry entry = { f, GetSimTime() + 1, reservation_bank,
                    reservation_type, !_banked };
    _voq[input][output_port][f->vc].push_back(entry);
    ++_occupancy[input_port];
    _Trace("S0_ENQUEUE", f, input, output,
           immediate_credit ? "RETURN_IMMEDIATE_SHARED" : "WITHHOLD_LANE");
#ifdef TRACK_FLOWS
    ++_received_flits[f->cl][input];
    ++_stored_flits[f->cl][input];
#endif
  }
  _arrivals.clear();
}

int LaneVOQRouter::_OutputFor(Flit const *flit, int input) const
{
  int output_port = -1;
  if(_rf) {
    OutputSet route;
    _rf(this, flit, input, &route, false);
    int route_vc = -1;
    bool const found = route.GetPortVC(&output_port, &route_vc);
    assert(found && (output_port >= 0) && (output_port < _ports));
  } else {
    output_port = flit->dest / _lanes;
  }
  return output_port * _lanes + (input % _lanes);
}

void LaneVOQRouter::_ScheduleWrites()
{
  if(!_banked) return;
  for(int port = 0; port < _ports; ++port) {
    for(int bank = 0; bank < _banks; ++bank) {
      Entry *selected = NULL;
      for(int lane = 0; lane < _lanes; ++lane) {
        int const input = port * _lanes + lane;
        for(int output_port = 0; output_port < _ports; ++output_port) {
          for(int vc = 0; vc < _vcs; ++vc) {
          deque<Entry> &queue = _voq[input][output_port][vc];
          for(deque<Entry>::iterator entry = queue.begin();
              entry != queue.end(); ++entry) {
            if(entry->payload_ready || (entry->bank != bank)) continue;
            if(!selected || (entry->flit->pid < selected->flit->pid))
              selected = &*entry;
          }
          }
        }
      }
      if(selected) {
        selected->payload_ready = true;
        selected->ready_time = GetSimTime() + 1;
        ++_bank_write_count;
      }
    }
  }

  int waiting = 0;
  for(int input = 0; input < _inputs; ++input)
    for(int output_port = 0; output_port < _ports; ++output_port)
      for(int vc = 0; vc < _vcs; ++vc)
      for(deque<Entry>::const_iterator entry = _voq[input][output_port][vc].begin();
          entry != _voq[input][output_port][vc].end(); ++entry)
        if(!entry->payload_ready) ++waiting;
  _lookaside_high_water = max(_lookaside_high_water, waiting);
  assert(waiting <= _lookaside_limit);
}

void LaneVOQRouter::_BypassArrivals()
{
  if(!_bypass_enabled) return;

  // A landing-flop arrival may take the S0 fast path only when its local VOQ
  // is empty.  The separate allocator resolves simultaneous landing arrivals;
  // an output already carrying an S2 queue read this cycle is unavailable.
  for(int lane = 0; lane < _lanes; ++lane) {
    Allocator *allocator = _bypass_allocators[lane];
    allocator->Clear();
    for(map<int, Flit *>::const_iterator it = _arrivals.begin();
        it != _arrivals.end(); ++it) {
      int const input = it->first;
      if((input % _lanes) != lane) continue;
      int const input_port = input / _lanes;
      Flit const *f = it->second;
      int const output = _OutputFor(f, input);
      int const output_port = output / _lanes;
      assert((output % _lanes) == lane);
      assert(output_port != input_port);
      bool queued = false;
      for(int vc = 0; vc < _vcs; ++vc)
        queued |= !_voq[input][output_port][vc].empty();
      if(queued ||
         !_output_buffer[output].empty() ||
         (!_ideal_output && _downstream[output]->IsFullFor(0))) continue;
      allocator->AddRequest(input_port, output_port, output_port);
    }
    allocator->Allocate();

    for(int input_port = 0; input_port < _ports; ++input_port) {
      int const output_port = allocator->OutputAssigned(input_port);
      if(output_port < 0) continue;
      int const input = input_port * _lanes + lane;
      map<int, Flit *>::iterator arrival = _arrivals.find(input);
      assert(arrival != _arrivals.end());
      Flit *f = arrival->second;
      int const output = output_port * _lanes + lane;
      assert(_OutputFor(f, input) == output);
      assert(f->head && f->tail && (f->vc >= 0) && (f->vc < _vcs));

      _QueueCredit(input, f->vc, f->voq_reservation_type,
                   f->voq_reservation_bank);
      ++_port_telemetry[output_port].request_cycles;
      _RecordPortGrant(output_port, f);
      _Trace("S0_BYPASS", f, input, output, "RETURN_BYPASS_LANDING");
      if(!_ideal_output) {
        assert(_downstream[output]->IsAvailableFor(0));
        _downstream[output]->TakeBuffer(0, f->pid);
        _downstream[output]->SendingFlit(f);
      }
      ++f->hops;
      Entry entry = { f, GetSimTime(), f->voq_reservation_bank,
                      f->voq_reservation_type, true };
      PendingRead send = { GetSimTime(), input, output, entry, true };
      _output_buffer[output].push(send);
#ifdef TRACK_FLOWS
      ++_received_flits[f->cl][input];
      ++_sent_flits[f->cl][output];
#endif
      _arrivals.erase(arrival);
    }
  }
}

void LaneVOQRouter::_CompleteReads()
{
  while(!_read_pipe.empty() &&
        (_read_pipe.front().ready_time <= GetSimTime())) {
    PendingRead const read = _read_pipe.front();
    int const input_port = read.input / _lanes;
    --_occupancy[input_port];
    if(_vc_sharing) {
      int const vc = read.entry.flit->vc;
      _QueueCredit(read.input, vc);
      _Trace(_read_latency == 1 ? "S2_READ_DONE" :
             (_read_latency == 3 ? "S4_READ_DONE" : "S3_READ_DONE"),
             read.entry.flit, read.input, read.output,
             "RETURN_VC_UNTAGGED");
      _output_buffer[read.output].push(read);
      _read_pipe.pop_front();
      continue;
    }
    bool return_lane = false;
    int returned_type = -1;
    int returned_bank = -1;
    if(_lane_credit_first && (_withheld_lane[read.input] > 0)) {
      --_withheld_lane[read.input];
      if(_banked) {
        returned_type = read.entry.reservation_type;
        returned_bank = read.entry.bank;
        if(returned_type == 0)
          ++_private_reserved[input_port][returned_bank];
        else
          ++_shared_reserved[input_port][returned_bank];
      }
      _QueueCredit(read.input, read.entry.flit->vc, returned_type, returned_bank);
      return_lane = true;
    } else if(_borrowed_shared[read.input] > 0) {
      --_borrowed_shared[read.input];
      assert(_shared_free[input_port] < _shared_capacity);
      ++_shared_free[input_port];
      if(_banked) {
        if(read.entry.reservation_type == 0)
          ++_private_unreserved[input_port][read.entry.bank];
        else
          ++_shared_unreserved[input_port][read.entry.bank];
      }
    } else {
      assert(_withheld_lane[read.input] > 0);
      --_withheld_lane[read.input];
      if(_banked) {
        returned_type = read.entry.reservation_type;
        returned_bank = read.entry.bank;
        if(returned_type == 0)
          ++_private_reserved[input_port][returned_bank];
        else
          ++_shared_reserved[input_port][returned_bank];
      }
      _QueueCredit(read.input, read.entry.flit->vc, returned_type, returned_bank);
      return_lane = true;
    }
    _Trace(_read_latency == 1 ? "S2_READ_DONE" :
           (_read_latency == 3 ? "S4_READ_DONE" : "S3_READ_DONE"),
           read.entry.flit, read.input, read.output,
           return_lane ? (_lane_credit_first ? "RETURN_LANE_EAGER"
                                             : "RETURN_LANE_AFTER_DEBT_ZERO")
                       : (_lane_credit_first ? "REPLENISH_SHARED_NO_WITHHELD"
                                             : "REPLENISH_SHARED_STRICT"));
    _output_buffer[read.output].push(read);
    _read_pipe.pop_front();
  }
}

void LaneVOQRouter::_Arbitrate()
{
  _BeginPortArbitrationTelemetry();
  if(_banked && (_allocator_policy == "max_size")) {
    for(int lane = 0; lane < _lanes; ++lane) {
      vector<vector<int> > edges(_ports);
      vector<vector<int> > selected_vc(_ports, vector<int>(_ports, -1));
      for(int input_port = 0; input_port < _ports; ++input_port) {
        int const input = input_port * _lanes + lane;
        for(int output_offset = 0; output_offset < _ports; ++output_offset) {
          int const output_port =
              (GetSimTime() + lane + input_port + output_offset) % _ports;
          if(output_port == input_port) continue;
          int const output = output_port * _lanes + lane;
          if(!_ideal_output && _downstream[output]->IsFullFor(0)) continue;
          for(int offset = 0; offset < _vcs; ++offset) {
            int const vc = (_vc_rr[input][output_port] + offset) % _vcs;
            if(_voq[input][output_port][vc].empty()) continue;
            Entry const &entry = _voq[input][output_port][vc].front();
            if(entry.payload_ready && entry.ready_time <= GetSimTime()) {
              selected_vc[input_port][output_port] = vc;
              edges[input_port].push_back(output_port);
              break;
            }
          }
        }
      }

      vector<int> output_to_input(_ports, -1);
      for(int input_offset = 0; input_offset < _ports; ++input_offset) {
        int const input_port =
            (GetSimTime() + lane + input_offset) % _ports;
        vector<bool> seen_output(_ports, false);
        _MaximumAugment(input_port, edges, seen_output, output_to_input);
      }

      for(int output_port = 0; output_port < _ports; ++output_port) {
        int const input_port = output_to_input[output_port];
        if(input_port < 0) continue;
        int const input = input_port * _lanes + lane;
        int const output = output_port * _lanes + lane;
        int const vc = selected_vc[input_port][output_port];
        assert(vc >= 0);
        Entry entry = _voq[input][output_port][vc].front();
        _voq[input][output_port][vc].pop_front();
        _vc_rr[input][output_port] = (vc + 1) % _vcs;
        _RecordPortGrant(output_port, entry.flit);
        _Trace("S1_MATCH", entry.flit, input, output, "MAX_SIZE");
        if(!_ideal_output) {
          assert(_downstream[output]->IsAvailableFor(0));
          _downstream[output]->TakeBuffer(0, entry.flit->pid);
          _downstream[output]->SendingFlit(entry.flit);
        }
        ++entry.flit->hops;
        PendingRead read = { GetSimTime() + _read_latency,
                             input, output, entry, false };
        _read_pipe.push_back(read);
        ++_bank_read_requests;
        ++_bank_read_matches;
#ifdef TRACK_FLOWS
        --_stored_flits[entry.flit->cl][input];
        ++_sent_flits[entry.flit->cl][output];
#endif
      }
    }
    _FinishPortArbitrationTelemetry();
    return;
  }

  if(_banked) {
    struct Proposal {
      int lane;
      int input_port;
      int output_port;
      int bank;
      int vc;
      int grant_slot;
    };
    vector<bool> input_matched(_inputs, false);
    vector<bool> output_matched(_outputs, false);
    vector<vector<bool> > bank_used(_ports, vector<bool>(_banks, false));

    for(int iteration = 0; iteration < _alloc_iters; ++iteration) {
      vector<Proposal> proposals;
      for(int lane = 0; lane < _lanes; ++lane) {
        vector<int> grants(_ports, -1);
        vector<int> grant_slots(_ports, -1);
        for(int output_port = 0; output_port < _ports; ++output_port) {
          int const output = output_port * _lanes + lane;
          if(output_matched[output]) continue;
          int const candidates = (_grant_policy == "weighted" &&
                                  !_grant_schedules.empty()) ?
              _grant_schedules[output_port].size() : _ports;
          for(int offset = 0; offset < candidates; ++offset) {
            int input_port, grant_slot = -1;
            if((_grant_policy == "weighted") && !_grant_schedules.empty()) {
              vector<int> const &schedule = _grant_schedules[output_port];
              grant_slot = (_bank_weighted_gptr[lane][output_port] + offset) %
                           schedule.size();
              input_port = schedule[grant_slot];
            } else {
              input_port = (_bank_gptr[lane][output_port] + offset) % _ports;
            }
            int const input = input_port * _lanes + lane;
            if(input_matched[input] || (output_port == input_port)) continue;
            int selected_vc = -1;
            for(int voff = 0; voff < _vcs; ++voff) {
              int const vc = (_vc_rr[input][output_port] + voff) % _vcs;
              if(_voq[input][output_port][vc].empty()) continue;
              Entry const &candidate = _voq[input][output_port][vc].front();
              if(candidate.payload_ready &&
                 !bank_used[input_port][candidate.bank] &&
                 candidate.ready_time <= GetSimTime()) {
                selected_vc = vc;
                break;
              }
            }
            if(selected_vc < 0 ||
               (!_ideal_output && _downstream[output]->IsFullFor(0))) continue;
            grants[output_port] = input_port;
            grant_slots[output_port] = grant_slot;
            break;
          }
        }
        for(int input_port = 0; input_port < _ports; ++input_port) {
          int const input = input_port * _lanes + lane;
          if(input_matched[input]) continue;
          for(int offset = 0; offset < _ports; ++offset) {
            int const output_port =
                (_bank_aptr[lane][input_port] + offset) % _ports;
            if(grants[output_port] != input_port) continue;
            int selected_vc = -1;
            for(int voff = 0; voff < _vcs; ++voff) {
              int const vc = (_vc_rr[input][output_port] + voff) % _vcs;
              if(!_voq[input][output_port][vc].empty() &&
                 _voq[input][output_port][vc].front().payload_ready &&
                 _voq[input][output_port][vc].front().ready_time <= GetSimTime()) {
                selected_vc = vc; break;
              }
            }
            assert(selected_vc >= 0);
            Proposal proposal = { lane, input_port, output_port,
                 _voq[input][output_port][selected_vc].front().bank, selected_vc,
                 grant_slots[output_port] };
            proposals.push_back(proposal);
            ++_bank_read_requests;
            break;
          }
        }
      }

      vector<bool> winner(proposals.size(), false);
      for(int port = 0; port < _ports; ++port) {
        for(int bank = 0; bank < _banks; ++bank) {
          int contenders = 0;
          int selected = -1;
          for(int offset = 0; offset < _lanes; ++offset) {
            int const wanted_lane =
                (_bank_read_rr[port][bank] + offset) % _lanes;
            for(size_t p = 0; p < proposals.size(); ++p) {
              if((proposals[p].input_port == port) &&
                 (proposals[p].bank == bank)) {
                if(proposals[p].lane == wanted_lane && selected < 0)
                  selected = p;
              }
            }
          }
          for(size_t p = 0; p < proposals.size(); ++p)
            if((proposals[p].input_port == port) &&
               (proposals[p].bank == bank)) ++contenders;
          if(selected >= 0) {
            winner[selected] = true;
            _bank_read_rr[port][bank] =
                (proposals[selected].lane + 1) % _lanes;
          }
          if(contenders > 1) _bank_read_conflicts += contenders - 1;
        }
      }

      int committed = 0;
      for(size_t p = 0; p < proposals.size(); ++p) {
        if(!winner[p]) continue;
        Proposal const &proposal = proposals[p];
        int const input = proposal.input_port * _lanes + proposal.lane;
        int const output = proposal.output_port * _lanes + proposal.lane;
        assert(!input_matched[input] && !output_matched[output]);
        assert(!bank_used[proposal.input_port][proposal.bank]);
        Entry entry = _voq[input][proposal.output_port][proposal.vc].front();
        _voq[input][proposal.output_port][proposal.vc].pop_front();
        _vc_rr[input][proposal.output_port] = (proposal.vc + 1) % _vcs;
        _RecordPortGrant(proposal.output_port, entry.flit);
        _Trace("S1_MATCH", entry.flit, input, output, "BANK_OK");
        if(!_ideal_output) {
          assert(_downstream[output]->IsAvailableFor(0));
          _downstream[output]->TakeBuffer(0, entry.flit->pid);
          _downstream[output]->SendingFlit(entry.flit);
        }
        ++entry.flit->hops;
        PendingRead read = { GetSimTime() + _read_latency,
                             input, output, entry, false };
        _read_pipe.push_back(read);
        input_matched[input] = true;
        output_matched[output] = true;
        bank_used[proposal.input_port][proposal.bank] = true;
        if(iteration == 0) {
          if((_grant_policy == "weighted") && (proposal.grant_slot >= 0)) {
            _bank_weighted_gptr[proposal.lane][proposal.output_port] =
                (proposal.grant_slot + 1) %
                _grant_schedules[proposal.output_port].size();
          } else {
            _bank_gptr[proposal.lane][proposal.output_port] =
                (proposal.input_port + 1) % _ports;
          }
          _bank_aptr[proposal.lane][proposal.input_port] =
              (proposal.output_port + 1) % _ports;
        }
        ++_bank_read_matches;
        ++committed;
#ifdef TRACK_FLOWS
        --_stored_flits[entry.flit->cl][input];
        ++_sent_flits[entry.flit->cl][output];
#endif
      }
      if(committed == 0) break;
    }
    _FinishPortArbitrationTelemetry();
    return;
  }

  for(int lane = 0; lane < _lanes; ++lane) {
    Allocator *allocator = _allocators[lane];
    allocator->Clear();
    for(int input_port = 0; input_port < _ports; ++input_port) {
      int const input = input_port * _lanes + lane;
      for(int output_port = 0; output_port < _ports; ++output_port) {
        if(output_port == input_port) continue;
        int selected_vc = -1;
        for(int voff = 0; voff < _vcs; ++voff) {
          int const vc = (_vc_rr[input][output_port] + voff) % _vcs;
          if(!_voq[input][output_port][vc].empty()) { selected_vc = vc; break; }
        }
        if(selected_vc < 0) continue;
        Entry const &entry = _voq[input][output_port][selected_vc].front();
        int const output = output_port * _lanes + lane;
        if(entry.payload_ready && (entry.ready_time <= GetSimTime()) &&
           (_ideal_output || !_downstream[output]->IsFullFor(0))) {
          allocator->AddRequest(input_port, output_port, output_port);
        }
      }
    }
    allocator->Allocate();
    for(int input_port = 0; input_port < _ports; ++input_port) {
      int const output_port = allocator->OutputAssigned(input_port);
      if(output_port < 0) continue;
      int const input = input_port * _lanes + lane;
      int const output = output_port * _lanes + lane;
      int selected_vc = -1;
      for(int voff = 0; voff < _vcs; ++voff) {
        int const vc = (_vc_rr[input][output_port] + voff) % _vcs;
        if(!_voq[input][output_port][vc].empty() &&
           _voq[input][output_port][vc].front().payload_ready &&
           _voq[input][output_port][vc].front().ready_time <= GetSimTime()) {
          selected_vc = vc; break;
        }
      }
      assert(selected_vc >= 0);
      Entry entry = _voq[input][output_port][selected_vc].front();
      _voq[input][output_port][selected_vc].pop_front();
      _vc_rr[input][output_port] = (selected_vc + 1) % _vcs;
      _RecordPortGrant(output_port, entry.flit);
      _Trace("S1_MATCH", entry.flit, input, output, "NONE");
      if(!_ideal_output) {
        assert(_downstream[output]->IsAvailableFor(0));
        _downstream[output]->TakeBuffer(0, entry.flit->pid);
        _downstream[output]->SendingFlit(entry.flit);
      }
      ++entry.flit->hops;
      PendingRead read = { GetSimTime() + _read_latency,
                           input, output, entry, false };
      _read_pipe.push_back(read);
#ifdef TRACK_FLOWS
      --_stored_flits[entry.flit->cl][input];
      ++_sent_flits[entry.flit->cl][output];
#endif
    }
  }
  _FinishPortArbitrationTelemetry();
}

void LaneVOQRouter::_InternalStep()
{
  _CompleteReads();
  _Arbitrate();
  _BypassArrivals();
  _EnqueueArrivals();
  _ScheduleWrites();
  _CheckInvariants();
}

void LaneVOQRouter::WriteOutputs()
{
  for(int output = 0; output < _outputs; ++output) {
    if(!_output_buffer[output].empty()) {
      PendingRead const send = _output_buffer[output].front();
      _output_buffer[output].pop();
      _RecordPortDeparture(output / _lanes, send.entry.flit);
      if(send.bypass) {
        _Trace("S3_BYPASS_SEND", send.entry.flit, send.input, output,
               "CREDIT_QUEUED_IN_S0");
        _output_channels[output]->Send(send.entry.flit);
        continue;
      }
      _Trace(_read_latency == 1 ? "S3_SEND" :
             (_read_latency == 3 ? "S5_SEND" : "S4_SEND"),
             send.entry.flit, send.input, output,
             "CREDIT_HANDLED_IN_S2");
      _output_channels[output]->Send(send.entry.flit);
    }
  }
  for(int input = 0; input < _inputs; ++input) {
    if(!_credit_buffer[input].empty()) {
      Credit *c = _credit_buffer[input].front();
      _credit_buffer[input].pop();
      _input_credits[input]->Send(c);
    }
  }
}

int LaneVOQRouter::GetUsedCredit(int output) const
{
  return _downstream[output]->Occupancy();
}

int LaneVOQRouter::GetBufferOccupancy(int input) const
{
  return _occupancy[input / _lanes];
}

#ifdef TRACK_BUFFERS
int LaneVOQRouter::GetUsedCreditForClass(int output, int cl) const
{
  return _downstream[output]->OccupancyForClass(cl);
}

int LaneVOQRouter::GetBufferOccupancyForClass(int input, int cl) const
{
  (void)cl;
  return GetBufferOccupancy(input);
}
#endif

vector<int> LaneVOQRouter::UsedCredits() const
{
  vector<int> result(_outputs);
  for(int output = 0; output < _outputs; ++output)
    result[output] = _downstream[output]->OccupancyFor(0);
  return result;
}

vector<int> LaneVOQRouter::FreeCredits() const
{
  vector<int> result(_outputs);
  for(int output = 0; output < _outputs; ++output)
    result[output] = _downstream[output]->AvailableFor(0);
  return result;
}

vector<int> LaneVOQRouter::MaxCredits() const
{
  vector<int> result(_outputs);
  for(int output = 0; output < _outputs; ++output)
    result[output] = _downstream[output]->LimitFor(0);
  return result;
}

int LaneVOQRouter::LogicalPortOccupancy(int output_port) const
{
  assert(output_port >= 0 && output_port < _ports);
  int occupancy = 0;
  for(int input = 0; input < _inputs; ++input)
    for(int vc = 0; vc < _vcs; ++vc)
      occupancy += _voq[input][output_port][vc].size();
  for(deque<PendingRead>::const_iterator read = _read_pipe.begin();
      read != _read_pipe.end(); ++read)
    if((read->output / _lanes) == output_port) ++occupancy;
  return occupancy;
}

LaneVOQRouter::LogicalPortTelemetry
LaneVOQRouter::TakeLogicalPortTelemetry(int output_port)
{
  assert(output_port >= 0 && output_port < _ports);
  LogicalPortTelemetry result = _port_telemetry[output_port];
  _port_telemetry[output_port] = LogicalPortTelemetry();
  return result;
}
