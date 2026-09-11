using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading;
using System.Threading.Tasks;
using Whyun.Usage.Core;

namespace Whyun.Usage.Windows
{
    internal interface IProviderClient
    {
        ProviderKind Provider { get; }
        Task<ProviderUsage> FetchAsync(CancellationToken cancellationToken);
    }

    internal static class ProviderPoller
    {
        public static async Task<ProviderPollResult> FetchSafelyAsync(
            IProviderClient client, CancellationToken cancellationToken)
        {
            try
            {
                ProviderUsage usage = await client.FetchAsync(cancellationToken).ConfigureAwait(false);
                return ProviderPollResult.Success(usage);
            }
            catch (OperationCanceledException)
            {
                return ProviderPollResult.Failure(client.Provider, "Usage request timed out.");
            }
            catch (Exception exception)
            {
                return ProviderPollResult.Failure(client.Provider, UserFacingError(client.Provider, exception));
            }
        }

        private static string UserFacingError(ProviderKind provider, Exception exception)
        {
            string action;
            switch (provider)
            {
                case ProviderKind.Claude:
                    action = "Run Claude and sign in.";
                    break;
                case ProviderKind.Codex:
                    action = "Run codex and sign in with ChatGPT.";
                    break;
                case ProviderKind.Grok:
                    action = "Run grok login.";
                    break;
                default:
                    action = "Sign in with the provider CLI.";
                    break;
            }

            string detail = exception.Message == null ? string.Empty : exception.Message.Trim();
            return string.IsNullOrEmpty(detail) ? action : detail + " " + action;
        }
    }

    internal sealed class ClaudeUsageClient : IProviderClient
    {
        private const string UsageUrl = "https://api.anthropic.com/api/oauth/usage";
        private static readonly HttpClient Http = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };

        public ProviderKind Provider { get { return ProviderKind.Claude; } }

        public async Task<ProviderUsage> FetchAsync(CancellationToken cancellationToken)
        {
            string token = ReadCliAccessToken();
            using (var request = new HttpRequestMessage(HttpMethod.Get, UsageUrl))
            {
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                request.Headers.Accept.ParseAdd("application/json");
                request.Headers.TryAddWithoutValidation("anthropic-beta", "oauth-2025-04-20");

                using (HttpResponseMessage response = await Http.SendAsync(request, cancellationToken).ConfigureAwait(false))
                {
                    if (response.StatusCode == HttpStatusCode.Unauthorized || response.StatusCode == HttpStatusCode.Forbidden)
                    {
                        throw new InvalidOperationException("Claude CLI authentication expired.");
                    }
                    if ((int)response.StatusCode == 429)
                    {
                        throw new InvalidOperationException("Claude usage is temporarily rate limited.");
                    }
                    if (!response.IsSuccessStatusCode)
                    {
                        throw new InvalidOperationException("Claude usage returned HTTP " + (int)response.StatusCode + ".");
                    }

                    string json = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    return UsageParsers.ParseClaude(json);
                }
            }
        }

        private static string ReadCliAccessToken()
        {
            string configDirectory = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR");
            if (string.IsNullOrWhiteSpace(configDirectory))
            {
                configDirectory = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude");
            }

            string path = Path.Combine(configDirectory, ".credentials.json");
            if (!File.Exists(path))
            {
                throw new FileNotFoundException("Claude CLI credentials were not found.");
            }

            // The token remains owned by Claude CLI: read in memory for this request only,
            // never log it, copy it, or write the credentials file.
            object root = JsonNavigator.Deserialize(File.ReadAllText(path));
            object oauth = JsonNavigator.Get(root, "claudeAiOauth") ?? root;
            string token = JsonNavigator.Text(JsonNavigator.Get(oauth, "accessToken"));
            if (string.IsNullOrWhiteSpace(token))
            {
                throw new InvalidOperationException("Claude CLI has no OAuth access token.");
            }

            return token;
        }
    }

    internal sealed class CodexUsageClient : IProviderClient
    {
        public ProviderKind Provider { get { return ProviderKind.Codex; } }

        public async Task<ProviderUsage> FetchAsync(CancellationToken cancellationToken)
        {
            using (var rpc = new JsonRpcProcess(
                "codex", "-s read-only -a untrusted app-server", includeJsonRpcVersion: false))
            {
                var clientInfo = new Dictionary<string, object>
                {
                    { "name", "Usage" },
                    { "version", "0.1.0" },
                };
                await rpc.RequestAsync("initialize",
                    new Dictionary<string, object> { { "clientInfo", clientInfo } },
                    TimeSpan.FromSeconds(8), cancellationToken).ConfigureAwait(false);
                await rpc.NotifyAsync("initialized", new Dictionary<string, object>()).ConfigureAwait(false);
                string response = await rpc.RequestAsync("account/rateLimits/read",
                    new Dictionary<string, object>(), TimeSpan.FromSeconds(5), cancellationToken).ConfigureAwait(false);
                return UsageParsers.ParseCodexRpc(response);
            }
        }
    }

    internal sealed class GrokUsageClient : IProviderClient
    {
        public ProviderKind Provider { get { return ProviderKind.Grok; } }

        public async Task<ProviderUsage> FetchAsync(CancellationToken cancellationToken)
        {
            using (var rpc = new JsonRpcProcess("grok", "agent stdio", includeJsonRpcVersion: true))
            {
                var fileSystem = new Dictionary<string, object>
                {
                    { "readTextFile", false },
                    { "writeTextFile", false },
                };
                var capabilities = new Dictionary<string, object>
                {
                    { "fs", fileSystem },
                    { "terminal", false },
                };
                var initialize = new Dictionary<string, object>
                {
                    { "protocolVersion", "1" },
                    { "clientCapabilities", capabilities },
                };

                await rpc.RequestAsync("initialize", initialize,
                    TimeSpan.FromSeconds(6), cancellationToken).ConfigureAwait(false);
                string response = await rpc.RequestAsync("x.ai/billing",
                    new Dictionary<string, object>(), TimeSpan.FromSeconds(5), cancellationToken).ConfigureAwait(false);
                return UsageParsers.ParseGrokRpc(response);
            }
        }
    }
}
