#include "usage_protocol.h"

#include <string.h>

#include "parse_util.h"

namespace sysmon {

namespace {

using detail::clampPercent;
using detail::clampSeconds;
using detail::forEachField;
using detail::keyIs;
using detail::parseNumber;
using detail::valueIs;

// 百分比：-1 表示窗口已重置，其余限到 0..100。
int percentOrReset(long long v) { return v == -1 ? kReset : clampPercent(v); }

// 文字字段：截断到缓冲区大小，始终以 NUL 结尾。
void copyText(const char* val, const char* end, char* dst, size_t size) {
  size_t n = (size_t)(end - val);
  if (n > size - 1) n = size - 1;
  memcpy(dst, val, n);
  dst[n] = '\0';
}

}  // namespace

bool parsePageLine(const char* line, PageInfo* out) {
  if (!out || line[0] != 'P' || line[1] != ' ') return false;

  const char* p = line + 2;
  while (*p == ' ') ++p;
  const char* nameEnd = p;
  while (*nameEnd && *nameEnd != ' ') ++nameEnd;

  PageInfo info;
  if (valueIs(p, nameEnd, "sys")) info.page = Page::Sys;
  else if (valueIs(p, nameEnd, "pomo")) info.page = Page::Pomo;
  else if (valueIs(p, nameEnd, "cl")) info.page = Page::Claude;
  else if (valueIs(p, nameEnd, "gpt")) info.page = Page::ChatGPT;
  else return false;

  bool haveI = false, haveN = false;
  bool ok = forEachField(nameEnd, [&](const char* key, size_t keyLen, const char* val, const char* end) {
    bool isI = keyIs(key, keyLen, "i");
    if (!isI && !keyIs(key, keyLen, "n")) return true;
    long long v;
    if (!parseNumber(val, end, &v)) return false;
    // 超出 1..4 的值直接判无效，不必精确保存
    int iv = v < 0 ? 0 : v > 99 ? 99 : (int)v;
    if (isI) { info.index = iv; haveI = true; }
    else { info.count = iv; haveN = true; }
    return true;
  });
  if (!ok || !haveI || !haveN) return false;
  if (info.index < 1 || info.index > info.count || info.count > 4) return false;

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
      copyText(val, end, u.plan, sizeof(u.plan));
    } else if (keyIs(key, keyLen, "md")) {
      copyText(val, end, u.model, sizeof(u.model));
    } else {
      bool isAge = keyIs(key, keyLen, "age"), isH5r = keyIs(key, keyLen, "h5r");
      bool isH5 = keyIs(key, keyLen, "h5"), isWk = keyIs(key, keyLen, "wk");
      bool isWkd = keyIs(key, keyLen, "wkd"), isWkt = keyIs(key, keyLen, "wkt");
      bool isOp = keyIs(key, keyLen, "op"), isSo = keyIs(key, keyLen, "so");
      bool isMw = keyIs(key, keyLen, "mw");
      if (!(isAge || isH5r || isH5 || isWk || isWkd || isWkt || isOp || isSo || isMw)) return true;  // 未知字段忽略
      long long v;
      if (!parseNumber(val, end, &v)) return false;
      if (isAge) u.age = clampSeconds(v);
      else if (isH5r) u.h5r = clampSeconds(v);
      else if (isH5) u.h5 = percentOrReset(v);
      else if (isWk) u.wk = percentOrReset(v);
      else if (isOp) u.op = percentOrReset(v);
      else if (isSo) u.so = percentOrReset(v);
      else if (isMw) u.mw = percentOrReset(v);
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
