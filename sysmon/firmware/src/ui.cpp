#include "ui.h"

#include <math.h>
#include <stdio.h>

#include "format.h"
#include "tones.h"
#include "usage_format.h"

using namespace sysmon;

namespace {

constexpr uint16_t rgb(uint32_t hex) {
  return ((hex >> 8) & 0xF800) | ((hex >> 5) & 0x07E0) | ((hex >> 3) & 0x001F);
}

const uint16_t BG = rgb(0x0b0d10);
const uint16_t TRACK = rgb(0x1c2026);
const uint16_t TEXT = rgb(0xe8eaed);
const uint16_t LABEL = rgb(0x8a9099);
const uint16_t DIM = rgb(0x5c626b);
const uint16_t GREEN = rgb(0x34c759);
const uint16_t YELLOW = rgb(0xffcc00);
const uint16_t RED = rgb(0xff453a);
const uint16_t BLUE = rgb(0x64d2ff);
const uint16_t ORANGE = rgb(0xff9f0a);
const uint16_t BLUE_FILL = rgb(0x182b34);  // 蓝色按 15% 混进背景色
const uint16_t CLAUDE_BRAND = rgb(0xd97757);
const uint16_t CHATGPT_BRAND = rgb(0x10a37f);

uint16_t toneColor(Tone t) { return t == Tone::Red ? RED : t == Tone::Yellow ? YELLOW : GREEN; }

// 整屏 sprite 要 150KB，没有 PSRAM 放不下，所以上下两块分别画、分别推送。
constexpr int TOP_H = 134;
constexpr int BOTTOM_Y = TOP_H;
constexpr int BOTTOM_H = 320 - TOP_H;

// 页码小点：从右往左排，最右一个的右边缘在 x=228；纵向只占系统状态屏圆环（顶部 y=15）上方的空白
constexpr int DOTS_Y = 9, DOTS_X1 = 225, DOT_R = 3, DOT_GAP = 10;

// y 用屏幕坐标；oy 是 sprite 顶边在屏幕上的纵坐标
void drawDots(LGFX_Sprite& sp, const PageInfo& p, int oy) {
  if (p.count <= 1) return;
  for (int i = 1; i <= p.count; ++i) {
    sp.fillCircle(DOTS_X1 - (p.count - i) * DOT_GAP, DOTS_Y - oy, DOT_R, i == p.index ? LABEL : TRACK);
  }
}

// 圆环的弧：内半径 r0、外半径 r1，从 12 点钟方向顺时针画占比；percent <= 0 时只画底色
void drawArc(LGFX_Sprite& sp, int cx, int cy, int r0, int r1, int percent, uint16_t color) {
  sp.fillArc(cx, cy, r0, r1, 0, 360, TRACK);
  if (percent <= 0) return;
  // LovyanGFX 的角度 0 在 3 点钟、顺时针增大；跨过 360 时拆成两段
  float a0 = 270, a1 = 270 + percent * 3.6f;
  if (a1 <= 360) {
    sp.fillArc(cx, cy, r0, r1, a0, a1, color);
  } else {
    sp.fillArc(cx, cy, r0, r1, a0, 360, color);
    sp.fillArc(cx, cy, r0, r1, 0, a1 - 360, color);
  }
  // 圆头端点，对应效果图里的 stroke-linecap: round
  float mid = (r0 + r1) / 2.0f, capR = (r1 - r0) / 2.0f;
  float rad = a1 * (float)M_PI / 180;
  sp.fillCircle(cx, cy - (int)mid, (int)capR, color);
  sp.fillCircle(cx + (int)lroundf(mid * cosf(rad)), cy + (int)lroundf(mid * sinf(rad)), (int)capR, color);
}

// 系统状态屏的圆环：外半径 45、内半径 35
constexpr int RING_Y = 60, RING_R0 = 35, RING_R1 = 45;

void drawRing(LGFX_Sprite& sp, int cx, int percent, uint16_t color, uint16_t numColor, const char* label) {
  drawArc(sp, cx, RING_Y, RING_R0, RING_R1, percent, color);

  char num[8];
  snprintf(num, sizeof(num), "%d", percent);
  sp.setFont(&fonts::FreeSansBold18pt7b);
  sp.setTextColor(numColor);
  sp.setTextDatum(middle_center);
  sp.drawString(num, cx, RING_Y + 1);

  sp.setFont(&fonts::efontCN_12);
  sp.setTextColor(LABEL);
  sp.setTextDatum(middle_center);
  sp.drawString(label, cx, 120);
}

void drawTop(LGFX_Sprite& sp, const Sample& s, const PageInfo& p) {
  sp.fillScreen(BG);
  drawDots(sp, p, 0);
  drawRing(sp, 64, s.cpu, toneColor(cpuTone(s.cpu)), TEXT, "CPU %");
  uint16_t mem = toneColor(memTone(s.level));
  drawRing(sp, 176, s.mem, mem, mem, "内存压力 %");
}

// 下块内的纵坐标（下块从屏幕 y=134 开始）
constexpr int DIVIDER_Y = 0;
constexpr int LABEL_Y = 8;         // 屏幕 y≈142
constexpr int VALUE_BASE_Y = 52;   // 数值底边，屏幕 y≈186
constexpr int CHART_X0 = 12, CHART_X1 = 228;
constexpr int PEAK_Y = 74;         // 峰值虚线，屏幕 y≈208
constexpr int CHART_BOTTOM = 160;  // 底线，屏幕 y≈294
constexpr int AXIS_Y = 164;        // 时间标注顶边，屏幕 y≈298

// 画一组「大数字 + 小单位」，right=true 时右对齐到 x
void drawRate(LGFX_Sprite& sp, uint32_t bps, int x, bool right, uint16_t color) {
  char num[16];
  const char* unit = formatRate(bps, num, sizeof(num));
  sp.setFont(&fonts::FreeSansBold18pt7b);
  int numW = sp.textWidth(num);
  sp.setFont(&fonts::efontCN_12);
  int unitW = sp.textWidth(unit);
  int left = right ? x - numW - 3 - unitW : x;

  sp.setFont(&fonts::FreeSansBold18pt7b);
  sp.setTextColor(color);
  sp.setTextDatum(bottom_left);
  sp.drawString(num, left, VALUE_BASE_Y);
  sp.setFont(&fonts::efontCN_12);
  sp.setTextColor(LABEL);
  sp.drawString(unit, left + numW + 3, VALUE_BASE_Y - 3);
}

int pointX(int i, int n) { return CHART_X1 - (n - 1 - i) * (CHART_X1 - CHART_X0) / (History::kCapacity - 1); }

int pointY(uint32_t v, uint32_t peak) {
  if (peak == 0) return CHART_BOTTOM;
  return CHART_BOTTOM - (int)((uint64_t)v * (CHART_BOTTOM - PEAK_Y) / peak);
}

void drawChart(LGFX_Sprite& sp, const History& h) {
  uint32_t peak = h.peak();

  for (int x = CHART_X0; x < CHART_X1; x += 6) sp.drawFastHLine(x, PEAK_Y, 3, TRACK);
  sp.drawFastHLine(CHART_X0, CHART_BOTTOM, CHART_X1 - CHART_X0 + 1, TRACK);

  char num[16], text[32];
  const char* unit = formatRate(peak, num, sizeof(num));
  snprintf(text, sizeof(text), "峰值 %s %s", num, unit);
  sp.setFont(&fonts::efontCN_10);
  sp.setTextColor(DIM);
  sp.setTextDatum(bottom_right);
  sp.drawString(text, CHART_X1, PEAK_Y - 2);

  int n = h.size();
  // 下载曲线下方先填充
  for (int i = 1; i < n; ++i) {
    int x0 = pointX(i - 1, n), x1 = pointX(i, n);
    int y0 = pointY(h.rxAt(i - 1), peak), y1 = pointY(h.rxAt(i), peak);
    sp.fillTriangle(x0, y0, x1, y1, x1, CHART_BOTTOM, BLUE_FILL);
    sp.fillTriangle(x0, y0, x0, CHART_BOTTOM, x1, CHART_BOTTOM, BLUE_FILL);
  }
  for (int i = 1; i < n; ++i) {
    sp.drawWideLine(pointX(i - 1, n), pointY(h.rxAt(i - 1), peak), pointX(i, n), pointY(h.rxAt(i), peak), 1.0f, BLUE);
  }
  for (int i = 1; i < n; ++i) {
    sp.drawWideLine(pointX(i - 1, n), pointY(h.txAt(i - 1), peak), pointX(i, n), pointY(h.txAt(i), peak), 1.0f, ORANGE);
  }

  sp.setTextDatum(top_left);
  sp.drawString("5 分钟前", CHART_X0, AXIS_Y);
  sp.setTextDatum(top_right);
  sp.drawString("现在", CHART_X1, AXIS_Y);
}

void drawBottom(LGFX_Sprite& sp, const Sample& s, const History& h) {
  sp.fillScreen(BG);
  sp.drawFastHLine(CHART_X0, DIVIDER_Y, CHART_X1 - CHART_X0 + 1, TRACK);

  sp.setFont(&fonts::efontCN_12);
  sp.setTextColor(LABEL);
  sp.setTextDatum(top_left);
  sp.drawString("↓ 下载", CHART_X0, LABEL_Y);
  sp.setTextDatum(top_right);
  sp.drawString("↑ 上传", CHART_X1, LABEL_Y);

  drawRate(sp, s.rx, CHART_X0, false, BLUE);
  drawRate(sp, s.tx, CHART_X1, true, ORANGE);
  drawChart(sp, h);
}

// ---- 用量屏 ----
// 整屏按屏幕坐标排版；分上下两块画时，每块都把整屏画一遍，sprite 外的部分自动裁掉。
constexpr int U_X0 = 12, U_X1 = 228;
constexpr int BRAND_BASE_Y = 15;  // 品牌名基线，和页码小点大致齐平
constexpr int U_RING_X = 120, U_RING_Y = 96, U_RING_R0 = 51, U_RING_R1 = 65;
constexpr int U_NUM_Y = 90;        // 圆环中间的大数字
constexpr int U_WIN_Y = 122;       // 数字下面的“5 小时 %”
constexpr int U_RESET_Y = 172;     // 圆环下方的重置时间
constexpr int U_DIVIDER_Y = 182;
constexpr int U_ROW_Y = 190, U_ROW_PITCH = 36;  // 进度条行：上面标签和百分比，下面 8px 高的条
constexpr int U_FOOT_Y = 306;

// 数字颜色：绿档用正文色，黄、红档用档位色（同效果图）
uint16_t percentColor(int v) {
  Tone t = cpuTone(v);
  return t == Tone::Green ? TEXT : toneColor(t);
}

// v < 0（缺失或已重置）时写“--”、条留空
void drawBar(LGFX_Sprite& sp, int y, const char* label, int v) {
  sp.setFont(&fonts::efontCN_12);
  sp.setTextColor(LABEL);
  sp.setTextDatum(middle_left);
  sp.drawString(label, U_X0, y + 7);

  char num[16];
  if (v >= 0) {
    snprintf(num, sizeof(num), "%d%%", v);
  } else {
    snprintf(num, sizeof(num), "--");
  }
  sp.setFont(&fonts::FreeSansBold9pt7b);
  sp.setTextColor(percentColor(v));
  sp.setTextDatum(middle_right);
  sp.drawString(num, U_X1, y + 7);

  constexpr int w = U_X1 - U_X0;
  sp.fillRoundRect(U_X0, y + 17, w, 8, 4, TRACK);
  if (v > 0) sp.fillRoundRect(U_X0, y + 17, max(w * v / 100, 8), 8, 4, toneColor(cpuTone(v)));
}

void drawUsage(LGFX_Sprite& sp, const Usage& u, Service svc, const PageInfo& p, int oy) {
  bool claude = svc == Service::Claude;
  sp.fillScreen(BG);
  sp.setFont(&fonts::FreeSansBold9pt7b);
  sp.setTextColor(claude ? CLAUDE_BRAND : CHATGPT_BRAND);
  sp.setTextDatum(baseline_left);
  sp.drawString(claude ? "Claude" : "ChatGPT", U_X0, BRAND_BASE_Y - oy);
  drawDots(sp, p, oy);

  // 没有登录、也从没拉到过数据：整屏只写提示
  if (u.received && u.st == UsageStatus::Missing && u.age == kAbsent) {
    sp.setFont(&fonts::efontCN_14);
    sp.setTextColor(TEXT);
    sp.setTextDatum(middle_center);
    sp.drawString(claude ? "未找到 Claude Code 登录" : "未找到 Codex 登录", 120, 150 - oy);
    sp.setFont(&fonts::efontCN_12);
    sp.setTextColor(LABEL);
    sp.drawString("在设置里可以关闭这一屏", 120, 176 - oy);
    return;
  }

  // 5 小时窗口：大圆环
  drawArc(sp, U_RING_X, U_RING_Y - oy, U_RING_R0, U_RING_R1, u.h5, toneColor(cpuTone(u.h5)));
  char text[48];
  if (u.h5 >= 0) {
    snprintf(text, sizeof(text), "%d", u.h5);
  } else {
    snprintf(text, sizeof(text), "--");
  }
  sp.setFont(&fonts::FreeSansBold24pt7b);
  sp.setTextColor(percentColor(u.h5));
  sp.setTextDatum(middle_center);
  sp.drawString(text, U_RING_X, U_NUM_Y - oy);

  snprintf(text, sizeof(text), "%s %%", windowLabel(300));
  sp.setFont(&fonts::efontCN_12);
  sp.setTextColor(LABEL);
  sp.drawString(text, U_RING_X, U_WIN_Y - oy);

  text[0] = '\0';
  if (u.h5 == kReset) {
    snprintf(text, sizeof(text), "已重置");
  } else if (u.h5 >= 0 && u.h5r != kAbsent) {
    formatResetIn(u.h5r, text, sizeof(text));
  }
  sp.setFont(&fonts::efontCN_10);
  sp.setTextColor(DIM);
  sp.drawString(text, U_RING_X, U_RESET_Y - oy);

  sp.drawFastHLine(U_X0, U_DIVIDER_Y - oy, U_X1 - U_X0 + 1, TRACK);

  // 本周和分项：进度条。分项只有 Claude 有，按模型额度、Opus、Sonnet 的顺序，
  // 没发的不画，最多两条（屏幕只放得下三行）
  int y = U_ROW_Y;
  if (u.wk == kReset) {
    snprintf(text, sizeof(text), "本周 · 已重置");
  } else {
    formatWeekReset(u.wkd, u.wkt, text, sizeof(text));
  }
  drawBar(sp, y - oy, text, u.wk);
  if (claude) {
    int extra = 0;
    if (u.model[0] && u.mw != kAbsent) {
      snprintf(text, sizeof(text), "本周 %s", u.model);
      drawBar(sp, y + U_ROW_PITCH * ++extra - oy, text, u.mw);
    }
    if (extra < 2 && u.op != kAbsent) drawBar(sp, y + U_ROW_PITCH * ++extra - oy, "本周 Opus", u.op);
    if (extra < 2 && u.so != kAbsent) drawBar(sp, y + U_ROW_PITCH * ++extra - oy, "本周 Sonnet", u.so);
  }

  // 底栏：左套餐名，右数据新鲜度
  formatPlan(u.plan, text, sizeof(text));
  sp.setFont(&fonts::efontCN_10);
  sp.setTextColor(DIM);
  sp.setTextDatum(middle_left);
  sp.drawString(text, U_X0, U_FOOT_Y - oy);
  bool warn = false;
  formatFooter(u, text, sizeof(text), &warn);
  sp.setTextColor(warn ? ORANGE : DIM);
  sp.setTextDatum(middle_right);
  sp.drawString(text, U_X1, U_FOOT_Y - oy);
}

}  // namespace

// 开机时一次分配、一直复用，避免运行久了堆碎片导致分配失败、半边屏幕画不出来
static LGFX_Sprite* sprite = nullptr;

bool uiBegin(LGFX& lcd) {
  sprite = new LGFX_Sprite(&lcd);
  sprite->setColorDepth(16);
  if (sprite->createSprite(240, BOTTOM_H)) return true;

  Serial.printf("sysmon: sprite alloc failed, largest DMA block %u\n",
                (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_DMA));
  delete sprite;
  sprite = nullptr;
  lcd.setFont(&fonts::efontCN_14);
  lcd.setTextColor(TEXT, BG);
  lcd.setTextDatum(middle_center);
  lcd.fillScreen(BG);
  lcd.drawString("内存不足，无法显示", 120, 160);
  return false;
}

// 缓冲按下块的高度分配；上块只推送前 TOP_H 行
static void pushTop(LGFX& lcd) {
  lcd.setClipRect(0, 0, 240, TOP_H);
  sprite->pushSprite(0, 0);
  lcd.clearClipRect();
}

void uiDraw(LGFX& lcd, const Sample& s, const History& h, const PageInfo& p) {
  if (!sprite) return;
  drawTop(*sprite, s, p);
  pushTop(lcd);
  drawBottom(*sprite, s, h);
  sprite->pushSprite(0, BOTTOM_Y);
}

void uiDrawUsage(LGFX& lcd, const Usage& u, Service svc, const PageInfo& p) {
  if (!sprite) return;
  drawUsage(*sprite, u, svc, p, 0);
  pushTop(lcd);
  drawUsage(*sprite, u, svc, p, BOTTOM_Y);
  sprite->pushSprite(0, BOTTOM_Y);
}
