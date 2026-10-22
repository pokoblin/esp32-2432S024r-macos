// 板子背面的 RGB 灯：共阳，低电平点亮（2026-10-22 实测：GPIO4 红、GPIO16 蓝、GPIO17 绿）。
// 用 analogWrite 调亮度，值取反；255 时 Arduino 内核会输出满占空比的高电平，灯全灭。
#pragma once
#include <Arduino.h>

#include "breathe.h"

namespace rgbled {

constexpr int PIN_R = 4, PIN_G = 17, PIN_B = 16;

inline void write(sysmon::Rgb c) {
  analogWrite(PIN_R, 255 - c.r);
  analogWrite(PIN_G, 255 - c.g);
  analogWrite(PIN_B, 255 - c.b);
}

// 开机先全部拉高（灭）
inline void begin() {
  for (int pin : {PIN_R, PIN_G, PIN_B}) {
    pinMode(pin, OUTPUT);
    digitalWrite(pin, HIGH);
  }
  write({0, 0, 0});
}

}  // namespace rgbled
