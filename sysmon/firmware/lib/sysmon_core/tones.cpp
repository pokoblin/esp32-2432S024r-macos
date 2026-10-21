#include "tones.h"

namespace sysmon {

Tone cpuTone(int percent) {
  if (percent >= 80) return Tone::Red;
  if (percent >= 50) return Tone::Yellow;
  return Tone::Green;
}

Tone memTone(int level) {
  if (level == 4) return Tone::Red;
  if (level == 2) return Tone::Yellow;
  return Tone::Green;
}

}  // namespace sysmon
