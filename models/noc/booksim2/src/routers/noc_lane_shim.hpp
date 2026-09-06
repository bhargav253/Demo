#ifndef _NOC_LANE_SHIM_HPP_
#define _NOC_LANE_SHIM_HPP_

#include <deque>
#include <queue>
#include <vector>

#include "router.hpp"

class BufferState;

// Five-channel timed adapter: channel 0 is the one-lane L3 side and channels
// 1..4 are L2 lanes 0..3. Both directions can transfer concurrently.
class NocLaneShim : public Router {
  int _depth;
  int _rr;
  std::vector<std::deque<Flit *> > _queues;
  std::vector<std::queue<Flit *> > _outputs_pending;
  std::vector<std::queue<Credit *> > _credits_pending;
  std::vector<BufferState *> _downstream;
  long long _offered_l2;
  long long _sent_l3;
  long long _sent_l2;
  long long _contention_cycles;
  long long _credit_stall_cycles;
  int _high_water;
  long long _sent_from_l2[4];

  void _InternalStep();
  void _Forward(int input, int output);

public:
  NocLaneShim(Configuration const &config, Module *parent,
              std::string const &name, int id);
  virtual ~NocLaneShim();
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
  long long ContentionCycles() const { return _contention_cycles; }
  long long CreditStallCycles() const { return _credit_stall_cycles; }
  int HighWater() const { return _high_water; }
};

#endif
