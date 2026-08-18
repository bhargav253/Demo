#ifndef _LANE_VOQ_ROUTER_HPP_
#define _LANE_VOQ_ROUTER_HPP_

#include <deque>
#include <fstream>
#include <map>
#include <queue>
#include <vector>

#include "router.hpp"
#include "routefunc.hpp"

class Allocator;
class BufferState;

class LaneVOQRouter : public Router {
public:
  struct LogicalPortTelemetry {
    long long arrivals;
    long long departures;
    long long request_cycles;
    long long grant_cycles;
    long long allocator_loss_cycles;
    long long credit_stall_cycles;
    long long queue_wait_samples;
    long long queue_wait_cycles;
    long long residence_samples;
    long long residence_cycles;

    LogicalPortTelemetry()
      : arrivals(0), departures(0), request_cycles(0), grant_cycles(0),
        allocator_loss_cycles(0), credit_stall_cycles(0),
        queue_wait_samples(0), queue_wait_cycles(0),
        residence_samples(0), residence_cycles(0) {}
  };

private:
  struct Entry {
    Flit *flit;
    int ready_time;
    int bank;
    int reservation_type;
    bool payload_ready;
  };
  struct PendingRead {
    int ready_time;
    int input;
    int output;
    Entry entry;
    bool bypass;
  };

  int _ports;
  int _lanes;
  int _private_depth;
  int _shared_capacity;
  bool _ideal_output;
  bool _lane_credit_first;
  bool _bypass_enabled;
  std::string _storage;
  std::string _bank_policy;
  bool _banked;
  bool _fixed_lane_banks;
  int _banks;
  int _bank_depth;
  int _alloc_iters;
  int _lookaside_limit;
  bool _vc_sharing;
  int _vcs;
  int _reserved_per_vc;
  std::string _allocator_policy;
  std::string _grant_policy;
  int _read_latency;
  tRoutingFunction _rf;

  std::map<int, Flit *> _arrivals;
  std::vector<std::vector<std::vector<std::deque<Entry> > > > _voq;
  std::vector<std::vector<int> > _vc_rr;
  std::vector<int> _occupancy;
  std::vector<int> _shared_free;
  std::vector<int> _borrowed_shared;
  std::vector<int> _withheld_lane;
  std::vector<std::vector<int> > _vc_shared_used;
  std::vector<std::vector<int> > _vc_withheld;
  std::vector<std::vector<int> > _vc_reserved_embedded;
  std::vector<std::vector<int> > _vc_shared_inflight;
  std::vector<int> _lane_shared_free;
  std::vector<std::vector<int> > _private_unreserved;
  std::vector<std::vector<int> > _shared_unreserved;
  std::vector<std::vector<int> > _private_reserved;
  std::vector<std::vector<int> > _shared_reserved;
  std::vector<int> _spill_rr;
  std::vector<std::vector<int> > _bank_read_rr;
  std::vector<std::vector<int> > _bank_gptr;
  std::vector<std::vector<int> > _bank_weighted_gptr;
  std::vector<std::vector<int> > _bank_aptr;
  std::vector<std::vector<int> > _grant_weights;
  std::vector<std::vector<int> > _grant_schedules;
  long long _bank_read_requests;
  long long _bank_read_conflicts;
  long long _bank_read_matches;
  long long _bank_write_count;
  int _lookaside_high_water;
  std::vector<Allocator *> _allocators;
  std::vector<Allocator *> _bypass_allocators;
  std::vector<BufferState *> _downstream;

  std::deque<PendingRead> _read_pipe;
  std::vector<std::queue<PendingRead> > _output_buffer;
  std::vector<std::queue<Credit *> > _credit_buffer;
  std::ofstream *_trace;
  std::vector<LogicalPortTelemetry> _port_telemetry;
  std::vector<int> _port_requests_this_cycle;
  std::vector<int> _port_grants_this_cycle;

  void _InternalStep();
  void _ReceiveFlits();
  void _ReceiveCredits();
  void _EnqueueArrivals();
  void _BypassArrivals();
  void _CompleteReads();
  void _Arbitrate();
  void _QueueCredit(int input, int vc = 0, int reservation_type = -1,
                    int reservation_bank = -1);
  int _ReserveSharedBank(int input);
  void _ScheduleWrites();
  void _CheckInvariants() const;
  void _Trace(char const *event, Flit const *flit, int input, int output,
              char const *credit_action);
  int _OutputFor(Flit const *flit, int input) const;
  void _BeginPortArbitrationTelemetry();
  void _FinishPortArbitrationTelemetry();
  void _RecordPortGrant(int output_port, Flit const *flit);
  void _RecordPortDeparture(int output_port, Flit const *flit);

public:
  LaneVOQRouter(Configuration const &config, Module *parent,
                std::string const &name, int id, int inputs, int outputs,
                int logical_ports = -1, int lanes = -1,
                int total_buffer_size = -1);
  virtual ~LaneVOQRouter();

  virtual void AddOutputChannel(FlitChannel *channel,
                                CreditChannel *backchannel);
  virtual void ReadInputs();
  virtual void WriteOutputs();

  virtual int GetUsedCredit(int output) const;
  virtual int GetBufferOccupancy(int input) const;
#ifdef TRACK_BUFFERS
  virtual int GetUsedCreditForClass(int output, int cl) const;
  virtual int GetBufferOccupancyForClass(int input, int cl) const;
#endif
  virtual std::vector<int> UsedCredits() const;
  virtual std::vector<int> FreeCredits() const;
  virtual std::vector<int> MaxCredits() const;
  int NumLogicalPorts() const { return _ports; }
  int LogicalPortOccupancy(int output_port) const;
  LogicalPortTelemetry TakeLogicalPortTelemetry(int output_port);
  void SetGrantWeights(std::vector<std::vector<int> > const &weights);
};

#endif
