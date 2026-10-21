#include "format.h"

#include <stdio.h>

namespace sysmon {

const char* formatRate(uint32_t bytesPerSec, char* num, size_t numLen) {
  if (bytesPerSec < 1000) {
    snprintf(num, numLen, "%u", (unsigned)bytesPerSec);
    return "B/s";
  }
  // 按四舍五入后的值选单位和小数位，保证最多 3 位有效数字（999.5 KB 显示为 0.98 MB，9.999 显示为 10.0）
  const char* unit = "KB/s";
  double v = bytesPerSec / 1024.0;
  if (v >= 999.5) {
    unit = "MB/s";
    v /= 1024.0;
  }
  if (v >= 999.5) {
    unit = "GB/s";
    v /= 1024.0;
  }
  const char* fmt = v < 9.995 ? "%.2f" : v < 99.95 ? "%.1f" : "%.0f";
  snprintf(num, numLen, fmt, v);
  return unit;
}

}  // namespace sysmon
