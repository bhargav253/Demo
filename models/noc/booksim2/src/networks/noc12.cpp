#include "booksim.hpp"

#include <cassert>
#include <map>

#include "noc12.hpp"
#include "noc12_map.hpp"
#include "routefunc.hpp"
#include "routers/lane_voq_router.hpp"
#include "routers/noc_lane_shim.hpp"

using namespace std;

namespace {
vector<map<int,int> > gNoc12Routes;
int FlatPort(int router,int port,int lane) {
  return port*Noc12Map::RouterLanes(router)+lane;
}
long long Activity(FlitChannel const *channel) {
  vector<int> const &a=channel->GetActivity(); long long total=0;
  for(size_t i=0;i<a.size();++i) total+=a[i];
  return total;
}
void min_noc12(Router const *router,Flit const *flit,int in_channel,
               OutputSet *outputs,bool inject) {
  (void)in_channel; outputs->Clear();
  if(inject){outputs->AddRange(-1,0,gNumVCs-1);return;}
  assert(router); int const id=router->GetID();
  map<int,int>::const_iterator const it=gNoc12Routes[id].find(flit->dest);
  assert(it!=gNoc12Routes[id].end()); outputs->AddRange(it->second,flit->vc,flit->vc);
}
}

Noc12::Noc12(Configuration const &config,string const &name)
  : Network(config,name),_telemetry(NULL),
    _telemetry_interval(config.GetInt("noc_telemetry_interval")) {
  _ComputeSize(config); _Alloc(); _BuildNet(config); _BuildRoutingTable();
  string const file=config.GetStr("noc_telemetry_file");
  if(!file.empty()&&_telemetry_interval>0) {
    _telemetry=new ofstream(file.c_str()); assert(_telemetry->good());
    *_telemetry << "cycle,kind,id,name,port,arrivals,departures,occupancy,"
      "request_cycles,grant_cycles,allocator_loss_cycles,contention_cycles,"
      "credit_stall_cycles,queue_wait_samples,queue_wait_cycles,"
      "residence_samples,residence_cycles,avg_queue_wait,avg_residence\n";
  }
  _previous_router_in.assign(_size,0); _previous_router_out.assign(_size,0);
  _previous_channel.assign(_channels,0); _previous_inject.assign(_nodes,0);
  _previous_eject.assign(_nodes,0);
}
Noc12::~Noc12(){delete _telemetry;}
void Noc12::_ComputeSize(Configuration const &config){(void)config;Noc12Map::Validate();
  _size=Noc12Map::kRouterCount;_nodes=Noc12Map::kNodeCount;
  _channels=Noc12Map::InternalLinks().size();}

void Noc12::_BuildNet(Configuration const &config) {
  vector<vector<FlitChannel *> > inputs(_size),outputs(_size);
  vector<vector<CreditChannel *> > ic(_size),oc(_size);
  for(int r=0;r<_size;++r){int n=Noc12Map::RouterPorts(r)*Noc12Map::RouterLanes(r);
    inputs[r].assign(n,NULL);outputs[r].assign(n,NULL);ic[r].assign(n,NULL);oc[r].assign(n,NULL);}
  vector<Noc12Link> const links=Noc12Map::InternalLinks();
  for(int c=0;c<_channels;++c){Noc12Link const &l=links[c];
    int s=FlatPort(l.source_router,l.source_port,l.source_lane);
    int d=FlatPort(l.sink_router,l.sink_port,l.sink_lane);
    assert(!outputs[l.source_router][s]&&!inputs[l.sink_router][d]);
    outputs[l.source_router][s]=_chan[c];oc[l.source_router][s]=_chan_cred[c];
    inputs[l.sink_router][d]=_chan[c];ic[l.sink_router][d]=_chan_cred[c];
    _chan[c]->SetLatency(1);_chan_cred[c]->SetLatency(1);}
  vector<Noc12Endpoint> const eps=Noc12Map::Endpoints();
  for(size_t i=0;i<eps.size();++i){Noc12Endpoint const &e=eps[i];
    int f=FlatPort(e.router,e.port,e.router_lane);
    assert(!inputs[e.router][f]&&!outputs[e.router][f]);
    inputs[e.router][f]=_inject[e.node];ic[e.router][f]=_inject_cred[e.node];
    outputs[e.router][f]=_eject[e.node];oc[e.router][f]=_eject_cred[e.node];
    _inject[e.node]->SetLatency(1);_inject_cred[e.node]->SetLatency(1);
    _eject[e.node]->SetLatency(1);_eject_cred[e.node]->SetLatency(1);}
  for(int r=0;r<_size;++r){string const name=Noc12Map::RouterName(r);
    int const ports=Noc12Map::RouterPorts(r),lanes=Noc12Map::RouterLanes(r);
    if(r<Noc12Map::kL2Base) _routers[r]=new LaneVOQRouter(config,this,name,r,32,32,8,4,48);
    else if(r<Noc12Map::kL3Base) _routers[r]=new LaneVOQRouter(config,this,name,r,36,36,9,4,48);
    else if(r<Noc12Map::kShimBase) _routers[r]=new LaneVOQRouter(config,this,name,r,5,5,5,1,12);
    else _routers[r]=new NocLaneShim(config,this,name,r);
    if(r<Noc12Map::kL3Base&&config.GetStr("voq_grant_policy")=="weighted") {
      LaneVOQRouter *core=dynamic_cast<LaneVOQRouter *>(_routers[r]);assert(core);
      core->SetGrantWeights(Noc12Map::GrantWeights(r));}
    _timed_modules.push_back(_routers[r]); int const n=ports*lanes;
    for(int i=0;i<n;++i){assert(inputs[r][i]&&ic[r][i]);_routers[r]->AddInputChannel(inputs[r][i],ic[r][i]);}
    for(int o=0;o<n;++o){assert(outputs[r][o]&&oc[r][o]);_routers[r]->AddOutputChannel(outputs[r][o],oc[r][o]);}
  }
}
void Noc12::_BuildRoutingTable(){gNoc12Routes.assign(_size,map<int,int>());
  for(int r=0;r<Noc12Map::kShimBase;++r)for(int n=0;n<_nodes;++n)
    gNoc12Routes[r][n]=Noc12Map::RoutePort(r,n);}
void Noc12::RegisterRoutingFunctions(){gRoutingFunctionMap["min_noc12"]=&min_noc12;}

void Noc12::WriteOutputs() {
  Network::WriteOutputs(); if(!_telemetry||(GetSimTime()%_telemetry_interval))return;
  for(int r=0;r<_size;++r){int const count=Noc12Map::RouterPorts(r)*Noc12Map::RouterLanes(r);
    long long in=0,out=0;int occupancy=0;
    for(int i=0;i<count;++i){in+=Activity(_routers[r]->GetInputChannel(i));out+=Activity(_routers[r]->GetOutputChannel(i));}
    long long contention=0,stalls=0;NocLaneShim const *shim=dynamic_cast<NocLaneShim const *>(_routers[r]);
    if(shim){for(int i=0;i<count;++i)occupancy+=shim->GetBufferOccupancy(i);
      contention=shim->ContentionCycles();stalls=shim->CreditStallCycles();}
    else for(int p=0;p<Noc12Map::RouterPorts(r);++p)
      occupancy+=_routers[r]->GetBufferOccupancy(p*Noc12Map::RouterLanes(r));
    *_telemetry<<GetSimTime()<<','<<(shim?"shim":"router")<<','<<r<<','
      <<Noc12Map::RouterName(r)<<",-1,"<<in-_previous_router_in[r]<<','
      <<out-_previous_router_out[r]<<','<<occupancy<<",0,0,0,"<<contention<<','
      <<stalls<<",0,0,0,0,0,0\n";
    _previous_router_in[r]=in;_previous_router_out[r]=out;
    LaneVOQRouter *voq=dynamic_cast<LaneVOQRouter *>(_routers[r]);
    if(voq)for(int port=0;port<voq->NumLogicalPorts();++port){
      LaneVOQRouter::LogicalPortTelemetry const p=voq->TakeLogicalPortTelemetry(port);
      double aq=p.queue_wait_samples?double(p.queue_wait_cycles)/p.queue_wait_samples:0;
      double ar=p.residence_samples?double(p.residence_cycles)/p.residence_samples:0;
      *_telemetry<<GetSimTime()<<",port,"<<r<<','<<Noc12Map::RouterName(r)<<','<<port<<','
        <<p.arrivals<<','<<p.departures<<','<<voq->LogicalPortOccupancy(port)<<','
        <<p.request_cycles<<','<<p.grant_cycles<<','<<p.allocator_loss_cycles
        <<",0,"<<p.credit_stall_cycles<<','<<p.queue_wait_samples<<','
        <<p.queue_wait_cycles<<','<<p.residence_samples<<','<<p.residence_cycles
        <<','<<aq<<','<<ar<<'\n';}
  }
  vector<Noc12Link> const links=Noc12Map::InternalLinks();
  for(int c=0;c<_channels;++c){long long const active=Activity(_chan[c]);
    *_telemetry<<GetSimTime()<<",link,"<<c<<','<<links[c].name<<",-1,0,"
      <<active-_previous_channel[c]<<",0,0,0,0,0,0,0,0,0,0,0,0\n";
    _previous_channel[c]=active;}
  vector<Noc12Endpoint> const eps=Noc12Map::Endpoints();
  for(size_t i=0;i<eps.size();++i){int const node=eps[i].node;
    long long const injected=Activity(_inject[node]),ejected=Activity(_eject[node]);
    *_telemetry<<GetSimTime()<<",endpoint,"<<node<<','<<eps[i].name<<",-1,"
      <<injected-_previous_inject[node]<<','<<ejected-_previous_eject[node]
      <<",0,0,0,0,0,0,0,0,0,0,0,0\n";
    _previous_inject[node]=injected;_previous_eject[node]=ejected;}
  _telemetry->flush();
}
