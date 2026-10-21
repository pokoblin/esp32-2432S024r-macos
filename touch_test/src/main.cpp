// 触摸校准与画点测试（手指版）。
// 校准：5 个往屏幕内缩的大靶点，按住时多次采样取中位数，用最小二乘拟合「原始值→屏幕坐标」的仿射映射。
// 验证：另取 4 个点（不参与拟合）计算误差。之后进入画点模式。
// 映射参数保存在 NVS。开机时按住 BOOT 或点「校准」按钮可重新校准。
// 串口（115200）输出 [fit] / [acc] / [touch] 日志便于分析。
#include <Arduino.h>
#include <Preferences.h>
#include <algorithm>
#include "board.h"

static LGFX lcd;
static Preferences prefs;

static constexpr int PIN_BOOT_BTN = 0;
static constexpr int BAR_H = 28;
static constexpr int TARGET_R = 22;

// 仿射映射：sx = m[0]*rx + m[1]*ry + m[2]，sy = m[3]*rx + m[4]*ry + m[5]
static float m[6];
static bool haveMap = false;

struct Button { int x, y, w, h; const char *label; };
static const Button BTN_CLR = {82, 2, 50, 24, "清屏"};
static const Button BTN_TEST = {136, 2, 50, 24, "测试"};
static const Button BTN_CAL = {190, 2, 48, 24, "校准"};

static bool hit(const Button &b, int x, int y) {
  return x >= b.x && x < b.x + b.w && y >= b.y && y < b.y + b.h;
}

static void drawButton(const Button &b) {
  lcd.fillRoundRect(b.x, b.y, b.w, b.h, 4, TFT_DARKGREY);
  lcd.setTextColor(TFT_WHITE);
  lcd.setTextDatum(middle_center);
  lcd.drawString(b.label, b.x + b.w / 2, b.y + b.h / 2);
}

static void centerText(const char *s, int y, uint16_t color = TFT_WHITE) {
  lcd.setTextColor(color, TFT_BLACK);
  lcd.setTextDatum(middle_center);
  lcd.drawString(s, lcd.width() / 2, y);
}

static bool readRaw(int32_t &rx, int32_t &ry) {
  return board::readTouchRaw(lcd, rx, ry);
}

static void mapRaw(int32_t rx, int32_t ry, int32_t &sx, int32_t &sy) {
  sx = lroundf(m[0] * rx + m[1] * ry + m[2]);
  sy = lroundf(m[3] * rx + m[4] * ry + m[5]);
  sx = std::min<int32_t>(std::max<int32_t>(sx, 0), lcd.width() - 1);
  sy = std::min<int32_t>(std::max<int32_t>(sy, 0), lcd.height() - 1);
}

static void waitRelease() {
  int32_t rx, ry;
  uint32_t freeSince = millis();
  // 要求连续 120ms 无触摸才算松开，避免电阻屏手指抖动造成的断续
  while (millis() - freeSince < 120) {
    if (readRaw(rx, ry)) freeSince = millis();
    delay(10);
  }
}

// 等待一次按压：按下后先等 30ms 稳定，再采样直到松开（最多 1.5s），取中位数
static bool samplePress(int32_t &rx, int32_t &ry, int &count) {
  waitRelease();
  int32_t x, y;
  while (!readRaw(x, y)) delay(10);
  delay(30);
  static int32_t xs[150], ys[150];
  int n = 0, misses = 0;
  uint32_t t0 = millis();
  while (millis() - t0 < 1500 && n < 150) {
    if (readRaw(x, y)) {
      xs[n] = x; ys[n] = y; n++;
      misses = 0;
    } else if (++misses > 5) {
      break;
    }
    delay(10);
  }
  count = n;
  if (n < 3) return false;
  std::sort(xs, xs + n);
  std::sort(ys, ys + n);
  rx = xs[n / 2];
  ry = ys[n / 2];
  return true;
}

static void drawTarget(int x, int y, uint16_t c) {
  lcd.drawCircle(x, y, TARGET_R, c);
  lcd.drawCircle(x, y, TARGET_R - 1, c);
  lcd.drawLine(x - TARGET_R - 6, y, x + TARGET_R + 6, y, c);
  lcd.drawLine(x, y - TARGET_R - 6, x, y + TARGET_R + 6, c);
  lcd.fillCircle(x, y, 4, c);
}

static void clearTarget(int x, int y) {
  int r = TARGET_R + 7;
  lcd.fillRect(x - r, y - r, 2 * r + 1, 2 * r + 1, TFT_BLACK);
}

// 依次显示靶点并采样，失败（采样太少）就重来这个点
static void collectPoint(int tx, int ty, int idx, int total, const char *title,
                         int32_t &rx, int32_t &ry) {
  char buf[40];
  snprintf(buf, sizeof(buf), "%s  %d / %d", title, idx, total);
  lcd.fillRect(0, 140, lcd.width(), 40, TFT_BLACK);
  // 靶点在中心时提示文字让到下方
  int textY = (ty > 120 && ty < 200) ? 215 : 150;
  lcd.fillRect(0, textY - 10, lcd.width(), 44, TFT_BLACK);
  centerText(buf, textY);
  centerText("用指腹按一下靶心", textY + 20, TFT_LIGHTGREY);
  drawTarget(tx, ty, TFT_YELLOW);
  int n;
  while (!samplePress(rx, ry, n)) {
    Serial.printf("[sample] too few samples (%d), retry\n", n);
    drawTarget(tx, ty, TFT_RED);
    delay(300);
    drawTarget(tx, ty, TFT_YELLOW);
  }
  Serial.printf("[sample] target=(%d,%d) raw=(%ld,%ld) n=%d\n", tx, ty, (long)rx, (long)ry, n);
  drawTarget(tx, ty, TFT_GREEN);
  delay(250);
  clearTarget(tx, ty);
  lcd.fillRect(0, textY - 10, lcd.width(), 44, TFT_BLACK);
}

// 解 3x3 线性方程组（高斯消元）
static bool solve3(double A[3][3], double b[3], double out[3]) {
  for (int c = 0; c < 3; c++) {
    int p = c;
    for (int r = c + 1; r < 3; r++)
      if (fabs(A[r][c]) > fabs(A[p][c])) p = r;
    if (fabs(A[p][c]) < 1e-9) return false;
    for (int k = 0; k < 3; k++) std::swap(A[c][k], A[p][k]);
    std::swap(b[c], b[p]);
    for (int r = c + 1; r < 3; r++) {
      double f = A[r][c] / A[c][c];
      for (int k = c; k < 3; k++) A[r][k] -= f * A[c][k];
      b[r] -= f * b[c];
    }
  }
  for (int r = 2; r >= 0; r--) {
    double s = b[r];
    for (int k = r + 1; k < 3; k++) s -= A[r][k] * out[k];
    out[r] = s / A[r][r];
  }
  return true;
}

// 最小二乘拟合仿射映射
static bool fitAffine(const int32_t *rx, const int32_t *ry, const int *sx, const int *sy, int n) {
  double A[3][3] = {}, bx[3] = {}, by[3] = {};
  for (int i = 0; i < n; i++) {
    double v[3] = {(double)rx[i], (double)ry[i], 1.0};
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 3; c++) A[r][c] += v[r] * v[c];
      bx[r] += v[r] * sx[i];
      by[r] += v[r] * sy[i];
    }
  }
  double A2[3][3];
  memcpy(A2, A, sizeof(A));
  double px[3], py[3];
  if (!solve3(A, bx, px) || !solve3(A2, by, py)) return false;
  for (int i = 0; i < 3; i++) {
    m[i] = px[i];
    m[3 + i] = py[i];
  }
  return true;
}

static void runCalibration() {
  const int pts[][2] = {{30, 30}, {210, 30}, {120, 160}, {30, 290}, {210, 290}};
  const int n = 5;
  int32_t rx[n], ry[n];
  int sx[n], sy[n];
  lcd.fillScreen(TFT_BLACK);
  for (int i = 0; i < n; i++) {
    sx[i] = pts[i][0];
    sy[i] = pts[i][1];
    collectPoint(sx[i], sy[i], i + 1, n, "触摸校准", rx[i], ry[i]);
  }
  if (!fitAffine(rx, ry, sx, sy, n)) {
    Serial.println("[fit] failed (singular), retry");
    lcd.fillScreen(TFT_BLACK);
    centerText("校准失败，请重试", 160, TFT_RED);
    delay(1500);
    runCalibration();
    return;
  }
  float worst = 0;
  for (int i = 0; i < n; i++) {
    float ex = m[0] * rx[i] + m[1] * ry[i] + m[2] - sx[i];
    float ey = m[3] * rx[i] + m[4] * ry[i] + m[5] - sy[i];
    worst = std::max(worst, sqrtf(ex * ex + ey * ey));
  }
  Serial.printf("[fit] m= %.6f %.6f %.2f %.6f %.6f %.2f  fit_resid_max=%.1f\n",
                m[0], m[1], m[2], m[3], m[4], m[5], worst);
  prefs.putBytes("aff", m, sizeof(m));
  haveMap = true;
}

static void runAccuracyTest() {
  // 验证点不与校准点重合，检验拟合在其他位置是否也准
  const int pts[][2] = {{120, 45}, {30, 160}, {210, 160}, {120, 275}};
  const int n = 4;
  float sum = 0, worst = 0;
  lcd.fillScreen(TFT_BLACK);
  int32_t gx[n], gy[n];
  for (int i = 0; i < n; i++) {
    int32_t rx, ry;
    collectPoint(pts[i][0], pts[i][1], i + 1, n, "精度验证", rx, ry);
    mapRaw(rx, ry, gx[i], gy[i]);
    float dx = gx[i] - pts[i][0], dy = gy[i] - pts[i][1];
    float err = sqrtf(dx * dx + dy * dy);
    sum += err;
    worst = std::max(worst, err);
    Serial.printf("[acc] %d target=(%d,%d) got=(%ld,%ld) raw=(%ld,%ld) err=%.1f\n", i + 1,
                  pts[i][0], pts[i][1], (long)gx[i], (long)gy[i], (long)rx, (long)ry, err);
  }
  // 汇总画面：灰色十字是目标，圆点是实际落点（绿色 ≤10px，红色 >10px）
  lcd.fillScreen(TFT_BLACK);
  for (int i = 0; i < n; i++) {
    float dx = gx[i] - pts[i][0], dy = gy[i] - pts[i][1];
    drawTarget(pts[i][0], pts[i][1], TFT_DARKGREY);
    lcd.fillCircle(gx[i], gy[i], 4, sqrtf(dx * dx + dy * dy) <= 10 ? TFT_GREEN : TFT_RED);
  }
  float avg = sum / n;
  Serial.printf("[acc] summary avg=%.1f max=%.1f\n", avg, worst);
  char buf[48];
  snprintf(buf, sizeof(buf), "平均误差 %.1f px，最大 %.1f px", avg, worst);
  centerText(buf, 205);
  centerText(worst <= 12 ? "手指操作精度良好" : "误差偏大，建议重新校准", 225,
             worst <= 12 ? TFT_GREEN : TFT_ORANGE);
  centerText("点击任意位置继续", 245, TFT_LIGHTGREY);
  int32_t a, b;
  int c;
  samplePress(a, b, c);
  waitRelease();
}

static void drawUi() {
  lcd.fillScreen(TFT_BLACK);
  lcd.fillRect(0, 0, lcd.width(), BAR_H, 0x2104);
  drawButton(BTN_CLR);
  drawButton(BTN_TEST);
  drawButton(BTN_CAL);
}

static void showCoords(int x, int y) {
  char buf[16];
  snprintf(buf, sizeof(buf), "%d,%d", x, y);
  lcd.fillRect(0, 0, 80, BAR_H, 0x2104);
  lcd.setTextColor(TFT_WHITE);
  lcd.setTextDatum(middle_left);
  lcd.drawString(buf, 4, BAR_H / 2);
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_BOOT_BTN, INPUT_PULLUP);
  lcd.init();
  lcd.setRotation(0);
  lcd.setBrightness(200);
  lcd.setFont(&fonts::efontCN_14);

  prefs.begin("touch", false);
  bool saved = prefs.getBytesLength("aff") == sizeof(m);
  bool forceCal = digitalRead(PIN_BOOT_BTN) == LOW;
  if (saved && !forceCal) {
    prefs.getBytes("aff", m, sizeof(m));
    haveMap = true;
    Serial.printf("[fit] loaded m= %.6f %.6f %.2f %.6f %.6f %.2f\n", m[0], m[1], m[2], m[3], m[4], m[5]);
  } else {
    Serial.println(forceCal ? "[fit] BOOT held, recalibrating" : "[fit] no saved data, calibrating");
    runCalibration();
    runAccuracyTest();
  }
  drawUi();
  Serial.println("[ready] draw mode");
}

void loop() {
  static int32_t lastX = -1, lastY = -1;
  static uint32_t lastLog = 0, lastSeen = 0;
  int32_t rx, ry;
  if (!readRaw(rx, ry)) {
    // 短暂断触（<60ms）不算松开，保证拖动连线连续
    if (millis() - lastSeen > 60) lastX = lastY = -1;
    delay(5);
    return;
  }
  lastSeen = millis();
  int32_t x, y;
  mapRaw(rx, ry, x, y);
  if (millis() - lastLog > 100) {
    Serial.printf("[touch] %ld %ld raw %ld %ld\n", (long)x, (long)y, (long)rx, (long)ry);
    lastLog = millis();
  }
  if (y < BAR_H) {
    if (lastX < 0) {  // 只响应新按下，避免拖进工具栏时误触
      if (hit(BTN_CLR, x, y)) {
        drawUi();
      } else if (hit(BTN_TEST, x, y)) {
        runAccuracyTest();
        drawUi();
      } else if (hit(BTN_CAL, x, y)) {
        runCalibration();
        runAccuracyTest();
        drawUi();
      }
      waitRelease();
    }
    lastX = lastY = -1;
    return;
  }
  // 连续按住时连线，单点按下画圆点
  if (lastX >= 0 && abs(x - lastX) < 40 && abs(y - lastY) < 40) {
    lcd.drawWideLine(lastX, lastY, x, y, 2, TFT_CYAN);
  } else {
    lcd.fillCircle(x, y, 4, TFT_CYAN);
  }
  lastX = x;
  lastY = y;
  showCoords(x, y);
}
