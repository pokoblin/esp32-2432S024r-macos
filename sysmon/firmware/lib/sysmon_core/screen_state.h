// 背光开关：超过 kTimeoutMs 没数据或收到 OFF 就熄屏，有新数据就点亮。
// 时间差都用无符号减法，millis() 回绕后依然正确。主循环要持续调用 tick()：
// 超时和数据中断一经发现就锁存，否则长时间没数据时差值约 49.7 天后会回绕成小值，误判为刚收到数据。
#pragma once
#include <stdint.h>

namespace sysmon {

class ScreenState {
 public:
  static constexpr uint32_t kTimeoutMs = 10000;
  static constexpr uint32_t kStaleMs = 300000;

  // 返回 true 表示距上一条数据超过 kStaleMs，调用方应先清空曲线历史。
  bool onSample(uint32_t nowMs);
  void onOff() { forcedOff_ = true; }
  void tick(uint32_t nowMs);
  bool lit(uint32_t nowMs) const;

 private:
  bool hasSample_ = false;
  bool forcedOff_ = false;
  bool expired_ = false;  // 已超过 kTimeoutMs
  bool stale_ = false;    // 已超过 kStaleMs
  uint32_t lastMs_ = 0;
};

}  // namespace sysmon
