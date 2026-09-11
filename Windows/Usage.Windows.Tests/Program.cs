using System;
using Whyun.Usage.Core;

namespace Whyun.Usage.Windows.Tests
{
    internal static class Program
    {
        private static int _passed;

        private static int Main()
        {
            try
            {
                ClaudeUsesFiveHourWindow();
                CodexParsesCamelCaseRpc();
                CodexParsesSnakeCaseFallback();
                GrokParsesMonthlyBilling();
                PercentagesClampAtBothEnds();
                SummaryRoundsAndUsesUnavailableMark();
                MissingWindowsFailClearly();
                Console.WriteLine("Usage.Windows.Core tests passed (" + _passed + "/7).");
                return 0;
            }
            catch (Exception exception)
            {
                Console.Error.WriteLine(exception.Message);
                return 1;
            }
        }

        private static void ClaudeUsesFiveHourWindow()
        {
            ProviderUsage usage = UsageParsers.ParseClaude(
                "{\"five_hour\":{\"utilization\":18,\"resets_at\":\"2026-08-15T12:00:00Z\"}," +
                "\"seven_day\":{\"utilization\":40}}");
            Equal(ProviderKind.Claude, usage.Provider, "Claude provider");
            Near(82, usage.RemainingPercent, "Claude remaining");
            Equal("5-hour", usage.MetricLabel, "Claude label");
            Pass();
        }

        private static void CodexParsesCamelCaseRpc()
        {
            ProviderUsage usage = UsageParsers.ParseCodexRpc(
                "{\"id\":2,\"result\":{\"rateLimits\":{\"primary\":{" +
                "\"usedPercent\":37,\"resetsAt\":1786795200}}}}");
            Near(63, usage.RemainingPercent, "Codex remaining");
            Pass();
        }

        private static void CodexParsesSnakeCaseFallback()
        {
            ProviderUsage usage = UsageParsers.ParseCodexRpc(
                "{\"rate_limit\":{\"primary_window\":{\"used_percent\":4.5,\"reset_at\":1786795200}}}");
            Near(95.5, usage.RemainingPercent, "Codex snake case remaining");
            Pass();
        }

        private static void GrokParsesMonthlyBilling()
        {
            ProviderUsage usage = UsageParsers.ParseGrokRpc(
                "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{" +
                "\"monthlyLimit\":{\"val\":10000},\"usage\":{\"totalUsed\":{\"val\":900}}," +
                "\"billingCycle\":{\"billingPeriodEnd\":\"2026-09-01T00:00:00Z\"}}}");
            Near(91, usage.RemainingPercent, "Grok remaining");
            Pass();
        }

        private static void PercentagesClampAtBothEnds()
        {
            Near(100, new ProviderUsage(ProviderKind.Claude, -4, "", null).RemainingPercent,
                "negative used clamp");
            Near(0, new ProviderUsage(ProviderKind.Claude, 140, "", null).RemainingPercent,
                "over-100 used clamp");
            Pass();
        }

        private static void SummaryRoundsAndUsesUnavailableMark()
        {
            Equal("83", SummaryFormatter.Value(82.5), "summary rounding");
            Equal("—", SummaryFormatter.Value(null), "summary unavailable");
            Pass();
        }

        private static void MissingWindowsFailClearly()
        {
            bool threw = false;
            try
            {
                UsageParsers.ParseClaude("{}");
            }
            catch (UsageParseException)
            {
                threw = true;
            }

            Equal(true, threw, "missing Claude window");
            Pass();
        }

        private static void Near(double expected, double actual, string label)
        {
            if (Math.Abs(expected - actual) > 0.001)
            {
                throw new InvalidOperationException(label + ": expected " + expected + ", got " + actual);
            }
        }

        private static void Equal(object expected, object actual, string label)
        {
            if (!object.Equals(expected, actual))
            {
                throw new InvalidOperationException(label + ": expected " + expected + ", got " + actual);
            }
        }

        private static void Pass()
        {
            _passed++;
        }
    }
}
