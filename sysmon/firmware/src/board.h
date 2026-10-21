// ESP32-2432S024R 的 LovyanGFX 屏幕配置（ST7789，HSPI）。
// 取自 touch_test/src/board.h。触摸只用来判断有没有按下，不读坐标，所以没有接 LovyanGFX 的触摸驱动，
// 只靠 XPT2046 的 PENIRQ 脚。
// 屏幕 MISO 未接读不出 ID；用 Panel_ILI9341 时其初始化里的 0xC0=0x23 在 ST7789 上是 LCMCTRL，
// 会导致画面转置+镜像，由此判断控制器实为 ST7789。
#pragma once
#define LGFX_USE_V1
#include <Arduino.h>
#include <LovyanGFX.hpp>

class LGFX : public lgfx::LGFX_Device {
  lgfx::Panel_ST7789 _panel;
  lgfx::Bus_SPI _bus;
  lgfx::Light_PWM _light;

 public:
  LGFX() {
    {
      auto cfg = _bus.config();
      cfg.spi_host = HSPI_HOST;
      cfg.spi_mode = 0;
      cfg.freq_write = 27000000;
      cfg.freq_read = 16000000;
      cfg.spi_3wire = false;
      cfg.use_lock = true;
      cfg.dma_channel = SPI_DMA_CH_AUTO;
      cfg.pin_sclk = 14;
      cfg.pin_mosi = 13;
      cfg.pin_miso = 12;  // 屏幕 SDO 未接，此脚原本只给触摸芯片用
      cfg.pin_dc = 2;
      _bus.config(cfg);
      _panel.setBus(&_bus);
    }
    {
      auto cfg = _panel.config();
      cfg.pin_cs = 15;
      cfg.pin_rst = -1;  // 复位接在 EN 上
      cfg.pin_busy = -1;
      cfg.panel_width = 240;
      cfg.panel_height = 320;
      cfg.memory_width = 240;
      cfg.memory_height = 320;
      cfg.offset_x = 0;
      cfg.offset_y = 0;
      cfg.offset_rotation = 0;
      cfg.readable = false;     // 屏幕 MISO 未接，不能回读
      cfg.invert = false;
      cfg.rgb_order = false;    // 实测：设 true 时红蓝互换
      cfg.dlen_16bit = false;
      cfg.bus_shared = true;
      _panel.config(cfg);
    }
    {
      auto cfg = _light.config();
      cfg.pin_bl = 27;
      cfg.invert = false;
      cfg.freq = 44100;
      cfg.pwm_channel = 7;
      _light.config(cfg);
      _panel.setLight(&_light);
    }
    setPanel(&_panel);
  }
};

namespace board {
constexpr int PIN_TOUCH_IRQ = 36, PIN_TOUCH_CS = 33;

// 给 XPT2046 发一个 0x80：进入省电模式并使能 PENIRQ，之后按下时 IRQ 脚变低。
// 触摸和屏幕共用 HSPI，做法照 touch_test 的 readTouchRaw：等屏幕 DMA 结束，再单独开一次传输。
// 调用前 PIN_TOUCH_IRQ 要设成输入（GPIO36 只能输入，也没有内部上拉）。
inline void enablePenIrq(LGFX& lcd) {
  pinMode(PIN_TOUCH_CS, OUTPUT);
  digitalWrite(PIN_TOUCH_CS, HIGH);
  uint8_t cmd = 0x80;
  lcd.waitDMA();
  lgfx::spi::beginTransaction(HSPI_HOST, 1000000, 0);
  lgfx::gpio_lo(PIN_TOUCH_CS);
  lgfx::spi::readBytes(HSPI_HOST, &cmd, 1);
  lgfx::gpio_hi(PIN_TOUCH_CS);
  lgfx::spi::endTransaction(HSPI_HOST);
}

// 按下时 PENIRQ 为低
inline bool touchPressed() { return digitalRead(PIN_TOUCH_IRQ) == LOW; }
}  // namespace board
