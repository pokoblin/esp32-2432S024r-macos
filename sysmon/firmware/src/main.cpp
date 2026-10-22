// Mac 系统状态副屏：从串口读 Mac 端每 2 秒发来的数据，画系统状态屏、番茄屏或 Claude / ChatGPT 用量屏。
// 当前是哪一屏由 Mac 端的 P 行决定；点一下屏幕就回一行 TAP，由 Mac 端切到下一屏（有横幅时是关横幅）。
// 番茄倒计时按 T 行的剩余秒数在本地每秒往下走；B 行有横幅时整屏画横幅，RGB 灯跟着呼吸。
// 没有 S 行超过 10 秒或收到 OFF 就关背光；中断超过 5 分钟后清空曲线。
#include <Arduino.h>

#include "board.h"
#include "breathe.h"
#include "history.h"
#include "line_reader.h"
#include "protocol.h"
#include "rgb_led.h"
#include "screen_state.h"
#include "tap.h"
#include "timer_protocol.h"
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

static sysmon::Timer timer;
static uint32_t timerMs = 0;   // 收到 T 行时的 millis()
static int32_t shownRem = -1;  // 屏幕上正显示的剩余秒数
static sysmon::Banner banner;
static bool ledLit = false;
static uint32_t ledMs = 0;

static constexpr uint8_t BRIGHTNESS = 200;
static constexpr uint32_t LED_FRAME_MS = 20;

static int32_t timerRem() { return sysmon::timerRemaining(timer, timerMs, millis()); }

static int usageIndex(sysmon::Service svc) { return svc == sysmon::Service::Claude ? 0 : 1; }

// 画当前页；有横幅时画横幅。用量屏的服务还没收到过 U 行时也照常画，底栏写“等待数据”
static void drawPage() {
  int32_t rem = timerRem();
  shownRem = rem;
  if (banner.kind != sysmon::BannerKind::None) {
    uiDrawBanner(lcd, banner, timer, rem);
    return;
  }
  switch (page.page) {
    case sysmon::Page::Sys:
      if (hasSample) uiDraw(lcd, lastSample, history, page, timer, rem);
      break;
    case sysmon::Page::Pomo:
      uiDrawPomodoro(lcd, timer, rem, page);
      break;
    case sysmon::Page::Claude:
      uiDrawUsage(lcd, usage[0], sysmon::Service::Claude, page, timer, rem);
      break;
    case sysmon::Page::ChatGPT:
      uiDrawUsage(lcd, usage[1], sysmon::Service::ChatGPT, page, timer, rem);
      break;
  }
}

// 当前画面上有没有按秒走的倒计时（别的屏顶边的进度线跟着 S、U 行 2 秒重画一次就够了）
static bool showsCountdown() {
  if (banner.kind != sysmon::BannerKind::None) return banner.kind == sysmon::BannerKind::FocusDone;
  return page.page == sysmon::Page::Pomo;
}

static bool isCurrentPage(sysmon::Service svc) {
  return (svc == sysmon::Service::Claude && page.page == sysmon::Page::Claude) ||
         (svc == sysmon::Service::ChatGPT && page.page == sysmon::Page::ChatGPT);
}

// 一行不是 S / OFF 时，再试 P、U、T、B 行
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
    // 底栏的“N 分钟前更新”会变，所以每个 U 行都重画；横幅盖着时只记数据
    if (isCurrentPage(u.svc) && banner.kind == sysmon::BannerKind::None) drawPage();
    return;
  }
  sysmon::Timer t;
  if (sysmon::parseTimerLine(line, &t)) {
    bool changed = t.phase != timer.phase || t.running != timer.running || t.rd != timer.rd ||
                   t.dn != timer.dn || t.key != timer.key || t.tot != timer.tot;
    timer = t;
    timerMs = millis();
    // 阶段变了（开始、暂停等）立刻重画，进度线也跟着出现或消失；只是校准秒数的话交给每秒刷新
    if (changed) drawPage();
    return;
  }
  sysmon::Banner b;
  if (sysmon::parseBannerLine(line, &b)) {
    bool changed = b.kind != banner.kind || b.min != banner.min || b.xw != banner.xw || b.xs != banner.xs;
    banner = b;
    if (changed) drawPage();
  }
}

// 横幅显示且灯开着时按横幅颜色呼吸；其他时候（包括熄屏）灭
static void updateLed(uint32_t now) {
  bool want = backlightOn && banner.led && banner.kind != sysmon::BannerKind::None;
  if (want) {
    if (now - ledMs < LED_FRAME_MS) return;
    ledMs = now;
    rgbled::write(sysmon::scaleRgb(sysmon::bannerLedColor(banner.kind), sysmon::breatheLevel(now)));
    ledLit = true;
  } else if (ledLit) {
    rgbled::write({0, 0, 0});
    ledLit = false;
  }
}

void setup() {
  Serial.begin(115200);
  lcd.init();
  lcd.setBrightness(0);
  lcd.fillScreen(TFT_BLACK);
  usage[0].svc = sysmon::Service::Claude;
  usage[1].svc = sysmon::Service::ChatGPT;
  rgbled::begin();
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
        // 先画完再点亮，避免亮屏瞬间露出旧画面；横幅盖着时只记数据
        if (page.page == sysmon::Page::Sys && banner.kind == sysmon::BannerKind::None) drawPage();
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
  // 倒计时每过一秒重画一次（整屏约 50ms）
  if (timer.running && showsCountdown() && timerRem() != shownRem) drawPage();
  updateLed(now);

  // 熄屏时不发 TAP；按下状态照常跟踪，亮屏时还按着的手指不会算成一次点击
  if (tap.update(board::touchPressed(), now) && backlightOn) Serial.print("TAP\n");
  delay(10);
}
