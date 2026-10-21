#include <unity.h>
#include <string.h>

#include "line_reader.h"
#include "protocol.h"
#include "screen_state.h"

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
  return UNITY_END();
}
