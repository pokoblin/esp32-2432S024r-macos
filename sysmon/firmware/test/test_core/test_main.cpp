#include <unity.h>
#include <string.h>

#include "format.h"
#include "history.h"
#include "line_reader.h"
#include "protocol.h"
#include "screen_state.h"
#include "tones.h"
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
  TEST_ASSERT_FALSE(parsePageLine("P sys i=1 n=4", &p));
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
  RUN_TEST(test_parse_usage_minimal_and_reset);
  RUN_TEST(test_parse_usage_rejects_and_clamps);
  RUN_TEST(test_parse_usage_more_rejects_and_ranges);
  RUN_TEST(test_parse_usage_status_and_reset_state);
  return UNITY_END();
}
