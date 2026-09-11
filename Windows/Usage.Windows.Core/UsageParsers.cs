using System;

namespace Whyun.Usage.Core
{
    public static class UsageParsers
    {
        public static ProviderUsage ParseClaude(string json)
        {
            object root = JsonNavigator.Deserialize(json);
            object window = JsonNavigator.GetEither(root,
                new[] { "five_hour" },
                new[] { "fiveHour" },
                new[] { "seven_day" },
                new[] { "sevenDay" });

            double? used = JsonNavigator.Number(JsonNavigator.GetEither(window,
                new[] { "utilization" },
                new[] { "used_percent" },
                new[] { "usedPercent" }));
            if (!used.HasValue)
            {
                throw new UsageParseException("Claude returned no subscription usage window.");
            }

            DateTimeOffset? reset = JsonNavigator.Iso8601(JsonNavigator.GetEither(window,
                new[] { "resets_at" },
                new[] { "resetsAt" }));
            return new ProviderUsage(ProviderKind.Claude, used.Value, "5-hour", reset);
        }

        public static ProviderUsage ParseCodexRpc(string json)
        {
            object root = JsonNavigator.Deserialize(json);
            object limits = JsonNavigator.GetEither(root,
                new[] { "result", "rateLimits" },
                new[] { "result", "rate_limits" },
                new[] { "rateLimits" },
                new[] { "rate_limits" },
                new[] { "rate_limit" });
            object window = JsonNavigator.GetEither(limits,
                new[] { "primary" },
                new[] { "primaryWindow" },
                new[] { "primary_window" },
                new[] { "secondary" },
                new[] { "secondaryWindow" },
                new[] { "secondary_window" });

            double? used = JsonNavigator.Number(JsonNavigator.GetEither(window,
                new[] { "usedPercent" },
                new[] { "used_percent" }));
            if (!used.HasValue)
            {
                throw new UsageParseException("Codex returned no rate-limit window.");
            }

            DateTimeOffset? reset = JsonNavigator.UnixSeconds(JsonNavigator.GetEither(window,
                new[] { "resetsAt" },
                new[] { "resetAt" },
                new[] { "reset_at" }));
            return new ProviderUsage(ProviderKind.Codex, used.Value, "5-hour", reset);
        }

        public static ProviderUsage ParseGrokRpc(string json)
        {
            object root = JsonNavigator.Deserialize(json);
            object result = JsonNavigator.Get(root, "result") ?? root;
            double? limit = JsonNavigator.Number(JsonNavigator.GetEither(result,
                new[] { "monthlyLimit", "val" },
                new[] { "monthly_limit", "val" }));
            double? used = JsonNavigator.Number(JsonNavigator.GetEither(result,
                new[] { "usage", "totalUsed", "val" },
                new[] { "usage", "total_used", "val" },
                new[] { "usage", "includedUsed", "val" },
                new[] { "usage", "included_used", "val" }));

            if (!limit.HasValue || limit.Value <= 0 || !used.HasValue)
            {
                throw new UsageParseException("Grok returned no monthly billing window.");
            }

            object cycle = JsonNavigator.GetEither(result,
                new[] { "billingCycle" },
                new[] { "billing_cycle" });
            DateTimeOffset? reset = JsonNavigator.Iso8601(JsonNavigator.GetEither(cycle,
                new[] { "billingPeriodEnd" },
                new[] { "billing_period_end" }));
            return new ProviderUsage(ProviderKind.Grok, used.Value / limit.Value * 100.0, "Monthly", reset);
        }
    }
}
