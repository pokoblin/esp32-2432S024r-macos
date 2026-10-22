// 番茄屏和横幅的中文文案。缓冲区约定同 usage_format.h：
// 总是以 NUL 结尾，放不下就截断，不越界（len 为 0 时什么都不写）。
#pragma once
#include <stddef.h>
#include <stdint.h>

#include "timer_protocol.h"

namespace sysmon {

// "12:34"；0 和负数写 "00:00"，超过 99:59 截到 "99:59"。
void formatClock(int32_t secs, char* out, size_t len);

// "14:52 结束"；kAbsent（或越界）时写 ""。
void formatEndAt(int hhmm, char* out, size_t len);

// 专注和空闲："第 2 个 · 再 2 个后长休"，最后一个写 "第 4 个 · 这个做完长休"；休息中："已完成 2/4"。
void formatRoundLine(const Timer& t, char* out, size_t len);

// "2小时05分" / "45分" / "0分"。
void formatTodayMinutes(int dm, char* out, size_t len);

// "准备专注" / "专注" / "短休" / "长休" / "已暂停"。
const char* phaseLabel(const Timer& t);

// 番茄屏底栏的操作提示；没录快捷键时写 "在菜单栏开始"。
void formatHint(const Timer& t, char* out, size_t len);

// 横幅大标题（banner_titles.h 里的常量）；None 返回 ""。
const char* bannerTitle(BannerKind k);

// 标题下面的一行说明。专注完成的休息分钟数取 t.tot。
void formatBannerDetail(const Banner& b, const Timer& t, char* out, size_t len);

// 专注完成横幅的追加行：被压住的提醒。
void formatBannerExtras(const Banner& b, char* out, size_t len);

// 横幅最底下一行小字。
void formatBannerHint(const Banner& b, char* out, size_t len);

}  // namespace sysmon
