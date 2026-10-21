#include "tap.h"

namespace sysmon {

bool TapDetector::update(bool pressed, uint32_t nowMs) {
  bool rising = pressed && !wasPressed_;
  wasPressed_ = pressed;
  if (!rising) return false;
  // 无符号减法，millis() 回绕时也成立
  if (hasTapped_ && (uint32_t)(nowMs - lastTapMs_) < kMinGapMs) return false;
  hasTapped_ = true;
  lastTapMs_ = nowMs;
  return true;
}

}  // namespace sysmon
