#include "screen_state.h"

namespace sysmon {

bool ScreenState::onSample(uint32_t nowMs) {
  bool stale = hasSample_ && (uint32_t)(nowMs - lastMs_) > kStaleMs;
  hasSample_ = true;
  forcedOff_ = false;
  lastMs_ = nowMs;
  return stale;
}

bool ScreenState::lit(uint32_t nowMs) const {
  return hasSample_ && !forcedOff_ && (uint32_t)(nowMs - lastMs_) <= kTimeoutMs;
}

}  // namespace sysmon
