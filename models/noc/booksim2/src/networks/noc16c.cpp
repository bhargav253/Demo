#include "booksim.hpp"

#include <cassert>
#include <map>

#include "noc16c.hpp"
#include "noc16c_map.hpp"
#include "routefunc.hpp"
#include "routers/lane_voq_router.hpp"
#include "routers/noc_lane_shim.hpp"

using namespace std;

namespace {
vector<map<int,int> > gNoc16CRoutes;
int FlatPort(int router,int port,int lane) {
  return port*Noc16CMap::RouterLanes(router)+lane;
}
long long Activity(FlitChannel const *channel) {
  vector<int> const &a=channel->GetActivity(); long long total=0;
  for(size_t i=0;i<a.size();++i) total+=a[i];
  return total;
}
void min_noc16c(Router const *router,Flit const *flit,int in_channel,
               OutputSet *outputs,bool inject) {
  (void)in_channel; outputs->Clear();
  if(inject){outputs->AddRange(-1,0,gNumVCs-1);return;}
  assert(router); int const id=router->GetID();
  map<int,int>::const_iterator const it=gNoc16CRoutes[id].find(flit->dest);
  assert(it!=gNoc16CRoutes[id].end()); outputs->AddRange(it->second,flit->vc,flit->vc);
}
}

Noc16C::Noc16C(Configuration const &config,string const &name)
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
Noc16C::~Noc16C(){delete _telemetry;}
void Noc16C::_ComputeSize(Configuration const &config){(void)config;Noc16CMap::Validate();
  _size=Noc16CMap::kRouterCount;_nodes=Noc16CMap::kNodeCount;
  _channels=Noc16CMap::InternalLinks().size();}

void Noc16C::_BuildNet(Configuration const &config) {
  vector<vector<FlitChannel *> > inputs(_size),outputs(_size);
  vector<vector<CreditChannel *> > ic(_size),oc(_size);
  for(int r=0;r<_size;++r){int n=Noc16CMap::RouterPorts(r)*Noc16CMap::RouterLanes(r);
    inputs[r].assign(n,NULL);outputs[r].assign(n,NULL);ic[r].assign(n,NULL);oc[r].assign(n,NULL);}
  vector<Noc16CLink> const links=Noc16CMap::InternalLinks();
  for(int c=0;c<_channels;++c){Noc16CLink const &l=links[c];
    int s=FlatPort(l.source_router,l.source_port,l.source_lane);
    int d=FlatPort(l.sink_router,l.sink_port,l.sink_lane);
    assert(!outputs[l.source_router][s]&&!inputs[l.sink_router][d]);
    outputs[l.source_router][s]=_chan[c];oc[l.source_router][s]=_chan_cred[c];
    inputs[l.sink_router][d]=_chan[c];ic[l.sink_router][d]=_chan_cred[c];
    _chan[c]->SetLatency(1);_chan_cred[c]->SetLatency(1);}
  vector<Noc16CEndpoint> const eps=Noc16CMap::Endpoints();
  for(size_t i=0;i<eps.size();++i){Noc16CEndpoint const &e=eps[i];
    int f=FlatPort(e.router,e.port,e.router_lane);
    assert(!inputs[e.router][f]&&!outputs[e.router][f]);
    inputs[e.router][f]=_inject[e.node];ic[e.router][f]=_inject_cred[e.node];
    outputs[e.router][f]=_eject[e.node];oc[e.router][f]=_eject_cred[e.node];
    _inject[e.node]->SetLatency(1);_inject_cred[e.node]->SetLatency(1);
    _eject[e.node]->SetLatency(1);_eject_cred[e.node]->SetLatency(1);}
  for(int r=0;r<_size;++r){string const name=Noc16CMap::RouterName(r);
    int const ports=Noc16CMap::RouterPorts(r),lanes=Noc16CMap::RouterLanes(r);
    if(r<Noc16CMap::kL2Base) _routers[r]=new LaneVOQRouter(config,this,name,r,32,32,8,4,48);
    else if(r<Noc16CMap::kL3Base) _routers[r]=new LaneVOQRouter(config,this,name,r,36,36,9,4,48);
    else if(r<Noc16CMap::kShimBase) _routers[r]=new LaneVOQRouter(config,this,name,r,5,5,5,1,12);
    else _routers[r]=new NocLaneShim(config,this,name,r);
    if(r<Noc16CMap::kL3Base&&config.GetStr("voq_grant_policy")=="weighted") {
      LaneVOQRouter *core=dynamic_cast<LaneVOQRouter *>(_routers[r]);assert(core);
      core->SetGrantWeights(Noc16CMap::GrantWeights(r));}
    _timed_modules.push_back(_routers[r]); int const n=ports*lanes;
    for(int i=0;i<n;++i){assert(inputs[r][i]&&ic[r][i]);_routers[r]->AddInputChannel(inputs[r][i],ic[r][i]);}
    for(int o=0;o<n;++o){assert(outputs[r][o]&&oc[r][o]);_routers[r]->AddOutputChannel(outputs[r][o],oc[r][o]);}
  }
}
void Noc16C::_BuildRoutingTable(){gNoc16CRoutes.assign(_size,map<int,int>());
  for(int r=0;r<Noc16CMap::kShimBase;++r)for(int n=0;n<_nodes;++n)
    gNoc16CRoutes[r][n]=Noc16CMap::RoutePort(r,n);}
void Noc16C::RegisterRoutingFunctions(){gRoutingFunctionMap["min_noc16c"]=&min_noc16c;}

void Noc16C::WriteOutputs() {
  Network::WriteOutputs(); if(!_telemetry||(GetSimTime()%_telemetry_interval))return;
  for(int r=0;r<_size;++r){int const count=Noc16CMap::RouterPorts(r)*Noc16CMap::RouterLanes(r);
    long long in=0,out=0;int occupancy=0;
    for(int i=0;i<count;++i){in+=Activity(_routers[r]->GetInputChannel(i));out+=Activity(_routers[r]->GetOutputChannel(i));}
    long long contention=0,stalls=0;NocLaneShim const *shim=dynamic_cast<NocLaneShim const *>(_routers[r]);
    if(shim){for(int i=0;i<count;++i)occupancy+=shim->GetBufferOccupancy(i);
      contention=shim->ContentionCycles();stalls=shim->CreditStallCycles();}
    else for(int p=0;p<Noc16CMap::RouterPorts(r);++p)
      occupancy+=_routers[r]->GetBufferOccupancy(p*Noc16CMap::RouterLanes(r));
    *_telemetry<<GetSimTime()<<','<<(shim?"shim":"router")<<','<<r<<','
      <<Noc16CMap::RouterName(r)<<",-1,"<<in-_previous_router_in[r]<<','
      <<out-_previous_router_out[r]<<','<<occupancy<<",0,0,0,"<<contention<<','
      <<stalls<<",0,0,0,0,0,0\n";
    _previous_router_in[r]=in;_previous_router_out[r]=out;
    LaneVOQRouter *voq=dynamic_cast<LaneVOQRouter *>(_routers[r]);
    if(voq)for(int port=0;port<voq->NumLogicalPorts();++port){
      LaneVOQRouter::LogicalPortTelemetry const p=voq->TakeLogicalPortTelemetry(port);
      double aq=p.queue_wait_samples?double(p.queue_wait_cycles)/p.queue_wait_samples:0;
      double ar=p.residence_samples?double(p.residence_cycles)/p.residence_samples:0;
      *_telemetry<<GetSimTime()<<",port,"<<r<<','<<Noc16CMap::RouterName(r)<<','<<port<<','
        <<p.arrivals<<','<<p.departures<<','<<voq->LogicalPortOccupancy(port)<<','
        <<p.request_cycles<<','<<p.grant_cycles<<','<<p.allocator_loss_cycles
        <<",0,"<<p.credit_stall_cycles<<','<<p.queue_wait_samples<<','
        <<p.queue_wait_cycles<<','<<p.residence_samples<<','<<p.residence_cycles
        <<','<<aq<<','<<ar<<'\n';}
  }
  vector<Noc16CLink> const links=Noc16CMap::InternalLinks();
  for(int c=0;c<_channels;++c){long long const active=Activity(_chan[c]);
    *_telemetry<<GetSimTime()<<",link,"<<c<<','<<links[c].name<<",-1,0,"
      <<active-_previous_channel[c]<<",0,0,0,0,0,0,0,0,0,0,0,0\n";
    _previous_channel[c]=active;}
  vector<Noc16CEndpoint> const eps=Noc16CMap::Endpoints();
  for(size_t i=0;i<eps.size();++i){int const node=eps[i].node;
    long long const injected=Activity(_inject[node]),ejected=Activity(_eject[node]);
    *_telemetry<<GetSimTime()<<",endpoint,"<<node<<','<<eps[i].name<<",-1,"
      <<injected-_previous_inject[node]<<','<<ejected-_previous_eject[node]
      <<",0,0,0,0,0,0,0,0,0,0,0,0\n";
    _previous_inject[node]=injected;_previous_eject[node]=ejected;}
  _telemetry->flush();
}
