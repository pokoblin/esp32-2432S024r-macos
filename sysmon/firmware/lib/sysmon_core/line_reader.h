// 把串口逐字节拼成行。超过 kMax 的行（例如开机日志、半截数据）整行丢弃。
#pragma once
#include <stddef.h>

namespace sysmon {

class LineReader {
 public:
  static constexpr size_t kMax = 128;

  // 收到 '\n' 且这一行没超长时返回 true，之后 line() 是去掉 "\r\n" 的内容。
  bool feed(char c);
  const char* line() const { return buf_; }

 private:
  char buf_[kMax + 1] = {};
  size_t len_ = 0;
  bool overflow_ = false;
};

}  // namespace sysmon
