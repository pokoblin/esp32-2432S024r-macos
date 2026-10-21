// TODO 用真实响应核对：claude / claudeNulls 目前是按设计文档预计的格式手写的，
// 因为抓取时钥匙串里的 Claude 凭据已过期，拿不到真实响应。Task 11 里补做核对。
//
// 用量接口的测试夹具。
// - codex：2026-10-21 对 chatgpt.com/backend-api/wham/usage 的真实响应，
//   邮箱、user_id、account_id 已替换成占位符，其余结构和数值保持原样。
// - claude / claudeNulls：见上面的 TODO，手写的预计格式（utilization 为 0–100 的浮点数，
//   resets_at 为 ISO8601 字符串）。claudeNulls 里 seven_day_opus 为 null，
//   seven_day_sonnet.resets_at 为 null。
// - claudeKeychain / codexAuth：凭据文件的结构，里面全是假值，不含任何真实令牌。

enum UsageFixtures {
    /// GET api.anthropic.com/api/oauth/usage
    static let claude = #"""
{
  "five_hour": {
    "utilization": 37.0,
    "resets_at": "2026-10-21T14:00:00.123456+00:00"
  },
  "seven_day": {
    "utilization": 12.0,
    "resets_at": "2026-10-23T06:00:00.123456+00:00"
  },
  "seven_day_oauth_apps": null,
  "seven_day_opus": {
    "utilization": 5.0,
    "resets_at": "2026-10-23T06:00:00.123456+00:00"
  },
  "seven_day_sonnet": {
    "utilization": 8.0,
    "resets_at": "2026-10-23T06:00:00.123456+00:00"
  },
  "extra_usage": {
    "is_enabled": false,
    "monthly_limit": null,
    "used_credits": null,
    "utilization": null
  }
}
"""#

    /// 在 claude 的基础上：seven_day_opus 为 null，seven_day_sonnet.resets_at 为 null
    static let claudeNulls = #"""
{
  "five_hour": {
    "utilization": 37.0,
    "resets_at": "2026-10-21T14:00:00.123456+00:00"
  },
  "seven_day": {
    "utilization": 12.0,
    "resets_at": "2026-10-23T06:00:00.123456+00:00"
  },
  "seven_day_oauth_apps": null,
  "seven_day_opus": null,
  "seven_day_sonnet": {
    "utilization": 8.0,
    "resets_at": null
  },
  "extra_usage": {
    "is_enabled": false,
    "monthly_limit": null,
    "used_credits": null,
    "utilization": null
  }
}
"""#

    /// GET chatgpt.com/backend-api/wham/usage（真实响应，已脱敏）
    static let codex = #"""
{
  "user_id": "user-REDACTED",
  "account_id": "00000000-0000-0000-0000-000000000000",
  "email": "redacted@example.com",
  "plan_type": "plus",
  "rate_limit": {
    "allowed": true,
    "limit_reached": false,
    "primary_window": {
      "used_percent": 0,
      "limit_window_seconds": 18000,
      "reset_after_seconds": 18000,
      "reset_at": 1792581976
    },
    "secondary_window": {
      "used_percent": 1,
      "limit_window_seconds": 604800,
      "reset_after_seconds": 526953,
      "reset_at": 1793090928
    }
  },
  "code_review_rate_limit": null,
  "additional_rate_limits": null,
  "model_usage": {
    "gpt-6-astra": {
      "available": true,
      "available_at": null,
      "credits_would_enable": false
    }
  },
  "credits": {
    "has_credits": false,
    "unlimited": false,
    "overage_limit_reached": false,
    "balance": "0",
    "approx_local_messages": [
      0,
      0
    ],
    "approx_cloud_messages": [
      0,
      0
    ]
  },
  "spend_control": {
    "reached": false,
    "individual_limit": null
  },
  "rate_limit_reached_type": null,
  "promo": null,
  "rate_limit_reset_credits": {
    "available_count": 3,
    "applicable_available_count": 0
  }
}
"""#

    /// 钥匙串 Claude Code-credentials 的内容（假值）
    static let claudeKeychain = #"""
{
  "claudeAiOauth": {
    "accessToken": "sk-ant-oat01-FAKE-ACCESS-TOKEN",
    "refreshToken": "sk-ant-ort01-FAKE-REFRESH-TOKEN",
    "expiresAt": 1800000000000,
    "refreshTokenExpiresAt": 1800000000000,
    "scopes": [
      "user:file_upload",
      "user:inference",
      "user:mcp_servers",
      "user:plugins",
      "user:profile",
      "user:sessions:claude_code"
    ],
    "subscriptionType": "max",
    "rateLimitTier": "default_claude_max_20x"
  }
}
"""#

    /// ~/.codex/auth.json 的内容（假值；access_token 的 payload 为 {"exp": 1800000000}）
    static let codexAuth = #"""
{
  "auth_mode": "chatgpt",
  "OPENAI_API_KEY": null,
  "tokens": {
    "id_token": "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJleHAiOjE4MDAwMDAwMDAsImVtYWlsIjoicmVkYWN0ZWRAZXhhbXBsZS5jb20ifQ.fake-signature",
    "access_token": "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJleHAiOjE4MDAwMDAwMDB9.fake-signature",
    "refresh_token": "fake-refresh-token",
    "account_id": "00000000-0000-0000-0000-000000000000"
  },
  "last_refresh": "2026-10-21T00:00:00.000000Z"
}
"""#
}
