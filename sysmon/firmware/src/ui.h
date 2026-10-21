// 副屏画面。
//   系统状态屏：上半屏 CPU / 内存压力两个圆环，下半屏网速数值和最近 5 分钟曲线。
//     布局照搬 .superpowers/brainstorm/49999-1792549657/content/layout-v3.html（竖屏 240×320）。
//   用量屏（Claude / ChatGPT）：一个 5 小时大圆环，下面是本周等进度条。
//     布局照搬 .superpowers/brainstorm/84832-1792562336/content/usage-layout.html 的 C 版。
// 各屏右上角都有页码小点，轮换里只有一屏时不画。
#pragma once
#include "board.h"
#include "history.h"
#include "protocol.h"
#include "usage_protocol.h"

// 开机时调用一次：分配画图缓冲；失败时在屏幕和串口上报错并返回 false
bool uiBegin(LGFX& lcd);
void uiDraw(LGFX& lcd, const sysmon::Sample& s, const sysmon::History& h, const sysmon::PageInfo& p);
void uiDrawUsage(LGFX& lcd, const sysmon::Usage& u, sysmon::Service svc, const sysmon::PageInfo& p);
