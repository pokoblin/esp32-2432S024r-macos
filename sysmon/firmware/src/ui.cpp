#include "ui.h"

#include <math.h>
#include <stdio.h>

#include "format.h"
#include "tones.h"

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

uint16_t toneColor(Tone t) { return t == Tone::Red ? RED : t == Tone::Yellow ? YELLOW : GREEN; }

// 整屏 sprite 要 150KB，没有 PSRAM 放不下，所以上下两块分别画、分别推送。
constexpr int TOP_H = 134;
constexpr int BOTTOM_Y = TOP_H;
constexpr int BOTTOM_H = 320 - TOP_H;

// 圆环：外半径 45、内半径 35，从 12 点钟方向顺时针画占比
constexpr int RING_Y = 60, RING_R0 = 35, RING_R1 = 45;

void drawRing(LGFX_Sprite& sp, int cx, int percent, uint16_t color, uint16_t numColor, const char* label) {
  sp.fillArc(cx, RING_Y, RING_R0, RING_R1, 0, 360, TRACK);
  if (percent > 0) {
    // LovyanGFX 的角度 0 在 3 点钟、顺时针增大；跨过 360 时拆成两段
    float a0 = 270, a1 = 270 + percent * 3.6f;
    if (a1 <= 360) {
      sp.fillArc(cx, RING_Y, RING_R0, RING_R1, a0, a1, color);
    } else {
      sp.fillArc(cx, RING_Y, RING_R0, RING_R1, a0, 360, color);
      sp.fillArc(cx, RING_Y, RING_R0, RING_R1, 0, a1 - 360, color);
    }
    // 圆头端点，对应效果图里的 stroke-linecap: round
    constexpr float mid = (RING_R0 + RING_R1) / 2.0f, capR = (RING_R1 - RING_R0) / 2.0f;
    float rad = a1 * (float)M_PI / 180;
    sp.fillCircle(cx, RING_Y - (int)mid, (int)capR, color);
    sp.fillCircle(cx + (int)lroundf(mid * cosf(rad)), RING_Y + (int)lroundf(mid * sinf(rad)), (int)capR, color);
  }

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

void drawTop(LGFX_Sprite& sp, const Sample& s) {
  sp.fillScreen(BG);
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

}  // namespace

void uiDraw(LGFX& lcd, const Sample& s, const History& h) {
  LGFX_Sprite sp(&lcd);
  sp.setColorDepth(16);

  if (sp.createSprite(240, TOP_H)) {
    drawTop(sp, s);
    sp.pushSprite(0, 0);
    sp.deleteSprite();
  }
  if (sp.createSprite(240, BOTTOM_H)) {
    drawBottom(sp, s, h);
    sp.pushSprite(0, BOTTOM_Y);
    sp.deleteSprite();
  }
}
