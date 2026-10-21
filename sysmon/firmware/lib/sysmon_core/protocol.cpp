#include "protocol.h"

#include <stdlib.h>
#include <string.h>

#include "parse_util.h"

namespace sysmon {

using detail::clampPercent;
using detail::clampU32;
using detail::keyIs;
using detail::parseNumber;

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
