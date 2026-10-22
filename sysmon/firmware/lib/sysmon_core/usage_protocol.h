// Mac 端发来的页面和用量行。
//   页面：P <sys|pomo|cl|gpt> i=<n> n=<n>
//   用量：U svc=<cl|gpt> st=<ok|exp|err|none> [age=<秒>] [plan=<名>] [h5=<0-100|-1>] [h5r=<秒>]
//         [wk=<0-100|-1>] [wkd=<1-7>] [wkt=<HHMM>] [md=<模型名>] [mw=<0-100|-1>]
//         [op=<0-100|-1>] [so=<0-100|-1>]
// 字段顺序不限，不认识的字段忽略。
#pragma once
#include <stdint.h>

namespace sysmon {

enum class Page { Sys, Pomo, Claude, ChatGPT };

struct PageInfo {
  Page page = Page::Sys;
  int index = 1;  // 当前页在轮换里的序号，从 1 开始
  int count = 1;  // 轮换里一共几页
};

enum class Service { Claude, ChatGPT };
enum class UsageStatus { Ok, Expired, Error, Missing };

constexpr int kAbsent = -2;  // 字段没发
constexpr int kReset = -1;   // 窗口已重置

struct Usage {
  Service svc = Service::Claude;
  UsageStatus st = UsageStatus::Missing;
  bool received = false;  // 是否收到过这个服务的 U 行
  int32_t age = kAbsent;  // 数据多久以前取的，秒
  char plan[12] = "";
  int h5 = kAbsent;
  int32_t h5r = kAbsent;  // 5 小时窗口还剩多少秒重置
  int wk = kAbsent;
  int wkd = kAbsent;  // 周窗口重置的星期，1..7
  int wkt = kAbsent;  // 周窗口重置的时刻，HHMM
  char model[12] = "";  // 按模型单独计算的每周额度对应的模型名，例如 "Fable"
  int mw = kAbsent;     // 这个模型的每周额度
  int op = kAbsent;
  int so = kAbsent;
};

// 页名不认识，或 i、n 缺失、不满足 1 <= i <= n <= 4 时返回 false；失败时 *out 不变。
bool parsePageLine(const char* line, PageInfo* out);

// 缺 svc 或 st、值不认识、已知数字字段不是数字时返回 false；失败时 *out 不变。
// 成功时 *out 整个重写（不沿用旧字段），received 置 true。
bool parseUsageLine(const char* line, Usage* out);

}  // namespace sysmon
