// ESP32-2432S024R 的 LovyanGFX 屏幕配置（ST7789，HSPI）。
// 取自 touch_test/src/board.h，去掉了本项目用不到的 XPT2046 触摸部分。
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
