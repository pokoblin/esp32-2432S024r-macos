#include "timer_protocol.h"

#include "parse_util.h"

namespace sysmon {

namespace {

using detail::clampSeconds;
using detail::forEachField;
using detail::keyIs;
using detail::parseNumber;
using detail::valueIs;

// 个数、分钟数：负数归零，太大的限幅
int clampCount(long long v) { return v < 0 ? 0 : v > 9999 ? 9999 : (int)v; }

}  // namespace

bool parseTimerLine(const char* line, Timer* out) {
  if (!out || line[0] != 'T' || line[1] != ' ') return false;

  Timer t;
  bool haveSt = false, haveRem = false, haveTot = false;
  bool ok = forEachField(line + 2, [&](const char* key, size_t keyLen, const char* val, const char* end) {
    if (keyIs(key, keyLen, "st")) {
      if (valueIs(val, end, "idle")) t.phase = Phase::Idle;
      else if (valueIs(val, end, "focus")) t.phase = Phase::Focus;
      else if (valueIs(val, end, "short")) t.phase = Phase::Short;
      else if (valueIs(val, end, "long")) t.phase = Phase::Long;
      else return false;
      haveSt = true;
      return true;
    }
    bool isRun = keyIs(key, keyLen, "run"), isRem = keyIs(key, keyLen, "rem");
    bool isTot = keyIs(key, keyLen, "tot"), isEnd = keyIs(key, keyLen, "end");
    bool isRd = keyIs(key, keyLen, "rd"), isRn = keyIs(key, keyLen, "rn");
    bool isDn = keyIs(key, keyLen, "dn"), isDm = keyIs(key, keyLen, "dm");
    bool isKey = keyIs(key, keyLen, "key");
    if (!(isRun || isRem || isTot || isEnd || isRd || isRn || isDn || isDm || isKey)) return true;  // 未知字段忽略
    long long v;
    if (!parseNumber(val, end, &v)) return false;
    if (isRun) t.running = v != 0;
    else if (isKey) t.key = v != 0;
    else if (isRem) { t.rem = clampSeconds(v); haveRem = true; }
    else if (isTot) { t.tot = clampSeconds(v); haveTot = true; }
    else if (isEnd) t.end = (v >= 0 && v <= 2359 && v % 100 < 60) ? (int)v : kAbsent;
    else if (isRd) t.rd = clampCount(v);
    else if (isRn) t.rn = clampCount(v);
    else if (isDn) t.dn = clampCount(v);
    else t.dm = clampCount(v);
    return true;
  });
  if (!ok || !haveSt || !haveRem || !haveTot) return false;

  t.received = true;
  *out = t;
  return true;
}

bool parseBannerLine(const char* line, Banner* out) {
  if (!out || line[0] != 'B' || line[1] != ' ') return false;

  Banner b;
  bool haveKind = false;
  bool ok = forEachField(line + 2, [&](const char* key, size_t keyLen, const char* val, const char* end) {
    if (keyIs(key, keyLen, "k")) {
      if (valueIs(val, end, "none")) b.kind = BannerKind::None;
      else if (valueIs(val, end, "done")) b.kind = BannerKind::FocusDone;
      else if (valueIs(val, end, "brk")) b.kind = BannerKind::BreakEnded;
      else if (valueIs(val, end, "sit")) b.kind = BannerKind::Sit;
      else if (valueIs(val, end, "water")) b.kind = BannerKind::Water;
      else return false;
      haveKind = true;
      return true;
    }
    bool isMin = keyIs(key, keyLen, "min"), isXw = keyIs(key, keyLen, "xw");
    bool isXs = keyIs(key, keyLen, "xs"), isLed = keyIs(key, keyLen, "led");
    if (!(isMin || isXw || isXs || isLed)) return true;
    long long v;
    if (!parseNumber(val, end, &v)) return false;
    if (isMin) b.min = clampCount(v);
    else if (isXw) b.xw = v != 0;
    else if (isXs) b.xs = v != 0;
    else b.led = v != 0;
    return true;
  });
  if (!ok || !haveKind) return false;

  *out = b;
  return true;
}

int32_t timerRemaining(const Timer& t, uint32_t receivedMs, uint32_t nowMs) {
  if (!t.running) return t.rem;
  uint32_t elapsed = (nowMs - receivedMs) / 1000;
  return elapsed >= (uint32_t)t.rem ? 0 : t.rem - (int32_t)elapsed;
}

}  // namespace sysmon
