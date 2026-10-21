#include <tsl/robin_map.h>

// One insert is enough. The instantiated insert_impl_with_hash returns
// {bucket_entry*, i8} and is the largest function, so AggregateReturnDemotionPass
// erases the function CBStatistics recorded before the pass pipeline.
int main() {
  tsl::robin_map<int, int> m;
  auto r = m.insert({1, 2});
  return r.second ? r.first->second : 0;
}
