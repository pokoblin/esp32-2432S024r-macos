#include "usage_format.h"

#include <stdio.h>
#include <string.h>

namespace sysmon {

void formatResetIn(int32_t secs, char* out, size_t len) {
  if (len == 0) return;
  if (secs >= 3600) {
    snprintf(out, len, "%d小时%d分后重置", (int)(secs / 3600), (int)(secs % 3600 / 60));
  } else if (secs >= 60) {
    snprintf(out, len, "%d分后重置", (int)(secs / 60));
  } else {
    snprintf(out, len, "即将重置");
  }
}

void formatWeekReset(int wkd, int wkt, char* out, size_t len) {
  if (len == 0) return;
  static const char* const kDays[] = {"一", "二", "三", "四", "五", "六", "日"};
  if (wkd < 1 || wkd > 7 || wkt < 0) {
    snprintf(out, len, "本周");
    return;
  }
  snprintf(out, len, "本周 · 周%s %02d:%02d 重置", kDays[wkd - 1], wkt / 100, wkt % 100);
}

void formatAgo(int32_t secs, char* out, size_t len) {
  if (len == 0) return;
  if (secs < 60) {  // 含负数和 kAbsent
    snprintf(out, len, "刚刚");
  } else if (secs < 3600) {
    snprintf(out, len, "%d 分钟前", (int)(secs / 60));
  } else if (secs < 86400) {
    snprintf(out, len, "%d 小时前", (int)(secs / 3600));
  } else {
    snprintf(out, len, "%d 天前", (int)(secs / 86400));
  }
}

void formatFooter(const Usage& u, char* out, size_t len, bool* warn) {
  if (warn) *warn = false;
  if (len == 0) return;
  if (!u.received) {
    snprintf(out, len, "等待数据");
    return;
  }
  char ago[32];
  switch (u.st) {
    case UsageStatus::Ok:
      if (u.age == kAbsent || u.age < 60) {
        snprintf(out, len, "刚刚更新");
      } else {
        formatAgo(u.age, ago, sizeof ago);
        snprintf(out, len, "%s更新", ago);
      }
      break;
    case UsageStatus::Expired:
      snprintf(out, len, u.svc == Service::Claude ? "已过期 · 终端运行 claude" : "已过期 · 打开 Codex");
      if (warn) *warn = true;
      break;
    case UsageStatus::Error:
      if (u.age == kAbsent) {
        snprintf(out, len, "读取失败");
      } else {
        formatAgo(u.age, ago, sizeof ago);
        snprintf(out, len, "读取失败 · %s的数据", ago);
      }
      if (warn) *warn = true;
      break;
    case UsageStatus::Missing:
      out[0] = '\0';  // 整屏提示由 UI 来画
      break;
  }
}

void formatPlan(const char* plan, char* out, size_t len) {
  if (len == 0) return;
  strncpy(out, plan, len - 1);
  out[len - 1] = '\0';
  if (out[0] >= 'a' && out[0] <= 'z') out[0] = (char)(out[0] - 'a' + 'A');
}

const char* windowLabel(int minutes) {
  if (minutes == 300) return "5 小时";
  if (minutes == 10080) return "本周";
  return "";
}

}  // namespace sysmon
