// 触摸原始信号诊断：绕开显示库，直接用位操作 SPI 读 XPT2046。
// 每 100ms 输出一次 IRQ 电平与 Z1/Z2/X/Y 原始值，用于判断按压时芯片是否有反应。
#include <Arduino.h>

static constexpr int P_SCK = 14, P_MOSI = 13, P_MISO = 12, P_TCS = 33, P_IRQ = 36;
static constexpr int P_LCD_CS = 15, P_BL = 27;

static uint16_t xpt(uint8_t ctrl) {
  digitalWrite(P_TCS, LOW);
  for (int i = 7; i >= 0; i--) {
    digitalWrite(P_MOSI, (ctrl >> i) & 1);
    delayMicroseconds(2);
    digitalWrite(P_SCK, HIGH);
    delayMicroseconds(2);
    digitalWrite(P_SCK, LOW);
  }
  digitalWrite(P_MOSI, LOW);
  uint32_t v = 0;
  for (int i = 0; i < 16; i++) {
    digitalWrite(P_SCK, HIGH);
    delayMicroseconds(2);
    v = (v << 1) | digitalRead(P_MISO);
    digitalWrite(P_SCK, LOW);
    delayMicroseconds(2);
  }
  digitalWrite(P_TCS, HIGH);
  return (v >> 3) & 0xFFF;
}

void setup() {
  Serial.begin(115200);
  pinMode(P_LCD_CS, OUTPUT);
  digitalWrite(P_LCD_CS, HIGH);  // 屏幕片选无效，避免占用总线
  pinMode(P_BL, OUTPUT);
  digitalWrite(P_BL, HIGH);      // 点亮背光，方便用户看清按压位置
  pinMode(P_TCS, OUTPUT);
  digitalWrite(P_TCS, HIGH);
  pinMode(P_SCK, OUTPUT);
  digitalWrite(P_SCK, LOW);
  pinMode(P_MOSI, OUTPUT);
  pinMode(P_MISO, INPUT_PULLUP);
  pinMode(P_IRQ, INPUT);
  delay(300);
  Serial.printf("[diag] start temp0=%u (约 800 表示芯片在线)\n", xpt(0x87));
  xpt(0xD0);  // PD=00 让 PENIRQ 生效
}

void loop() {
  static uint32_t n = 0, irqLow = 0, zHigh = 0;
  // 先在空闲态读 IRQ，再做转换（转换期间 IRQ 不可靠）
  int irq = digitalRead(P_IRQ);
  uint16_t z1 = xpt(0xB1), z2 = xpt(0xC1), x = xpt(0xD1), y = xpt(0x91);
  xpt(0xD0);  // 结束时回到 PD=00，恢复 PENIRQ
  n++;
  if (irq == 0) irqLow++;
  if (z1 > 100) zHigh++;
  Serial.printf("[raw] irq=%d z1=%4u z2=%4u x=%4u y=%4u%s\n", irq, z1, z2, x, y,
                (irq == 0 || z1 > 100) ? "  <== PRESS?" : "");
  if (n % 50 == 0) Serial.printf("[sum] samples=%lu irq_low=%lu z1_high=%lu\n", n, irqLow, zHigh);
  delay(100);
}
