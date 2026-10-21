// Mac 端发来的一行文本协议。
//   数据行：S cpu=<0-100> mem=<0-100> lvl=<1|2|4> rx=<B/s> tx=<B/s>
//   熄屏：  OFF
// 不认识的行返回 Unknown，不认识的字段忽略，方便以后加指标。
#pragma once
#include <stdint.h>

namespace sysmon {

struct Sample {
  int cpu;
  int mem;
  int level;  // 内存压力等级：1 正常，2 警告，4 严重
  uint32_t rx;
  uint32_t tx;
};

enum class LineKind { Sample, Off, Unknown };

// cpu、mem、rx、tx 必须都有；lvl 缺省为 1。
LineKind parseLine(const char* line, Sample* out);

}  // namespace sysmon
