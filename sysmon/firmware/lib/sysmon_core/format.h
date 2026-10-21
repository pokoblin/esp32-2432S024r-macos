#pragma once
#include <stddef.h>
#include <stdint.h>

namespace sysmon {

// 把网速写成约 3 位有效数字的文字（"0.84"、"12.4"），返回单位 "MB/s"，满 1000 MB/s 时为 "GB/s"。
const char* formatRate(uint32_t bytesPerSec, char* num, size_t numLen);

}  // namespace sysmon
