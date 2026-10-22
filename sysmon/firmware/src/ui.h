// 副屏画面。
//   系统状态屏：上半屏 CPU / 内存压力两个圆环，下半屏网速数值和最近 5 分钟曲线。
//     布局照搬 .superpowers/brainstorm/49999-1792549657/content/layout-v3.html（竖屏 240×320）。
//   用量屏（Claude / ChatGPT）：一个 5 小时大圆环，下面是本周等进度条。
//     布局照搬 .superpowers/brainstorm/84832-1792562336/content/usage-layout.html 的 C 版。
//   番茄屏：大圆环倒计时、这一轮的进度点、今日统计。布局照搬 .superpowers/brainstorm/27580-1792646222/content/pomodoro-layout.html 的 A 版。
//   横幅：不管停在哪一屏都整屏盖上来，见同目录 timer-banner.html 的 ② A 版。
// 各屏右上角都有页码小点，轮换里只有一屏时不画。专注时（含暂停），番茄屏以外各屏顶边画一条进度线；为它留出位置，各屏内容比效果图整体下移 4px。
#pragma once
#include "board.h"
#include "history.h"
#include "protocol.h"
#include "timer_protocol.h"
#include "usage_protocol.h"

// 开机时调用一次：分配画图缓冲；失败时在屏幕和串口上报错并返回 false
bool uiBegin(LGFX& lcd);
// t 是最近一次收到的番茄状态，rem 是本地倒数后的剩余秒数
void uiDraw(LGFX& lcd, const sysmon::Sample& s, const sysmon::History& h, const sysmon::PageInfo& p,
            const sysmon::Timer& t, int32_t rem);
void uiDrawUsage(LGFX& lcd, const sysmon::Usage& u, sysmon::Service svc, const sysmon::PageInfo& p,
                 const sysmon::Timer& t, int32_t rem);
void uiDrawPomodoro(LGFX& lcd, const sysmon::Timer& t, int32_t rem, const sysmon::PageInfo& p);
void uiDrawBanner(LGFX& lcd, const sysmon::Banner& b, const sysmon::Timer& t, int32_t rem);
