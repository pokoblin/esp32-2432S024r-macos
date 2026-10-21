#pragma once
#include <stdint.h>

namespace sysmon {

// 触摸点击防抖：只有从松开变成按下、且距上一次点击不少于 kMinGapMs，才算一次点击。
class TapDetector {
 public:
  static constexpr uint32_t kMinGapMs = 300;
  bool update(bool pressed, uint32_t nowMs);

 private:
  bool wasPressed_ = false;
  bool hasTapped_ = false;
  uint32_t lastTapMs_ = 0;
};

}  // namespace sysmon
