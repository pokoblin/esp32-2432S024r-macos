#include "breathe.h"

#include <math.h>

namespace sysmon {

namespace {
constexpr uint32_t kPeriodMs = 3000;
}

uint8_t breatheLevel(uint32_t nowMs) {
  float phase = (float)(nowMs % kPeriodMs) / kPeriodMs;
  float v = (1.0f - cosf(2.0f * (float)M_PI * phase)) / 2.0f * 255.0f;
  return (uint8_t)lroundf(v);
}

Rgb bannerLedColor(BannerKind k) {
  switch (k) {
    case BannerKind::FocusDone: return {0, 255, 40};     // 绿
    case BannerKind::BreakEnded: return {255, 50, 20};   // 番茄红
    case BannerKind::Sit: return {255, 110, 0};          // 橙
    case BannerKind::Water: return {0, 150, 255};        // 蓝
    default: return {0, 0, 0};
  }
}

Rgb scaleRgb(Rgb c, uint8_t level) {
  return {(uint8_t)(c.r * level / 255), (uint8_t)(c.g * level / 255), (uint8_t)(c.b * level / 255)};
}

}  // namespace sysmon
