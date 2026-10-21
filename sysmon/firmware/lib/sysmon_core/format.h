#pragma once
#include <stddef.h>
#include <stdint.h>

namespace sysmon {

// 把网速写成约 3 位有效数字的文字（"12.4"、"860"），返回单位 "B/s" / "KB/s" / "MB/s"。
const char* formatRate(uint32_t bytesPerSec, char* num, size_t numLen);

}  // namespace sysmon
