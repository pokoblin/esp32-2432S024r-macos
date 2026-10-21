#include "protocol.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

namespace sysmon {

namespace {

// 解析 [p, end) 里的十进制整数（允许前导负号）；不是纯数字返回 false。
bool parseNumber(const char* p, const char* end, long long* out) {
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

bool keyIs(const char* key, size_t len, const char* name) {
  return strlen(name) == len && strncmp(key, name, len) == 0;
}

int clampPercent(long long v) { return v < 0 ? 0 : v > 100 ? 100 : (int)v; }

uint32_t clampU32(long long v) { return v < 0 ? 0 : v > 0xFFFFFFFFLL ? 0xFFFFFFFFu : (uint32_t)v; }

}  // namespace

LineKind parseLine(const char* line, Sample* out) {
  if (strcmp(line, "OFF") == 0) return LineKind::Off;
  if (line[0] != 'S' || line[1] != ' ') return LineKind::Unknown;

  Sample s{0, 0, 1, 0, 0};
  enum { CPU = 1, MEM = 2, RX = 4, TX = 8, ALL = 15 };
  int seen = 0;

  const char* p = line + 2;
  while (*p) {
    while (*p == ' ') ++p;
    if (!*p) break;
    const char* tokEnd = p;
    while (*tokEnd && *tokEnd != ' ') ++tokEnd;
    const char* eq = (const char*)memchr(p, '=', tokEnd - p);
    if (eq) {
      size_t keyLen = eq - p;
      bool known = keyIs(p, keyLen, "cpu") || keyIs(p, keyLen, "mem") || keyIs(p, keyLen, "lvl") ||
                   keyIs(p, keyLen, "rx") || keyIs(p, keyLen, "tx");
      if (known) {
        long long v;
        if (!parseNumber(eq + 1, tokEnd, &v)) return LineKind::Unknown;
        if (keyIs(p, keyLen, "cpu")) { s.cpu = clampPercent(v); seen |= CPU; }
        else if (keyIs(p, keyLen, "mem")) { s.mem = clampPercent(v); seen |= MEM; }
        else if (keyIs(p, keyLen, "lvl")) { s.level = (int)v; }
        else if (keyIs(p, keyLen, "rx")) { s.rx = clampU32(v); seen |= RX; }
        else { s.tx = clampU32(v); seen |= TX; }
      }
    }
    p = tokEnd;
  }

  if (seen != ALL) return LineKind::Unknown;
  *out = s;
  return LineKind::Sample;
}

}  // namespace sysmon
