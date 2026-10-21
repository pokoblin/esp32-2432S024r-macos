#include <unity.h>
#include <string.h>

#include "format.h"
#include "history.h"
#include "line_reader.h"
#include "protocol.h"
#include "screen_state.h"
#include "tones.h"

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

static void test_format_rate() {
  assertRate(0, "0", "B/s");
  assertRate(999, "999", "B/s");
  assertRate(1000, "0.98", "KB/s");
  assertRate(880640, "860", "KB/s");
  assertRate(13002342, "12.4", "MB/s");
  assertRate(157286400, "150", "MB/s");
}

// 四舍五入后跨档的值要进位，保证最多 3 位有效数字
static void test_format_rate_rounding_boundaries() {
  assertRate(10239, "10.0", "KB/s");
  assertRate(102350, "100", "KB/s");
  assertRate(1023500, "0.98", "MB/s");
}

// 万兆网会超过 1000 MB/s，换成 GB/s 保持 3 位
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
  return UNITY_END();
}
