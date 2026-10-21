#pragma once
#include <stddef.h>
#include <stdint.h>

#include "usage_protocol.h"

namespace sysmon {

// 以下函数都写进调用方给的缓冲区：总是以 NUL 结尾，放不下就截断，不越界（len 为 0 时什么都不写）。

// "2小时13分后重置" / "13分后重置"；不足 1 分钟（含负数、kAbsent）写 "即将重置"。
void formatResetIn(int32_t secs, char* out, size_t len);

// "本周 · 周四 14:00 重置"；wkd 或 wkt 缺失（或越界）时只写 "本周"。
void formatWeekReset(int wkd, int wkt, char* out, size_t len);

// "刚刚" / "3 分钟前" / "2 小时前" / "5 天前"；负数和 kAbsent 当作 "刚刚"。
void formatAgo(int32_t secs, char* out, size_t len);

// 底栏右侧文字；*warn 为 true 表示用橙色（warn 可传空指针）。
void formatFooter(const Usage& u, char* out, size_t len, bool* warn);

// 套餐名首字母大写："max" → "Max"。
void formatPlan(const char* plan, char* out, size_t len);

// 窗口分钟数对应的标签：300 → "5 小时"，10080 → "本周"，其他返回 ""。
const char* windowLabel(int minutes);

}  // namespace sysmon
