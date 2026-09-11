using Whyun.Usage.Core;

namespace Whyun.Usage.Windows
{
    internal sealed class ProviderViewState
    {
        public ProviderViewState(ProviderKind provider)
        {
            Provider = provider;
        }

        public ProviderKind Provider { get; private set; }
        public double? RemainingPercent { get; set; }
        public string ErrorMessage { get; set; }

        public ProviderViewState Copy()
        {
            return new ProviderViewState(Provider)
            {
                RemainingPercent = RemainingPercent,
                ErrorMessage = ErrorMessage,
            };
        }
    }

    internal sealed class ProviderPollResult
    {
        private ProviderPollResult(ProviderKind provider, ProviderUsage usage, string errorMessage)
        {
            Provider = provider;
            Usage = usage;
            ErrorMessage = errorMessage;
        }

        public ProviderKind Provider { get; private set; }
        public ProviderUsage Usage { get; private set; }
        public string ErrorMessage { get; private set; }

        public static ProviderPollResult Success(ProviderUsage usage)
        {
            return new ProviderPollResult(usage.Provider, usage, null);
        }

        public static ProviderPollResult Failure(ProviderKind provider, string message)
        {
            return new ProviderPollResult(provider, null, message);
        }
    }
}
