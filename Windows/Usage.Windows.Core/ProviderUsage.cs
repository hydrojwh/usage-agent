using System;
using System.Globalization;

namespace Whyun.Usage.Core
{
    public enum ProviderKind
    {
        Claude,
        Codex,
        Grok,
    }

    public sealed class ProviderUsage
    {
        public ProviderUsage(ProviderKind provider, double usedPercent, string metricLabel, DateTimeOffset? resetsAt)
        {
            Provider = provider;
            UsedPercent = UsageMath.ClampPercent(usedPercent);
            MetricLabel = metricLabel ?? string.Empty;
            ResetsAt = resetsAt;
        }

        public ProviderKind Provider { get; private set; }
        public double UsedPercent { get; private set; }
        public double RemainingPercent { get { return 100.0 - UsedPercent; } }
        public string MetricLabel { get; private set; }
        public DateTimeOffset? ResetsAt { get; private set; }
    }

    public static class UsageMath
    {
        public static double ClampPercent(double value)
        {
            if (double.IsNaN(value) || double.IsInfinity(value))
            {
                return 0;
            }

            return Math.Max(0, Math.Min(100, value));
        }
    }

    public static class SummaryFormatter
    {
        public static string Value(double? remainingPercent)
        {
            if (!remainingPercent.HasValue)
            {
                return "—";
            }

            double value = UsageMath.ClampPercent(remainingPercent.Value);
            return Math.Round(value, MidpointRounding.AwayFromZero).ToString("0", CultureInfo.InvariantCulture);
        }

        public static string ProviderName(ProviderKind provider)
        {
            switch (provider)
            {
                case ProviderKind.Claude:
                    return "Claude";
                case ProviderKind.Codex:
                    return "Codex";
                case ProviderKind.Grok:
                    return "Grok";
                default:
                    return provider.ToString();
            }
        }
    }

    public sealed class UsageParseException : Exception
    {
        public UsageParseException(string message) : base(message)
        {
        }
    }
}
