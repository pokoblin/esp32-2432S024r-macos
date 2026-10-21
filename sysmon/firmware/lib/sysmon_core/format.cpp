#include "format.h"

#include <stdio.h>

namespace sysmon {

const char* formatRate(uint32_t bytesPerSec, char* num, size_t numLen) {
  if (bytesPerSec < 1000) {
    snprintf(num, numLen, "%u", (unsigned)bytesPerSec);
    return "B/s";
  }
  // 满 1000 就进位，保证数字最多 3 位
  const char* unit = "KB/s";
  double v = bytesPerSec / 1024.0;
  if (bytesPerSec >= 1000u * 1024u) {
    unit = "MB/s";
    v = bytesPerSec / (1024.0 * 1024.0);
  }
  const char* fmt = v < 10 ? "%.2f" : v < 100 ? "%.1f" : "%.0f";
  snprintf(num, numLen, fmt, v);
  return unit;
}

}  // namespace sysmon
