// Mac 系统状态副屏：从串口读 Mac 端每 2 秒发来的一行数据，画圆环和网速曲线。
// 没有数据超过 10 秒或收到 OFF 就关背光；中断超过 5 分钟后清空曲线。
#include <Arduino.h>

#include "board.h"
#include "history.h"
#include "line_reader.h"
#include "protocol.h"
#include "screen_state.h"
#include "ui.h"

static LGFX lcd;
static sysmon::LineReader reader;
static sysmon::ScreenState state;
static sysmon::History history;
static bool backlightOn = false;

static constexpr uint8_t BRIGHTNESS = 200;

void setup() {
  Serial.begin(115200);
  lcd.init();
  lcd.setBrightness(0);
  lcd.fillScreen(TFT_BLACK);
}

void loop() {
  while (Serial.available() > 0) {
    if (!reader.feed((char)Serial.read())) continue;

    sysmon::Sample s;
    switch (sysmon::parseLine(reader.line(), &s)) {
      case sysmon::LineKind::Sample:
        if (state.onSample(millis())) history.clear();
        history.push(s.rx, s.tx);
        // 先画完再点亮，避免亮屏瞬间露出旧画面
        uiDraw(lcd, s, history);
        break;
      case sysmon::LineKind::Off:
        state.onOff();
        break;
      case sysmon::LineKind::Unknown:
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
  delay(10);
}
