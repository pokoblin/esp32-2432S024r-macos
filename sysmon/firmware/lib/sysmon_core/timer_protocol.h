// Mac 端发来的番茄状态和横幅行。
//   番茄：T st=<idle|focus|short|long> run=<0|1> rem=<秒> tot=<秒> [end=<HHMM>] rd=<n> rn=<n>
//         dn=<n> dm=<分钟> key=<0|1>
//   横幅：B k=<none|done|brk|sit|water> [min=<分钟>] [xw=1] [xs=1] [led=<0|1>]
// 字段顺序不限，不认识的字段忽略。
#pragma once
#include <stdint.h>

#include "usage_protocol.h"

namespace sysmon {

enum class Phase { Idle, Focus, Short, Long };

struct Timer {
  bool received = false;  // 是否收到过 T 行
  Phase phase = Phase::Idle;
  bool running = false;   // 暂停和空闲时为 false
  int32_t rem = 0;        // 这一段还剩多少秒（空闲时是下一段专注的总秒数）
  int32_t tot = 0;        // 这一段的总秒数
  int end = kAbsent;      // 预计结束的本地时刻 HHMM；暂停和空闲时没有
  int rd = 1;             // 第几个：专注和空闲时是当前或下一个，休息时是刚做完的
  int rn = 4;             // 每轮几个
  int dn = 0;             // 今天完成几个
  int dm = 0;             // 今天专注了多少分钟
  bool key = false;       // Mac 上录了番茄快捷键没有
};

enum class BannerKind { None, FocusDone, BreakEnded, Sit, Water };

struct Banner {
  BannerKind kind = BannerKind::None;
  int min = kAbsent;  // 久坐、喝水的分钟数
  bool xw = false;    // 专注完成横幅追加“喝水”
  bool xs = false;    // 专注完成横幅追加“起来走走”
  bool led = false;   // RGB 灯开关
};

// 缺 st / rem / tot、st 不认识、已知数字字段不是数字时返回 false，*out 不变；
// 成功时 *out 整个重写，received 置 true。
bool parseTimerLine(const char* line, Timer* out);

// 缺 k 或 k 不认识时返回 false，*out 不变；成功时整个重写。
bool parseBannerLine(const char* line, Banner* out);

// 收到 T 行的时刻是 receivedMs。走着时按经过的整秒往下减，最小为 0；不在走时原样返回 rem。
// 时间差用无符号减法，millis() 回绕后依然正确。
int32_t timerRemaining(const Timer& t, uint32_t receivedMs, uint32_t nowMs);

}  // namespace sysmon
