// 横幅出现时 RGB 灯的呼吸：颜色按横幅种类，亮度按时间平滑往返。
#pragma once
#include <stdint.h>

#include "timer_protocol.h"

namespace sysmon {

struct Rgb {
  uint8_t r, g, b;
};

// 周期 3000ms 的 0..255 往返：整周期处为 0，半周期处为 255。
uint8_t breatheLevel(uint32_t nowMs);

// 横幅色的近似；None 为全灭。
Rgb bannerLedColor(BannerKind k);

// 每个分量 * level / 255。
Rgb scaleRgb(Rgb c, uint8_t level);

}  // namespace sysmon
