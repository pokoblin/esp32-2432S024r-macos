#include "usage_protocol.h"

#include <string.h>

#include "parse_util.h"

namespace sysmon {

namespace {

using detail::clampPercent;
using detail::keyIs;
using detail::parseNumber;

// 逐个遍历 [p, end) 里以空格分隔的 key=value；fn(key, keyLen, val, valEnd) 返回 false 就中止。
// 没有 '=' 的记号忽略。
template <typename Fn>
bool forEachField(const char* p, Fn fn) {
  while (*p) {
    while (*p == ' ') ++p;
    if (!*p) break;
    const char* tokEnd = p;
    while (*tokEnd && *tokEnd != ' ') ++tokEnd;
    const char* eq = (const char*)memchr(p, '=', tokEnd - p);
    if (eq && !fn(p, (size_t)(eq - p), eq + 1, tokEnd)) return false;
    p = tokEnd;
  }
  return true;
}

bool valueIs(const char* val, const char* end, const char* name) {
  return keyIs(val, (size_t)(end - val), name);
}

// 百分比：-1 表示窗口已重置，其余限到 0..100。
int percentOrReset(long long v) { return v == -1 ? kReset : clampPercent(v); }

// 秒数：负数归零，超过 int32 的限幅。
int32_t clampSeconds(long long v) { return v < 0 ? 0 : v > INT32_MAX ? INT32_MAX : (int32_t)v; }

}  // namespace

bool parsePageLine(const char* line, PageInfo* out) {
  if (!out || line[0] != 'P' || line[1] != ' ') return false;

  const char* p = line + 2;
  while (*p == ' ') ++p;
  const char* nameEnd = p;
  while (*nameEnd && *nameEnd != ' ') ++nameEnd;

  PageInfo info;
  if (valueIs(p, nameEnd, "sys")) info.page = Page::Sys;
  else if (valueIs(p, nameEnd, "cl")) info.page = Page::Claude;
  else if (valueIs(p, nameEnd, "gpt")) info.page = Page::ChatGPT;
  else return false;

  bool haveI = false, haveN = false;
  bool ok = forEachField(nameEnd, [&](const char* key, size_t keyLen, const char* val, const char* end) {
    bool isI = keyIs(key, keyLen, "i");
    if (!isI && !keyIs(key, keyLen, "n")) return true;
    long long v;
    if (!parseNumber(val, end, &v)) return false;
    // 超出 1..3 的值直接判无效，不必精确保存
    int iv = v < 0 ? 0 : v > 99 ? 99 : (int)v;
    if (isI) { info.index = iv; haveI = true; }
    else { info.count = iv; haveN = true; }
    return true;
  });
  if (!ok || !haveI || !haveN) return false;
  if (info.index < 1 || info.index > info.count || info.count > 3) return false;

  *out = info;
  return true;
}

bool parseUsageLine(const char* line, Usage* out) {
  if (!out || line[0] != 'U' || line[1] != ' ') return false;

  Usage u;
  bool haveSvc = false, haveSt = false;
  bool ok = forEachField(line + 2, [&](const char* key, size_t keyLen, const char* val, const char* end) {
    if (keyIs(key, keyLen, "svc")) {
      if (valueIs(val, end, "cl")) u.svc = Service::Claude;
      else if (valueIs(val, end, "gpt")) u.svc = Service::ChatGPT;
      else return false;
      haveSvc = true;
    } else if (keyIs(key, keyLen, "st")) {
      if (valueIs(val, end, "ok")) u.st = UsageStatus::Ok;
      else if (valueIs(val, end, "exp")) u.st = UsageStatus::Expired;
      else if (valueIs(val, end, "err")) u.st = UsageStatus::Error;
      else if (valueIs(val, end, "none")) u.st = UsageStatus::Missing;
      else return false;
      haveSt = true;
    } else if (keyIs(key, keyLen, "plan")) {
      // 截断到缓冲区大小，始终以 NUL 结尾
      size_t n = (size_t)(end - val);
      if (n > sizeof(u.plan) - 1) n = sizeof(u.plan) - 1;
      memcpy(u.plan, val, n);
      u.plan[n] = '\0';
    } else {
      bool isAge = keyIs(key, keyLen, "age"), isH5r = keyIs(key, keyLen, "h5r");
      bool isH5 = keyIs(key, keyLen, "h5"), isWk = keyIs(key, keyLen, "wk");
      bool isWkd = keyIs(key, keyLen, "wkd"), isWkt = keyIs(key, keyLen, "wkt");
      bool isOp = keyIs(key, keyLen, "op"), isSo = keyIs(key, keyLen, "so");
      if (!(isAge || isH5r || isH5 || isWk || isWkd || isWkt || isOp || isSo)) return true;  // 未知字段忽略
      long long v;
      if (!parseNumber(val, end, &v)) return false;
      if (isAge) u.age = clampSeconds(v);
      else if (isH5r) u.h5r = clampSeconds(v);
      else if (isH5) u.h5 = percentOrReset(v);
      else if (isWk) u.wk = percentOrReset(v);
      else if (isOp) u.op = percentOrReset(v);
      else if (isSo) u.so = percentOrReset(v);
      else if (isWkd) u.wkd = (v >= 1 && v <= 7) ? (int)v : kAbsent;
      else u.wkt = (v >= 0 && v <= 2359 && v % 100 < 60) ? (int)v : kAbsent;
    }
    return true;
  });
  if (!ok || !haveSvc || !haveSt) return false;

  u.received = true;
  *out = u;
  return true;
}

}  // namespace sysmon
