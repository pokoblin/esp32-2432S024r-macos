// 背光开关：超过 kTimeoutMs 没数据或收到 OFF 就熄屏，有新数据就点亮。
// 时间差都用无符号减法，millis() 回绕后依然正确。
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
  bool lit(uint32_t nowMs) const;

 private:
  bool hasSample_ = false;
  bool forcedOff_ = false;
  uint32_t lastMs_ = 0;
};

}  // namespace sysmon
