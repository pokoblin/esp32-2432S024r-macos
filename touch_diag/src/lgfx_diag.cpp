// LovyanGFX 触摸读取诊断：对比 IRQ 电平、getTouchRaw 结果与手动 SPI 读回的原始字节。
#include <Arduino.h>
#include "board.h"

static LGFX lcd;

// 复刻 Touch_XPT2046::getTouchRaw 的 SPI 交互，只读一组（Y、Z1、X、Z2）
static void manualRead(uint16_t &y, uint16_t &z1, uint16_t &x, uint16_t &z2) {
  uint8_t d[10] = {0x91, 0, 0xB1, 0, 0xD1, 0, 0xC1, 0, 0, 0x80};
  lcd.endWrite();
  lgfx::spi::beginTransaction(HSPI_HOST, 1000000, 0);
  lgfx::gpio_lo(33);
  lgfx::spi::readBytes(HSPI_HOST, d, sizeof(d));
  lgfx::gpio_hi(33);
  lgfx::spi::endTransaction(HSPI_HOST);
  y = (d[1] << 8 | d[2]) >> 3;
  z1 = (d[3] << 8 | d[4]) >> 3;
  x = (d[5] << 8 | d[6]) >> 3;
  z2 = (d[7] << 8 | d[8]) >> 3;
}

void setup() {
  Serial.begin(115200);
  bool ok = lcd.init();
  lcd.setFont(&fonts::efontCN_14);
  lcd.fillScreen(TFT_BLACK);
  // 方向/颜色测试：四角色块
  lcd.fillRect(0, 0, 40, 40, TFT_RED);
  lcd.fillRect(200, 0, 40, 40, TFT_GREEN);
  lcd.fillRect(0, 280, 40, 40, TFT_BLUE);
  lcd.fillRect(200, 280, 40, 40, TFT_WHITE);
  lcd.drawRect(0, 0, 240, 320, TFT_YELLOW);
  lcd.setTextColor(TFT_WHITE, TFT_BLACK);
  lcd.setTextDatum(middle_center);
  lcd.drawString("左上红 右上绿", 120, 70);
  lcd.drawString("左下蓝 右下白", 120, 95);
  lcd.drawString("触摸诊断：请按住屏幕", 120, 130);
  Serial.printf("[lgfx] init=%d touch=%p startCount=%d\n", ok, lcd.touch(), lcd.getStartCount());
}

void loop() {
  int irq = digitalRead(36);
  lgfx::touch_point_t tp = {};
  int cnt = lcd.getTouchRaw(&tp);
  int irq2 = digitalRead(36);
  uint16_t y, z1, x, z2;
  manualRead(y, z1, x, z2);
  bool press = irq == 0 || cnt > 0 || z1 > 100;
  Serial.printf("[lgfx] irq=%d cnt=%d tp=(%d,%d,s%d) irq_after=%d | manual y=%u z1=%u x=%u z2=%u%s\n",
                irq, cnt, tp.x, tp.y, tp.size, irq2, y, z1, x, z2, press ? "  <== PRESS?" : "");
  char buf[64];
  snprintf(buf, sizeof(buf), "IRQ=%d  库读数=%d  Z1=%u   ", irq, cnt, z1);
  lcd.drawString(buf, 120, 160);
  delay(150);
}
