#include "screen_state.h"

namespace sysmon {

bool ScreenState::onSample(uint32_t nowMs) {
  bool stale = hasSample_ && (stale_ || (uint32_t)(nowMs - lastMs_) > kStaleMs);
  hasSample_ = true;
  forcedOff_ = false;
  expired_ = false;
  stale_ = false;
  lastMs_ = nowMs;
  return stale;
}

void ScreenState::tick(uint32_t nowMs) {
  if (!hasSample_) return;
  uint32_t gap = nowMs - lastMs_;
  if (gap > kTimeoutMs) expired_ = true;
  if (gap > kStaleMs) stale_ = true;
}

bool ScreenState::lit(uint32_t nowMs) const {
  return hasSample_ && !forcedOff_ && !expired_ && (uint32_t)(nowMs - lastMs_) <= kTimeoutMs;
}

}  // namespace sysmon
