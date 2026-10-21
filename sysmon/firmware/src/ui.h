// 副屏画面：上半屏 CPU / 内存压力两个圆环，下半屏网速数值和最近 5 分钟曲线。
// 布局照搬 .superpowers/brainstorm/49999-1792549657/content/layout-v3.html（竖屏 240×320）。
#pragma once
#include "board.h"
#include "history.h"
#include "protocol.h"

void uiDraw(LGFX& lcd, const sysmon::Sample& s, const sysmon::History& h);
