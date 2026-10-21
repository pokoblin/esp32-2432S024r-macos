// 最近 5 分钟的网速历史（每 2 秒一个点，共 150 个），定长环形缓冲。
#pragma once
#include <stdint.h>

namespace sysmon {

class History {
 public:
  static constexpr int kCapacity = 150;

  void push(uint32_t rx, uint32_t tx);
  void clear() { head_ = 0; size_ = 0; }
  int size() const { return size_; }
  // i = 0 是最旧的点
  uint32_t rxAt(int i) const { return rx_[index(i)]; }
  uint32_t txAt(int i) const { return tx_[index(i)]; }
  // 当前所有点里 rx、tx 的最大值；没有数据时为 0
  uint32_t peak() const;

 private:
  int index(int i) const { return (head_ + kCapacity - size_ + i) % kCapacity; }

  uint32_t rx_[kCapacity] = {};
  uint32_t tx_[kCapacity] = {};
  int head_ = 0;  // 下一个写入位置
  int size_ = 0;
};

}  // namespace sysmon
