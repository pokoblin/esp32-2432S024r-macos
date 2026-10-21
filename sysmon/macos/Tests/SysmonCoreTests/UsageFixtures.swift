// 用量接口的测试夹具。
// - claude：2026-10-21 对 api.anthropic.com/api/oauth/usage 的真实响应，原样保留
//   （响应里没有账号标识，无需脱敏）。该账号的 seven_day_opus / seven_day_sonnet 都是 null。
// - claudeNulls：在 claude 的基础上手工改的：seven_day_opus 为 null，
//   seven_day_sonnet 有 utilization 但 resets_at 为 null，用来覆盖解析器对这两种空值的处理。
// - codex：2026-10-21 对 chatgpt.com/backend-api/wham/usage 的真实响应，
//   邮箱、user_id、account_id 已替换成占位符，其余结构和数值保持原样。
// - claudeKeychain / codexAuth：凭据文件的结构，里面全是假值，不含任何真实令牌。

enum UsageFixtures {
    /// GET api.anthropic.com/api/oauth/usage（真实响应）
    static let claude = #"""
{
  "five_hour": {
    "utilization": 8.0,
    "resets_at": "2026-10-21T09:09:59.555360+00:00",
    "limit_dollars": null,
    "used_dollars": null,
    "remaining_dollars": null,
    "locked_reason": null
  },
  "seven_day": {
    "utilization": 23.0,
    "resets_at": "2026-10-24T11:59:59.555385+00:00",
    "limit_dollars": null,
    "used_dollars": null,
    "remaining_dollars": null,
    "locked_reason": null
  },
  "seven_day_oauth_apps": null,
  "seven_day_opus": null,
  "seven_day_sonnet": null,
  "seven_day_cowork": null,
  "seven_day_omelette": null,
  "tangelo": null,
  "iguana_necktie": null,
  "omelette_promotional": null,
  "nimbus_quill": null,
  "cinder_cove": null,
  "copper_kite": null,
  "brass_thimble": null,
  "harbor_lantern": null,
  "wattle_ember": null,
  "amber_ladder": null,
  "granite_teacup": null,
  "amber_cistern": null,
  "juniper_tide": null,
  "cedar_ember": null,
  "starry_waterfall": null,
  "amber_gauge": null,
  "extra_usage": {
    "is_enabled": false,
    "monthly_limit": null,
    "used_credits": null,
    "utilization": null,
    "currency": null,
    "decimal_places": null,
    "disabled_reason": null,
    "user_disabled": false,
    "spend_limit_reached": false,
    "credits_ever_enabled": false,
    "daily": null,
    "weekly": null
  },
  "limits": [
    {
      "kind": "session",
      "group": "session",
      "percent": 8,
      "severity": "normal",
      "resets_at": "2026-10-21T09:09:59.555360+00:00",
      "scope": null,
      "is_active": false
    },
    {
      "kind": "weekly_all",
      "group": "weekly",
      "percent": 23,
      "severity": "normal",
      "resets_at": "2026-10-24T11:59:59.555385+00:00",
      "scope": null,
      "is_active": true
    },
    {
      "kind": "weekly_scoped",
      "group": "weekly",
      "percent": 0,
      "severity": "normal",
      "resets_at": "2026-10-24T12:00:00+00:00",
      "scope": {
        "model": {
          "id": null,
          "display_name": "Fable"
        },
        "surface": null
      },
      "is_active": false
    }
  ],
  "spend": {
    "used": {
      "amount_minor": 0,
      "currency": "USD",
      "exponent": 2
    },
    "limit": null,
    "percent": 0,
    "severity": "normal",
    "enabled": false,
    "disabled_reason": null,
    "cap": null,
    "balance": null,
    "auto_reload": null,
    "disclaimer": "Usage credits cover you when you hit your plan limits. [Learn more](https://support.claude.com/articles/12429409)",
    "can_purchase_credits": false,
    "can_toggle": false
  },
  "member_dashboard_available": false,
  "seven_day_breakdown": {
    "as_of": "2026-10-21T07:19:05.592063+00:00",
    "window_started_at": "2026-10-17T11:59:59.555385+00:00",
    "rows": [
      {
        "key": "claude_code",
        "display_name": "Claude Code",
        "percent": 100
      },
      {
        "key": "chat",
        "display_name": "Chats",
        "percent": 0
      },
      {
        "key": "cowork",
        "display_name": "Cowork",
        "percent": 0
      },
      {
        "key": "other",
        "display_name": "Other",
        "percent": 0
      }
    ]
  },
  "weekly_scoped_shares": [
    {
      "limit_index": 2,
      "used_percent_of_weekly": 0,
      "allowance_percent_of_weekly": 50
    }
  ]
}
"""#

    /// 在 claude 的基础上：seven_day_opus 为 null，seven_day_sonnet.resets_at 为 null
    static let claudeNulls = #"""
{
  "five_hour": {
    "utilization": 8.0,
    "resets_at": "2026-10-21T09:09:59.555360+00:00",
    "limit_dollars": null,
    "used_dollars": null,
    "remaining_dollars": null,
    "locked_reason": null
  },
  "seven_day": {
    "utilization": 23.0,
    "resets_at": "2026-10-24T11:59:59.555385+00:00",
    "limit_dollars": null,
    "used_dollars": null,
    "remaining_dollars": null,
    "locked_reason": null
  },
  "seven_day_oauth_apps": null,
  "seven_day_opus": null,
  "seven_day_sonnet": {
    "utilization": 23.0,
    "resets_at": null
  },
  "seven_day_cowork": null,
  "seven_day_omelette": null,
  "tangelo": null,
  "iguana_necktie": null,
  "omelette_promotional": null,
  "nimbus_quill": null,
  "cinder_cove": null,
  "copper_kite": null,
  "brass_thimble": null,
  "harbor_lantern": null,
  "wattle_ember": null,
  "amber_ladder": null,
  "granite_teacup": null,
  "amber_cistern": null,
  "juniper_tide": null,
  "cedar_ember": null,
  "starry_waterfall": null,
  "amber_gauge": null,
  "extra_usage": {
    "is_enabled": false,
    "monthly_limit": null,
    "used_credits": null,
    "utilization": null,
    "currency": null,
    "decimal_places": null,
    "disabled_reason": null,
    "user_disabled": false,
    "spend_limit_reached": false,
    "credits_ever_enabled": false,
    "daily": null,
    "weekly": null
  },
  "limits": [
    {
      "kind": "session",
      "group": "session",
      "percent": 8,
      "severity": "normal",
      "resets_at": "2026-10-21T09:09:59.555360+00:00",
      "scope": null,
      "is_active": false
    },
    {
      "kind": "weekly_all",
      "group": "weekly",
      "percent": 23,
      "severity": "normal",
      "resets_at": "2026-10-24T11:59:59.555385+00:00",
      "scope": null,
      "is_active": true
    },
    {
      "kind": "weekly_scoped",
      "group": "weekly",
      "percent": 0,
      "severity": "normal",
      "resets_at": "2026-10-24T12:00:00+00:00",
      "scope": {
        "model": {
          "id": null,
          "display_name": "Fable"
        },
        "surface": null
      },
      "is_active": false
    }
  ],
  "spend": {
    "used": {
      "amount_minor": 0,
      "currency": "USD",
      "exponent": 2
    },
    "limit": null,
    "percent": 0,
    "severity": "normal",
    "enabled": false,
    "disabled_reason": null,
    "cap": null,
    "balance": null,
    "auto_reload": null,
    "disclaimer": "Usage credits cover you when you hit your plan limits. [Learn more](https://support.claude.com/articles/12429409)",
    "can_purchase_credits": false,
    "can_toggle": false
  },
  "member_dashboard_available": false,
  "seven_day_breakdown": {
    "as_of": "2026-10-21T07:19:05.592063+00:00",
    "window_started_at": "2026-10-17T11:59:59.555385+00:00",
    "rows": [
      {
        "key": "claude_code",
        "display_name": "Claude Code",
        "percent": 100
      },
      {
        "key": "chat",
        "display_name": "Chats",
        "percent": 0
      },
      {
        "key": "cowork",
        "display_name": "Cowork",
        "percent": 0
      },
      {
        "key": "other",
        "display_name": "Other",
        "percent": 0
      }
    ]
  },
  "weekly_scoped_shares": [
    {
      "limit_index": 2,
      "used_percent_of_weekly": 0,
      "allowance_percent_of_weekly": 50
    }
  ]
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
