#include "booksim.hpp"

#include <algorithm>
#include <cassert>
#include <sstream>

#include "buffer_state.hpp"
#include "noc_lane_shim.hpp"

using namespace std;

NocLaneShim::NocLaneShim(Configuration const &config, Module *parent,
                         string const &name, int id)
  : Router(config, parent, name, id, 5, 5),
    _depth(config.GetInt("vc_buf_size")), _rr(0),
    _queues(5), _outputs_pending(5), _credits_pending(5),
    _offered_l2(0), _sent_l3(0), _sent_l2(0),
    _contention_cycles(0), _credit_stall_cycles(0), _high_water(0) {
  assert(_depth > 0);
  for(int lane = 0; lane < 4; ++lane) _sent_from_l2[lane] = 0;
  for(int output = 0; output < 5; ++output) {
    ostringstream n;
    n << "shim_downstream_" << output;
    _downstream.push_back(new BufferState(config, this, n.str()));
  }
}

NocLaneShim::~NocLaneShim() {
  if(_offered_l2 || _sent_l3 || _sent_l2 || _credit_stall_cycles) {
    cout << "SHIM_STATS shim=" << _id
         << " offered_l2=" << _offered_l2
         << " sent_l3=" << _sent_l3
         << " sent_l2=" << _sent_l2
         << " contention_cycles=" << _contention_cycles
         << " credit_stall_cycles=" << _credit_stall_cycles
         << " high_water=" << _high_water
         << " lane_sends=[" << _sent_from_l2[0] << ';' << _sent_from_l2[1]
         << ';' << _sent_from_l2[2] << ';' << _sent_from_l2[3] << "]" << endl;
  }
  for(size_t i = 0; i < _downstream.size(); ++i) delete _downstream[i];
}

void NocLaneShim::AddOutputChannel(FlitChannel *channel,
                                   CreditChannel *backchannel) {
  int const output = _output_channels.size();
  _downstream[output]->SetMinLatency(channel->GetLatency() +
                                     backchannel->GetLatency() + 1);
  Router::AddOutputChannel(channel, backchannel);
}

void NocLaneShim::ReadInputs() {
  for(int input = 0; input < 5; ++input) {
    Flit *f = _input_channels[input]->Receive();
    if(f) {
      assert(static_cast<int>(_queues[input].size()) < _depth);
      _queues[input].push_back(f);
      if(input > 0) ++_offered_l2;
      _high_water = max(_high_water, static_cast<int>(_queues[input].size()));
    }
  }
  for(int output = 0; output < 5; ++output) {
    Credit *c = _output_credits[output]->Receive();
    if(c) {
      _downstream[output]->ProcessCredit(c);
      c->Free();
    }
  }
}

void NocLaneShim::_Forward(int input, int output) {
  Flit *f = _queues[input].front();
  _queues[input].pop_front();
  assert(_downstream[output]->IsAvailableFor(f->vc));
  _downstream[output]->TakeBuffer(f->vc, f->pid);
  _downstream[output]->SendingFlit(f);
  _outputs_pending[output].push(f);
  Credit *credit = Credit::New();
  credit->vc.insert(f->vc);
  credit->voq_reservation_type = -1;
  credit->voq_reservation_bank = -1;
  _credits_pending[input].push(credit);
  ++f->hops;
}

void NocLaneShim::_InternalStep() {
  // L3 -> one address-selected L2 lane.
  if(!_queues[0].empty()) {
    Flit *f = _queues[0].front();
    assert(f->noc_lane >= 0 && f->noc_lane < 4);
    int const output = 1 + f->noc_lane;
    if(!_downstream[output]->IsFullFor(f->vc)) {
      _Forward(0, output);
      ++_sent_l2;
    } else {
      ++_credit_stall_cycles;
    }
  }

  // Four L2 lanes -> one L3 lane, round robin. This direction is independent
  // and may transfer in the same cycle as L3 -> L2.
  int contenders = 0;
  for(int lane = 0; lane < 4; ++lane)
    if(!_queues[1 + lane].empty()) ++contenders;
  if(contenders > 1) ++_contention_cycles;
  if(contenders) {
    int selected = -1;
    for(int offset = 0; offset < 4; ++offset) {
      int const lane = (_rr + offset) % 4;
      if(!_queues[1 + lane].empty()) { selected = lane; break; }
    }
    assert(selected >= 0);
    Flit *f = _queues[1 + selected].front();
    if(!_downstream[0]->IsFullFor(f->vc)) {
      _Forward(1 + selected, 0);
      _rr = (selected + 1) % 4;
      ++_sent_l3;
      ++_sent_from_l2[selected];
    } else {
      ++_credit_stall_cycles;
    }
  }
}

void NocLaneShim::WriteOutputs() {
  for(int output = 0; output < 5; ++output)
    if(!_outputs_pending[output].empty()) {
      _output_channels[output]->Send(_outputs_pending[output].front());
      _outputs_pending[output].pop();
    }
  for(int input = 0; input < 5; ++input)
    if(!_credits_pending[input].empty()) {
      _input_credits[input]->Send(_credits_pending[input].front());
      _credits_pending[input].pop();
    }
}

int NocLaneShim::GetUsedCredit(int output) const {
  return _downstream[output]->Occupancy();
}
int NocLaneShim::GetBufferOccupancy(int input) const {
  return _queues[input].size();
}
#ifdef TRACK_BUFFERS
int NocLaneShim::GetUsedCreditForClass(int output, int cl) const {
  return _downstream[output]->OccupancyForClass(cl);
}
int NocLaneShim::GetBufferOccupancyForClass(int input, int cl) const {
  (void)cl; return GetBufferOccupancy(input);
}
#endif
vector<int> NocLaneShim::UsedCredits() const {
  vector<int> r(5); for(int i=0;i<5;++i) r[i]=_downstream[i]->Occupancy(); return r;
}
vector<int> NocLaneShim::FreeCredits() const {
  vector<int> r(5); for(int i=0;i<5;++i) r[i]=_downstream[i]->AvailableFor(0); return r;
}
vector<int> NocLaneShim::MaxCredits() const {
  vector<int> r(5); for(int i=0;i<5;++i) r[i]=_downstream[i]->LimitFor(0); return r;
}
