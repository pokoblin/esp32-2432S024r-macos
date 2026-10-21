// Mac 系统状态副屏：从串口读 Mac 端每 2 秒发来的数据，画系统状态屏或 Claude / ChatGPT 用量屏。
// 当前是哪一屏由 Mac 端的 P 行决定；点一下屏幕就回一行 TAP，由 Mac 端切到下一屏。
// 没有 S 行超过 10 秒或收到 OFF 就关背光；中断超过 5 分钟后清空曲线。
#include <Arduino.h>

#include "board.h"
#include "history.h"
#include "line_reader.h"
#include "protocol.h"
#include "screen_state.h"
#include "tap.h"
#include "ui.h"
#include "usage_protocol.h"

static LGFX lcd;
static sysmon::LineReader reader;
static sysmon::ScreenState state;
static sysmon::History history;
static bool backlightOn = false;
static bool uiReady = false;

static sysmon::PageInfo page;
static sysmon::Usage usage[2];  // 0 是 Claude，1 是 ChatGPT
static sysmon::TapDetector tap;
// 停在用量屏时 S 行只记下来不画，切回系统状态屏时用它立即重画
static sysmon::Sample lastSample;
static bool hasSample = false;

static constexpr uint8_t BRIGHTNESS = 200;

static int usageIndex(sysmon::Service svc) { return svc == sysmon::Service::Claude ? 0 : 1; }

// 画当前页。用量屏的服务还没收到过 U 行时也照常画，底栏写“等待数据”
static void drawPage() {
  switch (page.page) {
    case sysmon::Page::Sys:
      if (hasSample) uiDraw(lcd, lastSample, history, page);
      break;
    case sysmon::Page::Claude:
      uiDrawUsage(lcd, usage[0], sysmon::Service::Claude, page);
      break;
    case sysmon::Page::ChatGPT:
      uiDrawUsage(lcd, usage[1], sysmon::Service::ChatGPT, page);
      break;
  }
}

static bool isCurrentPage(sysmon::Service svc) {
  return (svc == sysmon::Service::Claude && page.page == sysmon::Page::Claude) ||
         (svc == sysmon::Service::ChatGPT && page.page == sysmon::Page::ChatGPT);
}

// 一行不是 S / OFF 时，再试 P 行和 U 行
static void handleOtherLine(const char* line) {
  sysmon::PageInfo p;
  if (sysmon::parsePageLine(line, &p)) {
    bool changed = p.page != page.page || p.index != page.index || p.count != page.count;
    page = p;
    if (changed) drawPage();
    return;
  }
  sysmon::Usage u;
  if (sysmon::parseUsageLine(line, &u)) {
    usage[usageIndex(u.svc)] = u;
    // 底栏的“N 分钟前更新”会变，所以每个 U 行都重画
    if (isCurrentPage(u.svc)) drawPage();
  }
}

void setup() {
  Serial.begin(115200);
  lcd.init();
  lcd.setBrightness(0);
  lcd.fillScreen(TFT_BLACK);
  usage[0].svc = sysmon::Service::Claude;
  usage[1].svc = sysmon::Service::ChatGPT;
  pinMode(board::PIN_TOUCH_IRQ, INPUT);
  board::enablePenIrq(lcd);
  uiReady = uiBegin(lcd);
  // 没法画图时常亮显示报错，免得看起来像是没收到数据
  if (!uiReady) lcd.setBrightness(BRIGHTNESS);
}

void loop() {
  if (!uiReady) return;

  while (Serial.available() > 0) {
    if (!reader.feed((char)Serial.read())) continue;

    sysmon::Sample s;
    switch (sysmon::parseLine(reader.line(), &s)) {
      case sysmon::LineKind::Sample:
        if (state.onSample(millis())) history.clear();
        history.push(s.rx, s.tx);
        lastSample = s;
        hasSample = true;
        // 先画完再点亮，避免亮屏瞬间露出旧画面
        if (page.page == sysmon::Page::Sys) uiDraw(lcd, s, history, page);
        break;
      case sysmon::LineKind::Off:
        state.onOff();
        break;
      case sysmon::LineKind::Unknown:
        handleOtherLine(reader.line());
        break;
    }
  }

  uint32_t now = millis();
  state.tick(now);
  bool lit = state.lit(now);
  if (lit != backlightOn) {
    lcd.setBrightness(lit ? BRIGHTNESS : 0);
    backlightOn = lit;
  }
  // 熄屏时不发 TAP；按下状态照常跟踪，亮屏时还按着的手指不会算成一次点击
  if (tap.update(board::touchPressed(), now) && backlightOn) Serial.print("TAP\n");
  delay(10);
}
