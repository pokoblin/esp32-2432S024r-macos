// protocol.cpp 和 usage_protocol.cpp 共用的小工具，只在 lib 内部使用。
#pragma once
#include <ctype.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

namespace sysmon {
namespace detail {

// 解析 [p, end) 里的十进制整数（允许前导负号）；不是纯数字返回 false。
inline bool parseNumber(const char* p, const char* end, long long* out) {
  if (p == end) return false;
  bool neg = false;
  if (*p == '-') {
    neg = true;
    if (++p == end) return false;
  }
  unsigned long long v = 0;
  for (; p < end; ++p) {
    if (!isdigit((unsigned char)*p)) return false;
    // 超大的数直接饱和，后面再按字段限幅
    if (v < 1000000000000ULL) v = v * 10 + (unsigned long long)(*p - '0');
  }
  *out = neg ? -(long long)v : (long long)v;
  return true;
}

inline bool keyIs(const char* key, size_t len, const char* name) {
  return strlen(name) == len && strncmp(key, name, len) == 0;
}

inline int clampPercent(long long v) { return v < 0 ? 0 : v > 100 ? 100 : (int)v; }

inline uint32_t clampU32(long long v) {
  return v < 0 ? 0 : v > 0xFFFFFFFFLL ? 0xFFFFFFFFu : (uint32_t)v;
}

}  // namespace detail
}  // namespace sysmon
