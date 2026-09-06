#include <cassert>
#include <iostream>
#include <set>
#include <vector>

#include "allocators/islip.hpp"

static int MatchCount(iSLIP_Sparse &allocator, int inputs)
{
  int matches = 0;
  std::set<int> outputs;
  for(int input = 0; input < inputs; ++input) {
    int const output = allocator.OutputAssigned(input);
    if(output >= 0) {
      ++matches;
      assert(outputs.insert(output).second);
      assert(allocator.InputAssigned(output) == input);
    }
  }
  return matches;
}

static void AddSecondIterationMatrix(iSLIP_Sparse &allocator)
{
  allocator.AddRequest(0, 0);
  allocator.AddRequest(0, 1);
  allocator.AddRequest(1, 0);
  allocator.AddRequest(2, 1);
}

int main()
{
  iSLIP_Sparse one(NULL, "one_iteration", 3, 2, 1);
  AddSecondIterationMatrix(one);
  one.Allocate();
  assert(MatchCount(one, 3) == 1);

  iSLIP_Sparse two(NULL, "two_iterations", 3, 2, 2);
  AddSecondIterationMatrix(two);
  two.Allocate();
  assert(MatchCount(two, 3) == 2);

  iSLIP_Sparse fairness(NULL, "fairness", 4, 1, 1);
  for(int expected = 0; expected < 4; ++expected) {
    fairness.Clear();
    for(int input = 0; input < 4; ++input)
      fairness.AddRequest(input, 0);
    fairness.Allocate();
    assert(fairness.InputAssigned(0) == expected);
  }

  // Output-side weighted RR must preserve the 1:3:2 service ratio while the
  // input accept phase remains ordinary iSLIP. All requesters are persistent.
  iSLIP_Sparse weighted(NULL, "weighted_grants", 3, 1, 1);
  std::vector<std::vector<int> > weights(3, std::vector<int>(1, 1));
  weights[1][0] = 3;
  weights[2][0] = 2;
  weighted.SetGrantWeights(weights);
  int expected[] = { 0, 1, 1, 1, 2, 2, 0, 1, 1, 1, 2, 2 };
  for(int cycle = 0; cycle < 12; ++cycle) {
    weighted.Clear();
    for(int input = 0; input < 3; ++input) weighted.AddRequest(input, 0);
    weighted.Allocate();
    assert(weighted.InputAssigned(0) == expected[cycle]);
  }

  // An inactive high-weight input must not waste the output or starve the
  // remaining default-weight requesters.
  for(int cycle = 0; cycle < 4; ++cycle) {
    weighted.Clear();
    weighted.AddRequest(0, 0);
    weighted.AddRequest(2, 0);
    weighted.Allocate();
    assert(weighted.InputAssigned(0) >= 0);
  }

  std::cout << "iSLIP unit tests passed\n";
  return 0;
}
