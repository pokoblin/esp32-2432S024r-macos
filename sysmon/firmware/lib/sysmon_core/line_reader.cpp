#include "line_reader.h"

namespace sysmon {

bool LineReader::feed(char c) {
  if (c == '\n') {
    bool ok = !overflow_;
    buf_[len_] = '\0';
    len_ = 0;
    overflow_ = false;
    return ok;
  }
  if (c == '\r') return false;
  if (overflow_) return false;
  if (len_ >= kMax) {
    overflow_ = true;
    len_ = 0;
    return false;
  }
  buf_[len_++] = c;
  return false;
}

}  // namespace sysmon
