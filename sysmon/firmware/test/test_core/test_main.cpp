#include <unity.h>
#include <string.h>

#include "banner_glyphs.h"
#include "breathe.h"
#include "format.h"
#include "history.h"
#include "line_reader.h"
#include "protocol.h"
#include "screen_state.h"
#include "tap.h"
#include "timer_format.h"
#include "timer_protocol.h"
#include "tones.h"
#include "usage_format.h"
#include "usage_protocol.h"

using namespace sysmon;

void setUp() {}
void tearDown() {}

// ---- protocol ----

static void test_parse_full_line() {
  Sample s{};
  TEST_ASSERT_EQUAL(LineKind::Sample, parseLine("S cpu=37 mem=51 lvl=1 rx=13002342 tx=880640", &s));
  TEST_ASSERT_EQUAL(37, s.cpu);
  TEST_ASSERT_EQUAL(51, s.mem);
  TEST_ASSERT_EQUAL(1, s.level);
  TEST_ASSERT_EQUAL_UINT32(13002342, s.rx);
  TEST_ASSERT_EQUAL_UINT32(880640, s.tx);
}

static void test_parse_off() {
  Sample s{};
  TEST_ASSERT_EQUAL(LineKind::Off, parseLine("OFF", &s));
}

static void test_parse_unknown_field_and_default_level() {
  Sample s{};
  TEST_ASSERT_EQUAL(LineKind::Sample, parseLine("S cpu=1 mem=2 rx=3 tx=4 foo=9", &s));
  TEST_ASSERT_EQUAL(1, s.level);
  TEST_ASSERT_EQUAL_UINT32(3, s.rx);
  TEST_ASSERT_EQUAL_UINT32(4, s.tx);
}

static void test_parse_clamps() {
  Sample s{};
  TEST_ASSERT_EQUAL(LineKind::Sample, parseLine("S cpu=150 mem=-5 lvl=2 rx=0 tx=0", &s));
  TEST_ASSERT_EQUAL(100, s.cpu);
  TEST_ASSERT_EQUAL(0, s.mem);
  TEST_ASSERT_EQUAL(2, s.level);
}

static void test_parse_rx_saturates() {
  Sample s{};
  TEST_ASSERT_EQUAL(LineKind::Sample, parseLine("S cpu=1 mem=1 rx=99999999999 tx=1", &s));
  TEST_ASSERT_EQUAL_UINT32(4294967295u, s.rx);
}

static void test_parse_rejects() {
  Sample s{};
  TEST_ASSERT_EQUAL(LineKind::Unknown, parseLine("", &s));
  TEST_ASSERT_EQUAL(LineKind::Unknown, parseLine("garbage", &s));
  TEST_ASSERT_EQUAL(LineKind::Unknown, parseLine("S cpu=37", &s));
  TEST_ASSERT_EQUAL(LineKind::Unknown, parseLine("S cpu=37 mem=1 rx=1", &s));
  TEST_ASSERT_EQUAL(LineKind::Unknown, parseLine("S cpu=abc mem=1 rx=1 tx=1", &s));
  TEST_ASSERT_EQUAL(LineKind::Unknown, parseLine("HELLO v1", &s));
}

// ---- line reader ----

static bool feedAll(LineReader& r, const char* s) {
  bool ready = false;
  for (const char* p = s; *p; ++p) ready = r.feed(*p);
  return ready;
}

static void test_line_reader_basic() {
  LineReader r;
  TEST_ASSERT_FALSE(r.feed('O'));
  TEST_ASSERT_FALSE(r.feed('F'));
  TEST_ASSERT_FALSE(r.feed('F'));
  TEST_ASSERT_FALSE(r.feed('\r'));
  TEST_ASSERT_TRUE(r.feed('\n'));
  TEST_ASSERT_EQUAL_STRING("OFF", r.line());
}

static void test_line_reader_overlong_dropped() {
  LineReader r;
  for (int i = 0; i < 200; ++i) TEST_ASSERT_FALSE(r.feed('x'));
  TEST_ASSERT_FALSE(r.feed('\n'));
  TEST_ASSERT_TRUE(feedAll(r, "OFF\n"));
  TEST_ASSERT_EQUAL_STRING("OFF", r.line());
}

// ---- screen state ----

static void test_screen_state_initially_dark() {
  ScreenState st;
  TEST_ASSERT_FALSE(st.lit(0));
}

static void test_screen_state_timeout() {
  ScreenState st;
  st.onSample(1000);
  TEST_ASSERT_TRUE(st.lit(11000));
  TEST_ASSERT_FALSE(st.lit(11001));
}

static void test_screen_state_off_then_resume() {
  ScreenState st;
  st.onSample(0);
  st.onOff();
  TEST_ASSERT_FALSE(st.lit(1));
  st.onSample(2);
  TEST_ASSERT_TRUE(st.lit(2));
}

static void test_screen_state_stale() {
  ScreenState st;
  TEST_ASSERT_FALSE(st.onSample(0));
  TEST_ASSERT_TRUE(st.onSample(300001));
  TEST_ASSERT_FALSE(st.onSample(302001));
}

static void test_screen_state_millis_wrap() {
  ScreenState st;
  st.onSample(0xFFFFF000u);
  TEST_ASSERT_TRUE(st.lit(0x00000100u));
}

// 板子长时间收不到数据时，millis() 差值约 49.7 天后会回绕到很小的值，不能因此重新亮屏
static void test_screen_state_expiry_latched() {
  ScreenState st;
  st.onSample(0);
  st.tick(10001);
  TEST_ASSERT_FALSE(st.lit(5));
}

// 同理，熄屏超过 5 分钟后，回绕不能让下一条数据跳过清空历史
static void test_screen_state_stale_latched() {
  ScreenState st;
  st.onSample(0);
  st.tick(300001);
  TEST_ASSERT_TRUE(st.onSample(5));
  TEST_ASSERT_TRUE(st.lit(5));
}

// ---- history ----

static void test_history_rollover() {
  History h;
  for (uint32_t i = 1; i <= 151; ++i) h.push(i, 0);
  TEST_ASSERT_EQUAL(150, h.size());
  TEST_ASSERT_EQUAL_UINT32(2, h.rxAt(0));
  TEST_ASSERT_EQUAL_UINT32(151, h.rxAt(149));
}

static void test_history_peak_after_evict() {
  History h;
  h.push(1000, 0);
  for (int i = 0; i < 150; ++i) h.push(5, 7);
  TEST_ASSERT_EQUAL_UINT32(7, h.peak());
  TEST_ASSERT_EQUAL_UINT32(7, h.txAt(149));
}

static void test_history_empty_peak() {
  History h;
  TEST_ASSERT_EQUAL_UINT32(0, h.peak());
  TEST_ASSERT_EQUAL(0, h.size());
  h.push(9, 9);
  h.clear();
  TEST_ASSERT_EQUAL_UINT32(0, h.peak());
  TEST_ASSERT_EQUAL(0, h.size());
}

// ---- format ----

static void assertRate(uint32_t bps, const char* num, const char* unit) {
  char buf[16];
  const char* u = formatRate(bps, buf, sizeof(buf));
  TEST_ASSERT_EQUAL_STRING(num, buf);
  TEST_ASSERT_EQUAL_STRING(unit, u);
}

// 默认用 MB/s，约 3 位有效数字；满 1000 MB/s 改用 GB/s
static void test_format_rate() {
  assertRate(0, "0.00", "MB/s");
  assertRate(880640, "0.84", "MB/s");
  assertRate(13002342, "12.4", "MB/s");
  assertRate(157286400, "150", "MB/s");
}

// 四舍五入后跨档的值要进位，保证最多 3 位有效数字
static void test_format_rate_rounding_boundaries() {
  assertRate(10480518, "10.0", "MB/s");
  assertRate(104805172, "100", "MB/s");
}

static void test_format_rate_gigabytes() {
  assertRate(1048051712, "0.98", "GB/s");
  assertRate(1610612736, "1.50", "GB/s");
  assertRate(4294967295u, "4.00", "GB/s");
}

// ---- tones ----

static void test_tones() {
  TEST_ASSERT_EQUAL(Tone::Green, cpuTone(49));
  TEST_ASSERT_EQUAL(Tone::Yellow, cpuTone(50));
  TEST_ASSERT_EQUAL(Tone::Yellow, cpuTone(79));
  TEST_ASSERT_EQUAL(Tone::Red, cpuTone(80));
  TEST_ASSERT_EQUAL(Tone::Green, memTone(1));
  TEST_ASSERT_EQUAL(Tone::Yellow, memTone(2));
  TEST_ASSERT_EQUAL(Tone::Red, memTone(4));
  TEST_ASSERT_EQUAL(Tone::Green, memTone(3));
  TEST_ASSERT_EQUAL(Tone::Green, memTone(0));
}

// ---- usage protocol ----

static void test_parse_page() {
  PageInfo p;
  TEST_ASSERT_TRUE(parsePageLine("P cl i=2 n=3", &p));
  TEST_ASSERT_EQUAL(Page::Claude, p.page); TEST_ASSERT_EQUAL(2, p.index); TEST_ASSERT_EQUAL(3, p.count);
  TEST_ASSERT_FALSE(parsePageLine("P foo i=1 n=1", &p));
  TEST_ASSERT_FALSE(parsePageLine("P cl i=4 n=3", &p));
  TEST_ASSERT_FALSE(parsePageLine("S cpu=1", &p));
}
static void test_parse_page_rejects_and_keeps_out() {
  PageInfo p;
  p.page = Page::ChatGPT; p.index = 3; p.count = 3;
  TEST_ASSERT_FALSE(parsePageLine("P sys n=1", &p));        // 缺 i
  TEST_ASSERT_FALSE(parsePageLine("P sys i=1", &p));        // 缺 n
  TEST_ASSERT_FALSE(parsePageLine("P sys i=0 n=1", &p));
  TEST_ASSERT_FALSE(parsePageLine("P sys i=1 n=5", &p));
  TEST_ASSERT_FALSE(parsePageLine("P sys i=x n=1", &p));
  TEST_ASSERT_FALSE(parsePageLine("P sys i=1 n=1", nullptr));
  TEST_ASSERT_EQUAL(Page::ChatGPT, p.page);                  // 失败不改 out
  TEST_ASSERT_EQUAL(3, p.index);
  TEST_ASSERT_TRUE(parsePageLine("P gpt n=3 i=3 extra=9", &p));  // 字段顺序不限，未知字段忽略
  TEST_ASSERT_EQUAL(Page::ChatGPT, p.page);
  TEST_ASSERT_TRUE(parsePageLine("P sys i=1 n=1", &p));
  TEST_ASSERT_EQUAL(Page::Sys, p.page);
}
static void test_parse_usage_full() {
  Usage u;
  TEST_ASSERT_TRUE(parseUsageLine("U svc=cl st=ok age=60 plan=max h5=42 h5r=7980 wk=67 wkd=4 wkt=1400 op=12 so=28", &u));
  TEST_ASSERT_EQUAL(Service::Claude, u.svc); TEST_ASSERT_EQUAL(UsageStatus::Ok, u.st);
  TEST_ASSERT_EQUAL(60, u.age); TEST_ASSERT_EQUAL_STRING("max", u.plan);
  TEST_ASSERT_EQUAL(42, u.h5); TEST_ASSERT_EQUAL(7980, u.h5r);
  TEST_ASSERT_EQUAL(67, u.wk);
  TEST_ASSERT_EQUAL(4, u.wkd); TEST_ASSERT_EQUAL(1400, u.wkt);
  TEST_ASSERT_EQUAL(12, u.op); TEST_ASSERT_EQUAL(28, u.so);
  TEST_ASSERT_TRUE(u.received);
}
static void test_parse_usage_model_week() {
  Usage u;
  TEST_ASSERT_TRUE(parseUsageLine("U svc=cl st=ok age=0 wk=67 wkd=4 wkt=1400 md=Fable mw=4", &u));
  TEST_ASSERT_EQUAL_STRING("Fable", u.model);
  TEST_ASSERT_EQUAL(4, u.mw);
  TEST_ASSERT_TRUE(parseUsageLine("U svc=cl st=ok md=ABCDEFGHIJKLMN mw=-1", &u));
  TEST_ASSERT_EQUAL_STRING("ABCDEFGHIJK", u.model);  // 截断到缓冲区大小
  TEST_ASSERT_EQUAL(kReset, u.mw);
  TEST_ASSERT_TRUE(parseUsageLine("U svc=cl st=ok mw=150", &u));
  TEST_ASSERT_EQUAL(100, u.mw);
  TEST_ASSERT_TRUE(parseUsageLine("U svc=cl st=ok", &u));
  TEST_ASSERT_EQUAL_STRING("", u.model);
  TEST_ASSERT_EQUAL(kAbsent, u.mw);
  TEST_ASSERT_FALSE(parseUsageLine("U svc=cl st=ok mw=x", &u));
}
static void test_parse_usage_minimal_and_reset() {
  Usage u;
  TEST_ASSERT_TRUE(parseUsageLine("U svc=gpt st=exp", &u));
  TEST_ASSERT_EQUAL(Service::ChatGPT, u.svc); TEST_ASSERT_EQUAL(UsageStatus::Expired, u.st);
  TEST_ASSERT_EQUAL(kAbsent, u.h5); TEST_ASSERT_EQUAL(kAbsent, u.age);
  TEST_ASSERT_EQUAL_STRING("", u.plan);
  TEST_ASSERT_TRUE(parseUsageLine("U svc=cl st=ok age=5 h5=-1 wk=-1", &u));
  TEST_ASSERT_EQUAL(kReset, u.h5); TEST_ASSERT_EQUAL(kReset, u.wk);
}
static void test_parse_usage_rejects_and_clamps() {
  Usage u;
  TEST_ASSERT_FALSE(parseUsageLine("U st=ok", &u));
  TEST_ASSERT_FALSE(parseUsageLine("U svc=xx st=ok", &u));
  TEST_ASSERT_TRUE(parseUsageLine("U svc=cl st=ok h5=150 plan=averyveryverylongplan foo=1", &u));
  TEST_ASSERT_EQUAL(100, u.h5);
  TEST_ASSERT_EQUAL(11, (int)strlen(u.plan));   // 截断到缓冲区大小
}
static void test_parse_usage_more_rejects_and_ranges() {
  Usage u;
  u.h5 = 77;
  TEST_ASSERT_FALSE(parseUsageLine("U svc=cl", &u));                // 缺 st
  TEST_ASSERT_FALSE(parseUsageLine("U svc=cl st=bad", &u));
  TEST_ASSERT_FALSE(parseUsageLine("U svc=cl st=ok h5=abc", &u));   // 已知数字字段非数字
  TEST_ASSERT_FALSE(parseUsageLine("S svc=cl st=ok", &u));
  TEST_ASSERT_FALSE(parseUsageLine("U svc=cl st=ok", nullptr));
  TEST_ASSERT_EQUAL(77, u.h5);                                       // 失败不改 out
  // 负的 age、h5r 归零；极大值限幅到 int32
  TEST_ASSERT_TRUE(parseUsageLine("U svc=cl st=ok age=-5 h5r=-9 wk=-7 op=-3", &u));
  TEST_ASSERT_EQUAL(0, u.age); TEST_ASSERT_EQUAL(0, u.h5r);
  TEST_ASSERT_EQUAL(0, u.wk); TEST_ASSERT_EQUAL(0, u.op);            // -1 以外的负百分比限到 0
  TEST_ASSERT_TRUE(parseUsageLine("U svc=cl st=ok age=99999999999 h5r=3000000000", &u));
  TEST_ASSERT_EQUAL_INT32(INT32_MAX, u.age); TEST_ASSERT_EQUAL_INT32(INT32_MAX, u.h5r);
  // wkd 1..7、wkt 0..2359 且分钟 < 60，否则当没发
  TEST_ASSERT_TRUE(parseUsageLine("U svc=cl st=ok wkd=0 wkt=2360", &u));
  TEST_ASSERT_EQUAL(kAbsent, u.wkd); TEST_ASSERT_EQUAL(kAbsent, u.wkt);
  TEST_ASSERT_TRUE(parseUsageLine("U svc=cl st=ok wkd=8 wkt=1260", &u));
  TEST_ASSERT_EQUAL(kAbsent, u.wkd); TEST_ASSERT_EQUAL(kAbsent, u.wkt);
  TEST_ASSERT_TRUE(parseUsageLine("U svc=cl st=ok wkd=7 wkt=0 so=-1", &u));
  TEST_ASSERT_EQUAL(7, u.wkd); TEST_ASSERT_EQUAL(0, u.wkt); TEST_ASSERT_EQUAL(kReset, u.so);
  TEST_ASSERT_TRUE(parseUsageLine("U svc=cl st=ok wkt=2359 wkd=-1", &u));
  TEST_ASSERT_EQUAL(2359, u.wkt); TEST_ASSERT_EQUAL(kAbsent, u.wkd);
}
static void test_parse_usage_status_and_reset_state() {
  Usage u;
  TEST_ASSERT_TRUE(parseUsageLine("U svc=cl st=err", &u));
  TEST_ASSERT_EQUAL(UsageStatus::Error, u.st);
  TEST_ASSERT_TRUE(parseUsageLine("U svc=gpt st=none", &u));
  TEST_ASSERT_EQUAL(UsageStatus::Missing, u.st);
  // 复用同一个 out：上一次的字段不会残留
  TEST_ASSERT_TRUE(parseUsageLine("U svc=cl st=ok age=9 plan=pro h5=10", &u));
  TEST_ASSERT_TRUE(parseUsageLine("U st=ok svc=gpt", &u));           // 字段顺序不限
  TEST_ASSERT_EQUAL(Service::ChatGPT, u.svc);
  TEST_ASSERT_EQUAL(kAbsent, u.age); TEST_ASSERT_EQUAL(kAbsent, u.h5);
  TEST_ASSERT_EQUAL_STRING("", u.plan);
}

// ---- usage_format / tap ----

static void test_format_reset_in() {
  char b[48];
  formatResetIn(7980, b, sizeof b); TEST_ASSERT_EQUAL_STRING("2小时13分后重置", b);
  formatResetIn(7200, b, sizeof b); TEST_ASSERT_EQUAL_STRING("2小时0分后重置", b);
  formatResetIn(3600, b, sizeof b); TEST_ASSERT_EQUAL_STRING("1小时0分后重置", b);
  formatResetIn(3599, b, sizeof b); TEST_ASSERT_EQUAL_STRING("59分后重置", b);
  formatResetIn(780, b, sizeof b);  TEST_ASSERT_EQUAL_STRING("13分后重置", b);
  formatResetIn(60, b, sizeof b);   TEST_ASSERT_EQUAL_STRING("1分后重置", b);
  formatResetIn(59, b, sizeof b);   TEST_ASSERT_EQUAL_STRING("即将重置", b);
  formatResetIn(30, b, sizeof b);   TEST_ASSERT_EQUAL_STRING("即将重置", b);
  formatResetIn(0, b, sizeof b);    TEST_ASSERT_EQUAL_STRING("即将重置", b);
  formatResetIn(-5, b, sizeof b);   TEST_ASSERT_EQUAL_STRING("即将重置", b);
  formatResetIn(kAbsent, b, sizeof b); TEST_ASSERT_EQUAL_STRING("即将重置", b);
}
static void test_format_week_reset() {
  char b[48];
  formatWeekReset(4, 1400, b, sizeof b); TEST_ASSERT_EQUAL_STRING("本周 · 周四 14:00 重置", b);
  formatWeekReset(7, 905, b, sizeof b);  TEST_ASSERT_EQUAL_STRING("本周 · 周日 09:05 重置", b);
  formatWeekReset(1, 0, b, sizeof b);    TEST_ASSERT_EQUAL_STRING("本周 · 周一 00:00 重置", b);
  formatWeekReset(kAbsent, kAbsent, b, sizeof b); TEST_ASSERT_EQUAL_STRING("本周", b);
  formatWeekReset(4, kAbsent, b, sizeof b);       TEST_ASSERT_EQUAL_STRING("本周", b);
  formatWeekReset(kAbsent, 1400, b, sizeof b);    TEST_ASSERT_EQUAL_STRING("本周", b);
}
static void test_format_ago() {
  char b[32];
  formatAgo(30, b, sizeof b);     TEST_ASSERT_EQUAL_STRING("刚刚", b);
  formatAgo(59, b, sizeof b);     TEST_ASSERT_EQUAL_STRING("刚刚", b);
  formatAgo(60, b, sizeof b);     TEST_ASSERT_EQUAL_STRING("1 分钟前", b);
  formatAgo(179, b, sizeof b);    TEST_ASSERT_EQUAL_STRING("2 分钟前", b);
  formatAgo(180, b, sizeof b);    TEST_ASSERT_EQUAL_STRING("3 分钟前", b);
  formatAgo(3599, b, sizeof b);   TEST_ASSERT_EQUAL_STRING("59 分钟前", b);
  formatAgo(3600, b, sizeof b);   TEST_ASSERT_EQUAL_STRING("1 小时前", b);
  formatAgo(7200, b, sizeof b);   TEST_ASSERT_EQUAL_STRING("2 小时前", b);
  formatAgo(86399, b, sizeof b);  TEST_ASSERT_EQUAL_STRING("23 小时前", b);
  formatAgo(86400, b, sizeof b);  TEST_ASSERT_EQUAL_STRING("1 天前", b);
  formatAgo(432000, b, sizeof b); TEST_ASSERT_EQUAL_STRING("5 天前", b);
  formatAgo(-1, b, sizeof b);     TEST_ASSERT_EQUAL_STRING("刚刚", b);
  formatAgo(kAbsent, b, sizeof b); TEST_ASSERT_EQUAL_STRING("刚刚", b);
}
static void test_format_footer() {
  char b[64]; bool warn;
  Usage u; u.received = true; u.st = UsageStatus::Ok; u.age = 30;
  formatFooter(u, b, sizeof b, &warn); TEST_ASSERT_EQUAL_STRING("刚刚更新", b); TEST_ASSERT_FALSE(warn);
  u.age = 180;
  formatFooter(u, b, sizeof b, &warn); TEST_ASSERT_EQUAL_STRING("3 分钟前更新", b); TEST_ASSERT_FALSE(warn);
  u.age = kAbsent;
  formatFooter(u, b, sizeof b, &warn); TEST_ASSERT_EQUAL_STRING("刚刚更新", b); TEST_ASSERT_FALSE(warn);
  u.st = UsageStatus::Expired; u.svc = Service::Claude;
  formatFooter(u, b, sizeof b, &warn); TEST_ASSERT_EQUAL_STRING("已过期 · 终端运行 claude", b); TEST_ASSERT_TRUE(warn);
  u.svc = Service::ChatGPT;
  formatFooter(u, b, sizeof b, &warn); TEST_ASSERT_EQUAL_STRING("已过期 · 打开 Codex", b); TEST_ASSERT_TRUE(warn);
  u.st = UsageStatus::Error; u.age = 600;
  formatFooter(u, b, sizeof b, &warn); TEST_ASSERT_EQUAL_STRING("读取失败 · 10 分钟前的数据", b); TEST_ASSERT_TRUE(warn);
  u.age = 20;
  formatFooter(u, b, sizeof b, &warn); TEST_ASSERT_EQUAL_STRING("读取失败 · 刚刚的数据", b); TEST_ASSERT_TRUE(warn);
  u.age = kAbsent;
  formatFooter(u, b, sizeof b, &warn); TEST_ASSERT_EQUAL_STRING("读取失败", b); TEST_ASSERT_TRUE(warn);
  u.st = UsageStatus::Missing;
  formatFooter(u, b, sizeof b, &warn); TEST_ASSERT_EQUAL_STRING("", b); TEST_ASSERT_FALSE(warn);
  Usage fresh;
  warn = true;
  formatFooter(fresh, b, sizeof b, &warn); TEST_ASSERT_EQUAL_STRING("等待数据", b); TEST_ASSERT_FALSE(warn);
}
static void test_format_plan() {
  char b[12];
  formatPlan("max", b, sizeof b); TEST_ASSERT_EQUAL_STRING("Max", b);
  formatPlan("pro", b, sizeof b); TEST_ASSERT_EQUAL_STRING("Pro", b);
  formatPlan("Plus", b, sizeof b); TEST_ASSERT_EQUAL_STRING("Plus", b);
  formatPlan("20x", b, sizeof b); TEST_ASSERT_EQUAL_STRING("20x", b);   // 首字符不是字母则原样
  formatPlan("", b, sizeof b);    TEST_ASSERT_EQUAL_STRING("", b);
  formatPlan("enterprise", b, 5); TEST_ASSERT_EQUAL_STRING("Ente", b);   // 截断到缓冲区
}
static void test_window_label() {
  TEST_ASSERT_EQUAL_STRING("5 小时", windowLabel(300));
  TEST_ASSERT_EQUAL_STRING("本周", windowLabel(10080));
  TEST_ASSERT_EQUAL_STRING("", windowLabel(60));
}
static void test_format_tiny_buffer() {
  // 缓冲区装不下时必须截断且以 NUL 结尾，不越界
  char b[4];
  Usage u; u.received = true; u.st = UsageStatus::Ok; u.age = 180;
  bool warn;
  memset(b, 'x', sizeof b); formatResetIn(7980, b, 2); TEST_ASSERT_EQUAL_CHAR(0, b[1]); TEST_ASSERT_EQUAL_CHAR('x', b[2]);
  memset(b, 'x', sizeof b); formatWeekReset(4, 1400, b, 3); TEST_ASSERT_EQUAL_CHAR(0, b[2]); TEST_ASSERT_EQUAL_CHAR('x', b[3]);
  memset(b, 'x', sizeof b); formatAgo(180, b, 1); TEST_ASSERT_EQUAL_CHAR(0, b[0]); TEST_ASSERT_EQUAL_CHAR('x', b[1]);
  memset(b, 'x', sizeof b); formatFooter(u, b, 3, &warn); TEST_ASSERT_EQUAL_CHAR(0, b[2]); TEST_ASSERT_EQUAL_CHAR('x', b[3]);
  memset(b, 'x', sizeof b); formatPlan("max", b, 2); TEST_ASSERT_EQUAL_STRING("M", b); TEST_ASSERT_EQUAL_CHAR('x', b[2]);
  memset(b, 'x', sizeof b); formatPlan("max", b, 1); TEST_ASSERT_EQUAL_CHAR(0, b[0]); TEST_ASSERT_EQUAL_CHAR('x', b[1]);
}
static void test_tap_detector() {
  TapDetector t;
  TEST_ASSERT_TRUE(t.update(true, 1000));
  TEST_ASSERT_FALSE(t.update(true, 1100));   // 按住不放
  TEST_ASSERT_FALSE(t.update(false, 1150));
  TEST_ASSERT_FALSE(t.update(true, 1200));   // 距上次不到 300ms
  TEST_ASSERT_FALSE(t.update(false, 1250));
  TEST_ASSERT_TRUE(t.update(true, 1300));
}
static void test_tap_detector_millis_wrap() {
  TapDetector t;
  TEST_ASSERT_TRUE(t.update(true, 0xFFFFFF00u));
  t.update(false, 0xFFFFFF10u);
  TEST_ASSERT_FALSE(t.update(true, 0x00000010u));   // 回绕后实际只过了 0x110 ms
  t.update(false, 0x00000020u);
  TEST_ASSERT_TRUE(t.update(true, 0x00000100u));
}

// ---- 番茄 T / 横幅 B ----

static void test_parse_page_pomo() {
  PageInfo p;
  TEST_ASSERT_TRUE(parsePageLine("P pomo i=2 n=4", &p));
  TEST_ASSERT_EQUAL(Page::Pomo, p.page);
  TEST_ASSERT_EQUAL(2, p.index);
  TEST_ASSERT_EQUAL(4, p.count);
  TEST_ASSERT_FALSE(parsePageLine("P sys i=1 n=5", &p));
}
static void test_parse_timer_line() {
  Timer t;
  TEST_ASSERT_TRUE(parseTimerLine("T st=focus run=1 rem=754 tot=1500 end=1452 rd=2 rn=4 dn=5 dm=125 key=1", &t));
  TEST_ASSERT_TRUE(t.received);
  TEST_ASSERT_EQUAL(Phase::Focus, t.phase);
  TEST_ASSERT_TRUE(t.running);
  TEST_ASSERT_EQUAL_INT32(754, t.rem);
  TEST_ASSERT_EQUAL_INT32(1500, t.tot);
  TEST_ASSERT_EQUAL(1452, t.end);
  TEST_ASSERT_EQUAL(2, t.rd);
  TEST_ASSERT_EQUAL(4, t.rn);
  TEST_ASSERT_EQUAL(5, t.dn);
  TEST_ASSERT_EQUAL(125, t.dm);
  TEST_ASSERT_TRUE(t.key);
}
static void test_parse_timer_rejects_bad() {
  Timer t;
  t.rem = 42;
  TEST_ASSERT_FALSE(parseTimerLine("T st=nap rem=1 tot=1", &t));
  TEST_ASSERT_FALSE(parseTimerLine("T st=focus tot=1", &t));
  TEST_ASSERT_FALSE(parseTimerLine("T st=focus rem=x tot=1", &t));
  TEST_ASSERT_FALSE(parseTimerLine("U st=focus rem=1 tot=1", &t));
  TEST_ASSERT_FALSE(parseTimerLine("T st=focus rem=1 tot=1", nullptr));
  TEST_ASSERT_EQUAL_INT32(42, t.rem);
  TEST_ASSERT_FALSE(t.received);
}
static void test_parse_timer_missing_end_is_absent() {
  Timer t;
  TEST_ASSERT_TRUE(parseTimerLine("T st=short run=0 rem=120 tot=300 rd=-3 rn=4 dn=0 dm=0 key=0 zz=9", &t));
  TEST_ASSERT_EQUAL(Phase::Short, t.phase);
  TEST_ASSERT_FALSE(t.running);
  TEST_ASSERT_EQUAL(kAbsent, t.end);
  TEST_ASSERT_EQUAL(0, t.rd);
  TEST_ASSERT_FALSE(t.key);
}
static void test_parse_banner_lines() {
  Banner b;
  TEST_ASSERT_TRUE(parseBannerLine("B k=none", &b));
  TEST_ASSERT_EQUAL(BannerKind::None, b.kind);
  TEST_ASSERT_TRUE(parseBannerLine("B k=done xw=1 xs=1 led=1", &b));
  TEST_ASSERT_EQUAL(BannerKind::FocusDone, b.kind);
  TEST_ASSERT_TRUE(b.xw);
  TEST_ASSERT_TRUE(b.xs);
  TEST_ASSERT_TRUE(b.led);
  TEST_ASSERT_TRUE(parseBannerLine("B k=sit min=52 led=0", &b));
  TEST_ASSERT_EQUAL(BannerKind::Sit, b.kind);
  TEST_ASSERT_EQUAL(52, b.min);
  TEST_ASSERT_FALSE(b.led);
  TEST_ASSERT_FALSE(b.xw);
  TEST_ASSERT_TRUE(parseBannerLine("B k=brk led=1", &b));
  TEST_ASSERT_EQUAL(BannerKind::BreakEnded, b.kind);
  TEST_ASSERT_EQUAL(kAbsent, b.min);
  TEST_ASSERT_TRUE(parseBannerLine("B k=water min=60 led=1", &b));
  TEST_ASSERT_EQUAL(BannerKind::Water, b.kind);
  TEST_ASSERT_FALSE(parseBannerLine("B k=zzz", &b));
  TEST_ASSERT_FALSE(parseBannerLine("B led=1", &b));
  TEST_ASSERT_EQUAL(BannerKind::Water, b.kind);
}
static void test_timer_remaining_counts_down_and_clamps() {
  Timer t;
  t.running = true;
  t.rem = 3;
  TEST_ASSERT_EQUAL_INT32(3, timerRemaining(t, 1000, 1999));
  TEST_ASSERT_EQUAL_INT32(2, timerRemaining(t, 1000, 2000));
  TEST_ASSERT_EQUAL_INT32(0, timerRemaining(t, 1000, 60000));
  t.running = false;
  TEST_ASSERT_EQUAL_INT32(3, timerRemaining(t, 1000, 60000));
}
static void test_timer_remaining_millis_wrap() {
  Timer t;
  t.running = true;
  t.rem = 10;
  TEST_ASSERT_EQUAL_INT32(8, timerRemaining(t, 0xFFFFF000u, 0xFFFFF000u + 2000));
}

// ---- 番茄、横幅文案和呼吸灯 ----

static void test_format_clock() {
  char b[16];
  formatClock(754, b, sizeof b); TEST_ASSERT_EQUAL_STRING("12:34", b);
  formatClock(59, b, sizeof b); TEST_ASSERT_EQUAL_STRING("00:59", b);
  formatClock(0, b, sizeof b); TEST_ASSERT_EQUAL_STRING("00:00", b);
  formatClock(-5, b, sizeof b); TEST_ASSERT_EQUAL_STRING("00:00", b);
  formatClock(5400, b, sizeof b); TEST_ASSERT_EQUAL_STRING("90:00", b);
  formatClock(99999, b, sizeof b); TEST_ASSERT_EQUAL_STRING("99:59", b);
}
static void test_format_end_at() {
  char b[24];
  formatEndAt(1452, b, sizeof b); TEST_ASSERT_EQUAL_STRING("14:52 结束", b);
  formatEndAt(905, b, sizeof b); TEST_ASSERT_EQUAL_STRING("09:05 结束", b);
  formatEndAt(kAbsent, b, sizeof b); TEST_ASSERT_EQUAL_STRING("", b);
}
static void test_format_round_line() {
  char b[48];
  Timer t;
  t.rn = 4;
  t.phase = Phase::Focus; t.rd = 2;
  formatRoundLine(t, b, sizeof b); TEST_ASSERT_EQUAL_STRING("第 2 个 · 再 2 个后长休", b);
  t.rd = 4;
  formatRoundLine(t, b, sizeof b); TEST_ASSERT_EQUAL_STRING("第 4 个 · 这个做完长休", b);
  t.phase = Phase::Short; t.rd = 2;
  formatRoundLine(t, b, sizeof b); TEST_ASSERT_EQUAL_STRING("已完成 2/4", b);
  t.phase = Phase::Idle; t.rd = 1;
  formatRoundLine(t, b, sizeof b); TEST_ASSERT_EQUAL_STRING("第 1 个 · 再 3 个后长休", b);
}
static void test_format_today_minutes() {
  char b[24];
  formatTodayMinutes(125, b, sizeof b); TEST_ASSERT_EQUAL_STRING("2小时05分", b);
  formatTodayMinutes(45, b, sizeof b); TEST_ASSERT_EQUAL_STRING("45分", b);
  formatTodayMinutes(0, b, sizeof b); TEST_ASSERT_EQUAL_STRING("0分", b);
}
static void test_phase_label_and_hint() {
  char b[32];
  Timer t;
  t.key = true;
  TEST_ASSERT_EQUAL_STRING("准备专注", phaseLabel(t));
  formatHint(t, b, sizeof b); TEST_ASSERT_EQUAL_STRING("按快捷键开始专注", b);
  t.phase = Phase::Focus; t.running = true;
  TEST_ASSERT_EQUAL_STRING("专注", phaseLabel(t));
  formatHint(t, b, sizeof b); TEST_ASSERT_EQUAL_STRING("按快捷键暂停", b);
  t.running = false;
  TEST_ASSERT_EQUAL_STRING("已暂停", phaseLabel(t));
  formatHint(t, b, sizeof b); TEST_ASSERT_EQUAL_STRING("按快捷键继续", b);
  t.phase = Phase::Short; t.running = true;
  TEST_ASSERT_EQUAL_STRING("短休", phaseLabel(t));
  t.phase = Phase::Long;
  TEST_ASSERT_EQUAL_STRING("长休", phaseLabel(t));
  t.key = false;
  formatHint(t, b, sizeof b); TEST_ASSERT_EQUAL_STRING("在菜单栏开始", b);
}
static void test_banner_texts() {
  char b[64];
  Timer t;
  t.tot = 300;
  Banner done; done.kind = BannerKind::FocusDone;
  TEST_ASSERT_EQUAL_STRING("专注完成", bannerTitle(done.kind));
  formatBannerDetail(done, t, b, sizeof b); TEST_ASSERT_EQUAL_STRING("休息 5 分钟", b);
  formatBannerExtras(done, b, sizeof b); TEST_ASSERT_EQUAL_STRING("", b);
  done.xw = true;
  formatBannerExtras(done, b, sizeof b); TEST_ASSERT_EQUAL_STRING("顺便喝口水", b);
  done.xs = true;
  formatBannerExtras(done, b, sizeof b); TEST_ASSERT_EQUAL_STRING("顺便起来走走、喝口水", b);
  done.xw = false;
  formatBannerExtras(done, b, sizeof b); TEST_ASSERT_EQUAL_STRING("顺便起来走走", b);
  formatBannerHint(done, b, sizeof b); TEST_ASSERT_EQUAL_STRING("点一下关掉", b);

  Banner brk; brk.kind = BannerKind::BreakEnded;
  TEST_ASSERT_EQUAL_STRING("休息结束", bannerTitle(brk.kind));
  formatBannerDetail(brk, t, b, sizeof b); TEST_ASSERT_EQUAL_STRING("该开始下一个专注了", b);
  formatBannerHint(brk, b, sizeof b); TEST_ASSERT_EQUAL_STRING("按快捷键开始 · 点一下关掉", b);

  Banner sit; sit.kind = BannerKind::Sit; sit.min = 52;
  TEST_ASSERT_EQUAL_STRING("该起来走走了", bannerTitle(sit.kind));
  formatBannerDetail(sit, t, b, sizeof b); TEST_ASSERT_EQUAL_STRING("已连续用电脑 52 分钟", b);
  formatBannerHint(sit, b, sizeof b); TEST_ASSERT_EQUAL_STRING("点一下关掉 · 离开 5 分钟会自己消失", b);

  Banner water; water.kind = BannerKind::Water; water.min = 60;
  TEST_ASSERT_EQUAL_STRING("该喝水了", bannerTitle(water.kind));
  formatBannerDetail(water, t, b, sizeof b); TEST_ASSERT_EQUAL_STRING("上次提醒是 60 分钟前", b);

  TEST_ASSERT_EQUAL_STRING("", bannerTitle(BannerKind::None));
}
static void test_breathe_level() {
  TEST_ASSERT_EQUAL_UINT8(0, breatheLevel(0));
  TEST_ASSERT_EQUAL_UINT8(255, breatheLevel(1500));
  TEST_ASSERT_EQUAL_UINT8(0, breatheLevel(3000));
  TEST_ASSERT_EQUAL_UINT8(breatheLevel(700), breatheLevel(2300));
  TEST_ASSERT_TRUE(breatheLevel(700) > 0 && breatheLevel(700) < 255);
}
static void test_scale_rgb_and_colors() {
  Rgb c = scaleRgb(Rgb{255, 100, 0}, 128);
  TEST_ASSERT_EQUAL_UINT8(128, c.r);
  TEST_ASSERT_EQUAL_UINT8(50, c.g);
  TEST_ASSERT_EQUAL_UINT8(0, c.b);
  Rgb off = bannerLedColor(BannerKind::None);
  TEST_ASSERT_EQUAL_UINT8(0, off.r + off.g + off.b);
  Rgb water = bannerLedColor(BannerKind::Water);
  TEST_ASSERT_TRUE(water.b > water.r);
  Rgb done = bannerLedColor(BannerKind::FocusDone);
  TEST_ASSERT_TRUE(done.g > done.r && done.g > done.b);
}

// 横幅标题的每个字都要在小字库里，否则板子上会画成空白
static void test_banner_titles_covered_by_font() {
  const BannerKind kinds[] = {BannerKind::FocusDone, BannerKind::BreakEnded, BannerKind::Sit, BannerKind::Water};
  for (BannerKind k : kinds) {
    const char* p = bannerTitle(k);
    TEST_ASSERT_TRUE(*p != '\0');
    while (*p) {
      // 按 UTF-8 首字节算出这个字占几个字节
      size_t n = ((unsigned char)*p < 0x80) ? 1 : ((unsigned char)*p < 0xE0) ? 2 : ((unsigned char)*p < 0xF0) ? 3 : 4;
      char one[5] = {};
      memcpy(one, p, n);
      TEST_ASSERT_NOT_NULL_MESSAGE(strstr(kBannerGlyphs, one), one);
      p += n;
    }
  }
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_parse_full_line);
  RUN_TEST(test_parse_off);
  RUN_TEST(test_parse_unknown_field_and_default_level);
  RUN_TEST(test_parse_clamps);
  RUN_TEST(test_parse_rx_saturates);
  RUN_TEST(test_parse_rejects);
  RUN_TEST(test_line_reader_basic);
  RUN_TEST(test_line_reader_overlong_dropped);
  RUN_TEST(test_screen_state_initially_dark);
  RUN_TEST(test_screen_state_timeout);
  RUN_TEST(test_screen_state_off_then_resume);
  RUN_TEST(test_screen_state_stale);
  RUN_TEST(test_screen_state_millis_wrap);
  RUN_TEST(test_screen_state_expiry_latched);
  RUN_TEST(test_screen_state_stale_latched);
  RUN_TEST(test_history_rollover);
  RUN_TEST(test_history_peak_after_evict);
  RUN_TEST(test_history_empty_peak);
  RUN_TEST(test_format_rate);
  RUN_TEST(test_format_rate_rounding_boundaries);
  RUN_TEST(test_format_rate_gigabytes);
  RUN_TEST(test_tones);
  RUN_TEST(test_parse_page);
  RUN_TEST(test_parse_page_rejects_and_keeps_out);
  RUN_TEST(test_parse_usage_full);
  RUN_TEST(test_parse_usage_model_week);
  RUN_TEST(test_parse_usage_minimal_and_reset);
  RUN_TEST(test_parse_usage_rejects_and_clamps);
  RUN_TEST(test_parse_usage_more_rejects_and_ranges);
  RUN_TEST(test_parse_usage_status_and_reset_state);
  RUN_TEST(test_format_reset_in);
  RUN_TEST(test_format_week_reset);
  RUN_TEST(test_format_ago);
  RUN_TEST(test_format_footer);
  RUN_TEST(test_format_plan);
  RUN_TEST(test_window_label);
  RUN_TEST(test_format_tiny_buffer);
  RUN_TEST(test_tap_detector);
  RUN_TEST(test_tap_detector_millis_wrap);
  RUN_TEST(test_parse_page_pomo);
  RUN_TEST(test_parse_timer_line);
  RUN_TEST(test_parse_timer_rejects_bad);
  RUN_TEST(test_parse_timer_missing_end_is_absent);
  RUN_TEST(test_parse_banner_lines);
  RUN_TEST(test_timer_remaining_counts_down_and_clamps);
  RUN_TEST(test_timer_remaining_millis_wrap);
  RUN_TEST(test_format_clock);
  RUN_TEST(test_format_end_at);
  RUN_TEST(test_format_round_line);
  RUN_TEST(test_format_today_minutes);
  RUN_TEST(test_phase_label_and_hint);
  RUN_TEST(test_banner_texts);
  RUN_TEST(test_breathe_level);
  RUN_TEST(test_scale_rgb_and_colors);
  RUN_TEST(test_banner_titles_covered_by_font);
  return UNITY_END();
}
