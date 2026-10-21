// 硬件探测固件：识别 ESP32 带屏开发板的屏幕驱动、触摸芯片与引脚接法。
// 结果通过串口（115200）周期性输出，同时在屏幕上轮流显示颜色以确认背光引脚。
#include <Arduino.h>
#include <SPI.h>
#include <Wire.h>

static String report;
static bool capTouchFound = false;  // 有电容触摸时 GPIO21 可能是其 INT，不驱动

static void out(const String &s) {
  report += s;
  report += '\n';
  Serial.println(s);
}

static String hex32(uint32_t v) {
  char b[12];
  snprintf(b, sizeof(b), "%08lX", (unsigned long)v);
  return String(b);
}

// ---------- 1. GPIO 外部上下拉检测 ----------
// 内部上拉/下拉约 45k，外部 10k 左右的上下拉会压过它，据此判断哪些脚接了外部电阻（如 I2C、触摸 IRQ）。
static void surveyGpio() {
  const int pins[] = {0, 2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33};
  const int inputOnly[] = {34, 35, 36, 39};
  String pu = "GPIO pullup-read : ", pd = "GPIO pulldown-read: ";
  for (int p : pins) {
    pinMode(p, INPUT_PULLUP);
    delayMicroseconds(200);
    int a = digitalRead(p);
    pinMode(p, INPUT_PULLDOWN);
    delayMicroseconds(200);
    int b = digitalRead(p);
    pinMode(p, INPUT);
    pu += String(p) + "=" + a + " ";
    pd += String(p) + "=" + b + " ";
  }
  out(pu);
  out(pd);
  String io = "GPIO input-only  : ";
  for (int p : inputOnly) {
    pinMode(p, INPUT);
    io += String(p) + "=" + digitalRead(p) + " ";
  }
  out(io);
  String ext = "=> external pull: ";
  for (int p : pins) {
    pinMode(p, INPUT_PULLUP);
    delayMicroseconds(200);
    int a = digitalRead(p);
    pinMode(p, INPUT_PULLDOWN);
    delayMicroseconds(200);
    int b = digitalRead(p);
    pinMode(p, INPUT);
    if (a == 0 && b == 0) ext += String(p) + ":LOW ";
    if (a == 1 && b == 1) ext += String(p) + ":HIGH ";
  }
  out(ext);
}

// ---------- 2. I2C 扫描（电容触摸：CST820/816=0x15, GT911=0x5D/0x14, FT6x36=0x38） ----------
static void scanI2c() {
  // CST820 复位脚在部分 2.4 寸板上是 GPIO25
  pinMode(25, OUTPUT);
  digitalWrite(25, LOW);
  delay(10);
  digitalWrite(25, HIGH);
  delay(150);
  const int pairs[][2] = {{33, 32}, {32, 33}, {21, 22}, {22, 21}, {27, 22}, {4, 16}};
  for (auto &pr : pairs) {
    Wire.begin(pr[0], pr[1], 100000);
    String s = "I2C SDA" + String(pr[0]) + " SCL" + String(pr[1]) + ": ";
    int found = 0;
    for (uint8_t a = 0x08; a < 0x78; a++) {
      Wire.beginTransmission(a);
      if (Wire.endTransmission() == 0) {
        char b[8];
        snprintf(b, sizeof(b), "0x%02X ", a);
        s += b;
        found++;
        if (a == 0x15 || a == 0x5D || a == 0x14 || a == 0x38) capTouchFound = true;
      }
    }
    if (!found) s += "(none)";
    out(s);
    Wire.end();
    pinMode(pr[0], INPUT);
    pinMode(pr[1], INPUT);
  }
  pinMode(25, INPUT);
}

// ---------- 位操作 SPI ----------
static int P_SCK, P_MOSI, P_MISO, P_CS, P_DC;

static inline void bbWait() { delayMicroseconds(1); }

static void bbWrite(uint8_t b) {
  for (int i = 7; i >= 0; i--) {
    digitalWrite(P_MOSI, (b >> i) & 1);
    bbWait();
    digitalWrite(P_SCK, HIGH);
    bbWait();
    digitalWrite(P_SCK, LOW);
  }
}

static uint32_t bbRead(int nbits, int pin) {
  uint32_t v = 0;
  for (int i = 0; i < nbits; i++) {
    digitalWrite(P_SCK, HIGH);
    bbWait();
    v = (v << 1) | (digitalRead(pin) & 1);
    digitalWrite(P_SCK, LOW);
    bbWait();
  }
  return v;
}

static void bbSetup(int sck, int mosi, int miso, int cs, int dc) {
  P_SCK = sck; P_MOSI = mosi; P_MISO = miso; P_CS = cs; P_DC = dc;
  pinMode(P_CS, OUTPUT);
  digitalWrite(P_CS, HIGH);
  pinMode(P_SCK, OUTPUT);
  digitalWrite(P_SCK, LOW);
  pinMode(P_MOSI, OUTPUT);
  if (P_DC >= 0) pinMode(P_DC, OUTPUT);
}

static void bbRelease() {
  for (int p : {P_SCK, P_MOSI, P_MISO, P_CS, P_DC})
    if (p >= 0) pinMode(p, INPUT);
}

static void lcdCmd(uint8_t c) {
  digitalWrite(P_CS, LOW);
  digitalWrite(P_DC, LOW);
  bbWrite(c);
  digitalWrite(P_CS, HIGH);
}

// 读 LCD 寄存器：发命令后读 32 位原始数据（含 dummy 位，交给人工解读）
// threeWire=true 时从 MOSI(SDA) 回读，用于没有 MISO 的屏
static uint32_t lcdRead(uint8_t cmd, bool threeWire, int pull) {
  int rp = threeWire ? P_MOSI : P_MISO;
  digitalWrite(P_CS, LOW);
  digitalWrite(P_DC, LOW);
  bbWrite(cmd);
  digitalWrite(P_DC, HIGH);
  pinMode(rp, pull);
  uint32_t v = bbRead(32, rp);
  if (threeWire) pinMode(P_MOSI, OUTPUT);
  digitalWrite(P_CS, HIGH);
  return v;
}

struct LcdCand { const char *name; int sck, mosi, miso, cs, dc; };
static const LcdCand lcdCands[] = {
  {"HSPI sck14 mosi13 miso12 cs15 dc2", 14, 13, 12, 15, 2},
  {"VSPI sck18 mosi23 miso19 cs5 dc16", 18, 23, 19, 5, 16},
  {"VSPI sck18 mosi23 miso19 cs15 dc2", 18, 23, 19, 15, 2},
};
static int lcdFound = -1;

// ---------- 3. LCD 控制器探测 ----------
static void probeLcd() {
  for (int i = 0; i < (int)(sizeof(lcdCands) / sizeof(lcdCands[0])); i++) {
    const LcdCand &c = lcdCands[i];
    bbSetup(c.sck, c.mosi, c.miso, c.cs, c.dc);
    lcdCmd(0x01);  // 软复位
    delay(150);
    lcdCmd(0x11);  // 退出睡眠
    delay(150);
    out(String("LCD [") + c.name + "]");
    bool driven = false;
    for (bool tw : {false, true}) {
      for (uint8_t reg : {0x04, 0x09, 0x0A, 0xD3, 0xDA, 0xDB, 0xDC}) {
        uint32_t up = lcdRead(reg, tw, INPUT_PULLUP);
        uint32_t dn = lcdRead(reg, tw, INPUT_PULLDOWN);
        bool d = (up == dn);
        if (d && reg == 0x04 && up != 0xFFFFFFFF && up != 0) driven = true;
        out(String("  ") + (tw ? "3wire" : "miso ") + " reg 0x" + String(reg, HEX) +
            " pu=" + hex32(up) + " pd=" + hex32(dn) + (d ? "  DRIVEN" : ""));
      }
    }
    bbRelease();
    if (driven && lcdFound < 0) lcdFound = i;
  }
  out(String("=> LCD candidate: ") + (lcdFound >= 0 ? lcdCands[lcdFound].name : "none (MISO 未接，回退到 HSPI 做显示测试)"));
  if (lcdFound < 0) lcdFound = 0;
}

// ---------- 4. 电阻触摸 XPT2046 探测 ----------
static uint16_t xptRead(uint8_t ctrl, int pull) {
  if (P_MISO >= 34) pull = INPUT;
  digitalWrite(P_CS, LOW);
  bbWrite(ctrl);
  pinMode(P_MISO, pull);
  uint32_t v = bbRead(16, P_MISO);
  digitalWrite(P_CS, HIGH);
  return (v >> 3) & 0xFFF;
}

static void probeXpt() {
  struct { const char *name; int sck, mosi, miso, cs; } cands[] = {
    {"shared HSPI sck14 mosi13 miso12 cs33", 14, 13, 12, 33},
    {"separate sck25 mosi32 miso39 cs33", 25, 32, 39, 33},
  };
  pinMode(15, OUTPUT);  // 让 LCD 片选保持无效，避免共享总线冲突
  digitalWrite(15, HIGH);
  pinMode(36, INPUT);
  for (auto &c : cands) {
    bbSetup(c.sck, c.mosi, c.miso, c.cs, -1);
    out(String("XPT2046 [") + c.name + "] IRQ36=" + digitalRead(36));
    xptRead(0x87, INPUT_PULLUP);  // 打开内部参考电压
    for (uint8_t ctrl : {0x87, 0xA7, 0xB3, 0xC3, 0x93, 0xD3}) {
      uint16_t up = xptRead(ctrl, INPUT_PULLUP);
      uint16_t dn = xptRead(ctrl, INPUT_PULLDOWN);
      out(String("  ctrl 0x") + String(ctrl, HEX) + " pu=" + up + " pd=" + dn +
          (up == dn ? "  DRIVEN" : ""));
    }
    bbRelease();
  }
  pinMode(15, INPUT);
}

// ---------- 5. 屏幕颜色测试（用硬件 SPI，确认背光脚） ----------
static SPIClass lcdSpi(HSPI);

static void hwCmd(uint8_t c) {
  digitalWrite(P_DC, LOW);
  digitalWrite(P_CS, LOW);
  lcdSpi.transfer(c);
  digitalWrite(P_CS, HIGH);
  digitalWrite(P_DC, HIGH);
}

static void hwData(const uint8_t *d, int n) {
  digitalWrite(P_CS, LOW);
  lcdSpi.transferBytes(d, nullptr, n);
  digitalWrite(P_CS, HIGH);
}

static void lcdInit() {
  const LcdCand &c = lcdCands[lcdFound];
  P_CS = c.cs; P_DC = c.dc;
  pinMode(P_CS, OUTPUT);
  digitalWrite(P_CS, HIGH);
  pinMode(P_DC, OUTPUT);
  lcdSpi.begin(c.sck, c.miso, c.mosi, -1);
  lcdSpi.beginTransaction(SPISettings(20000000, MSBFIRST, SPI_MODE0));
  hwCmd(0x01); delay(150);
  hwCmd(0x11); delay(150);
  uint8_t pix = 0x55; hwCmd(0x3A); hwData(&pix, 1);   // 16bit 色深
  uint8_t mad = 0x08; hwCmd(0x36); hwData(&mad, 1);   // 竖屏、BGR，不做 X 镜像
  hwCmd(0x29);
}

static void lcdFill(uint16_t color) {
  uint8_t ca[4] = {0, 0, 0, 239}, pa[4] = {0, 0, 0x01, 0x3F};
  hwCmd(0x2A); hwData(ca, 4);
  hwCmd(0x2B); hwData(pa, 4);
  hwCmd(0x2C);
  static uint8_t line[240 * 2];
  for (int i = 0; i < 240; i++) { line[2 * i] = color >> 8; line[2 * i + 1] = color & 0xFF; }
  digitalWrite(P_CS, LOW);
  for (int y = 0; y < 320; y++) lcdSpi.transferBytes(line, nullptr, sizeof(line));
  digitalWrite(P_CS, HIGH);
}

static void lcdRect(int x, int y, int w, int h, uint16_t color) {
  uint8_t ca[4] = {(uint8_t)(x >> 8), (uint8_t)x, (uint8_t)((x + w - 1) >> 8), (uint8_t)(x + w - 1)};
  uint8_t pa[4] = {(uint8_t)(y >> 8), (uint8_t)y, (uint8_t)((y + h - 1) >> 8), (uint8_t)(y + h - 1)};
  hwCmd(0x2A); hwData(ca, 4);
  hwCmd(0x2B); hwData(pa, 4);
  hwCmd(0x2C);
  uint8_t px[2] = {(uint8_t)(color >> 8), (uint8_t)color};
  digitalWrite(P_CS, LOW);
  for (int i = 0; i < w * h; i++) lcdSpi.transferBytes(px, nullptr, 2);
  digitalWrite(P_CS, HIGH);
}

void setup() {
  Serial.begin(115200);
  delay(500);
  out("===== HW PROBE START =====");
  surveyGpio();
  scanI2c();
  probeLcd();
  probeXpt();
  out("===== HW PROBE END =====");
  if (lcdFound >= 0) lcdInit();
}

void loop() {
  static uint32_t last = 0;
  if (millis() - last > 8000) {
    last = millis();
    Serial.println("\n----- REPORT (repeat) -----");
    Serial.print(report);
  }
  if (lcdFound < 0) { delay(100); return; }
  // 方向测试：白底，原点 40x40 黑块，沿 X 轴（y=0..7）画一条通栏黑条
  static bool drawn = false;
  if (!drawn) {
    pinMode(27, OUTPUT);
    digitalWrite(27, HIGH);
    lcdFill(0xFFFF);
    lcdRect(0, 0, 40, 40, 0x0000);
    lcdRect(0, 0, 240, 8, 0x0000);
    Serial.println("[orient] MADCTL=0x08 block@origin bar along X");
    drawn = true;
  }
  delay(100);
}
