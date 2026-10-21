#include "history.h"

namespace sysmon {

void History::push(uint32_t rx, uint32_t tx) {
  rx_[head_] = rx;
  tx_[head_] = tx;
  head_ = (head_ + 1) % kCapacity;
  if (size_ < kCapacity) ++size_;
}

uint32_t History::peak() const {
  uint32_t m = 0;
  for (int i = 0; i < size_; ++i) {
    if (rxAt(i) > m) m = rxAt(i);
    if (txAt(i) > m) m = txAt(i);
  }
  return m;
}

}  // namespace sysmon
