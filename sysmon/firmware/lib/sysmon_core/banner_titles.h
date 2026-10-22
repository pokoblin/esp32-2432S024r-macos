// 横幅大标题。这几个字用自制的小字库画（src/banner_font.h），
// 改了标题要重跑 sysmon/tools/make_banner_font.swift，它从这个文件里所有 "..." 抽字。
#pragma once

namespace sysmon {

constexpr const char* kTitleFocusDone = "专注完成";
constexpr const char* kTitleBreakEnded = "休息结束";
constexpr const char* kTitleSit = "该起来走走了";
constexpr const char* kTitleWater = "该喝水了";

}  // namespace sysmon
