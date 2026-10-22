#include "timer_format.h"

#include <stdio.h>

#include "banner_titles.h"

namespace sysmon {

void formatClock(int32_t secs, char* out, size_t len) {
  if (len == 0) return;
  if (secs < 0) secs = 0;
  if (secs > 99 * 60 + 59) secs = 99 * 60 + 59;
  snprintf(out, len, "%02d:%02d", (int)(secs / 60), (int)(secs % 60));
}

void formatEndAt(int hhmm, char* out, size_t len) {
  if (len == 0) return;
  if (hhmm < 0 || hhmm > 2359 || hhmm % 100 >= 60) {
    out[0] = '\0';
    return;
  }
  snprintf(out, len, "%02d:%02d 结束", hhmm / 100, hhmm % 100);
}

void formatRoundLine(const Timer& t, char* out, size_t len) {
  if (len == 0) return;
  if (t.phase == Phase::Short || t.phase == Phase::Long) {
    snprintf(out, len, "已完成 %d/%d", t.rd, t.rn);
  } else if (t.rd >= t.rn) {
    snprintf(out, len, "第 %d 个 · 这个做完长休", t.rd);
  } else {
    snprintf(out, len, "第 %d 个 · 再 %d 个后长休", t.rd, t.rn - t.rd);
  }
}

void formatTodayMinutes(int dm, char* out, size_t len) {
  if (len == 0) return;
  if (dm < 0) dm = 0;
  if (dm >= 60) {
    snprintf(out, len, "%d小时%02d分", dm / 60, dm % 60);
  } else {
    snprintf(out, len, "%d分", dm);
  }
}

const char* phaseLabel(const Timer& t) {
  if (t.phase == Phase::Idle) return "准备专注";
  if (!t.running) return "已暂停";
  switch (t.phase) {
    case Phase::Focus: return "专注";
    case Phase::Short: return "短休";
    default: return "长休";
  }
}

void formatHint(const Timer& t, char* out, size_t len) {
  if (len == 0) return;
  const char* text = !t.key ? "在菜单栏开始"
                     : t.phase == Phase::Idle ? "按快捷键开始专注"
                     : t.running ? "按快捷键暂停"
                                 : "按快捷键继续";
  snprintf(out, len, "%s", text);
}

const char* bannerTitle(BannerKind k) {
  switch (k) {
    case BannerKind::FocusDone: return kTitleFocusDone;
    case BannerKind::BreakEnded: return kTitleBreakEnded;
    case BannerKind::Sit: return kTitleSit;
    case BannerKind::Water: return kTitleWater;
    default: return "";
  }
}

void formatBannerDetail(const Banner& b, const Timer& t, char* out, size_t len) {
  if (len == 0) return;
  int min = b.min < 0 ? 0 : b.min;
  switch (b.kind) {
    case BannerKind::FocusDone: snprintf(out, len, "休息 %d 分钟", (int)(t.tot / 60)); break;
    case BannerKind::BreakEnded: snprintf(out, len, "该开始下一个专注了"); break;
    case BannerKind::Sit: snprintf(out, len, "已连续用电脑 %d 分钟", min); break;
    case BannerKind::Water: snprintf(out, len, "上次提醒是 %d 分钟前", min); break;
    default: out[0] = '\0';
  }
}

void formatBannerExtras(const Banner& b, char* out, size_t len) {
  if (len == 0) return;
  const char* text = b.xs && b.xw ? "顺便起来走走、喝口水"
                     : b.xs ? "顺便起来走走"
                     : b.xw ? "顺便喝口水"
                            : "";
  snprintf(out, len, "%s", text);
}

void formatBannerHint(const Banner& b, char* out, size_t len) {
  if (len == 0) return;
  const char* text = b.kind == BannerKind::Sit ? "点一下关掉 · 离开 5 分钟会自己消失"
                     : b.kind == BannerKind::BreakEnded ? "按快捷键开始 · 点一下关掉"
                                                        : "点一下关掉";
  snprintf(out, len, "%s", text);
}

}  // namespace sysmon
