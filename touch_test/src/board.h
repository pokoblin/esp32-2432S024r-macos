// ESP32-2432S024R 的 LovyanGFX 配置：ST7789 + XPT2046，两者共用 HSPI 总线。
// 引脚已在实机验证（见 hw_probe 探测结果）。
// 屏幕 MISO 未接读不出 ID；用 Panel_ILI9341 时其初始化里的 0xC0=0x23 在 ST7789 上是 LCMCTRL，
// 会导致画面转置+镜像，由此判断控制器实为 ST7789。
#pragma once
#define LGFX_USE_V1
#include <Arduino.h>
#include <LovyanGFX.hpp>
#include <algorithm>

class LGFX : public lgfx::LGFX_Device {
  lgfx::Panel_ST7789 _panel;
  lgfx::Bus_SPI _bus;
  lgfx::Light_PWM _light;
  lgfx::Touch_XPT2046 _touch;

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
      cfg.pin_miso = 12;  // 屏幕 SDO 未接，此脚只给触摸芯片用
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
    {
      auto cfg = _touch.config();
      cfg.spi_host = HSPI_HOST;
      cfg.freq = 1000000;
      cfg.pin_sclk = 14;
      cfg.pin_mosi = 13;
      cfg.pin_miso = 12;
      cfg.pin_cs = 33;
      cfg.pin_int = 36;
      cfg.bus_shared = true;
      cfg.offset_rotation = 0;
      // 原始量程占位值；坐标映射由应用自己的校准决定
      cfg.x_min = 0;
      cfg.x_max = 4095;
      cfg.y_min = 0;
      cfg.y_max = 4095;
      _touch.config(cfg);
      _panel.setTouch(&_touch);
    }
    setPanel(&_panel);
  }
};

// 读取 XPT2046 原始坐标。
// 不用 LovyanGFX 的 getTouchRaw：它按 z = 0x3200 + y - x + (Z1-Z2)/2 判定按下，
// 手指轻点时结果为负会被当成未按下。这里改用芯片的 PENIRQ（GPIO36，按下为低）判定，
// 再连续采样取中位数。z1 可选输出，用于粗略判断按压力度。
namespace board {
constexpr int PIN_TOUCH_IRQ = 36;
constexpr int PIN_TOUCH_CS = 33;

inline bool readTouchRaw(LGFX &lcd, int32_t &rx, int32_t &ry, int32_t *z1 = nullptr) {
  if (digitalRead(PIN_TOUCH_IRQ)) return false;
  constexpr int REPS = 5;
  // 每次测量占 3 字节：命令 + 2 字节结果；最后发 0x80 回到省电模式并重新使能 PENIRQ
  uint8_t d[REPS * 9 + 3] = {};
  for (int r = 0; r < REPS; r++) {
    d[r * 9 + 0] = 0xD1;  // X
    d[r * 9 + 3] = 0x91;  // Y
    d[r * 9 + 6] = 0xB1;  // Z1
  }
  d[REPS * 9] = 0x80;
  lcd.waitDMA();
  lgfx::spi::beginTransaction(HSPI_HOST, 1000000, 0);
  lgfx::gpio_lo(PIN_TOUCH_CS);
  lgfx::spi::readBytes(HSPI_HOST, d, sizeof(d));
  lgfx::gpio_hi(PIN_TOUCH_CS);
  lgfx::spi::endTransaction(HSPI_HOST);

  int32_t xs[REPS], ys[REPS], zs[REPS];
  int n = 0;
  for (int r = 0; r < REPS; r++) {
    auto v = [&](int o) { return (int32_t)((d[r * 9 + o + 1] << 8 | d[r * 9 + o + 2]) >> 3); };
    int32_t x = v(0), y = v(3), z = v(6);
    // 两端读数通常是接触不良或刚抬起，丢掉
    if (x < 100 || x > 4000 || y < 100 || y > 4000) continue;
    xs[n] = x; ys[n] = y; zs[n] = z; n++;
  }
  if (n < 3) return false;
  std::sort(xs, xs + n);
  std::sort(ys, ys + n);
  std::sort(zs, zs + n);
  rx = xs[n / 2];
  ry = ys[n / 2];
  if (z1) *z1 = zs[n / 2];
  return true;
}
}  // namespace board
