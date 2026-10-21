// 圆环配色分档。CPU 按百分比；内存按系统压力等级，和活动监视器一致。
#pragma once

namespace sysmon {

enum class Tone { Green, Yellow, Red };

Tone cpuTone(int percent);  // <50 绿，50–79 黄，>=80 红
Tone memTone(int level);    // 1 绿，2 黄，4 红，其他按绿

}  // namespace sysmon
