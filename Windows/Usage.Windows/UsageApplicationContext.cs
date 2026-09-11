using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Whyun.Usage.Core;

namespace Whyun.Usage.Windows
{
    internal sealed class UsageApplicationContext : ApplicationContext
    {
        private readonly UsageStripForm _form;
        private readonly TaskbarHost _host;
        private readonly NotifyIcon _notifyIcon;
        private readonly Icon _trayIcon;
        private readonly ContextMenuStrip _menu;
        private readonly ToolStripMenuItem _refreshMenuItem;
        private readonly System.Windows.Forms.Timer _refreshTimer;
        private readonly System.Windows.Forms.Timer _hostTimer;
        private readonly IProviderClient[] _clients;
        private ProviderViewState[] _states;
        private CancellationTokenSource _refreshCancellation;
        private bool _refreshing;

        public UsageApplicationContext()
        {
            _clients = new IProviderClient[]
            {
                new ClaudeUsageClient(),
                new CodexUsageClient(),
                new GrokUsageClient(),
            };
            _states = new[]
            {
                new ProviderViewState(ProviderKind.Claude),
                new ProviderViewState(ProviderKind.Codex),
                new ProviderViewState(ProviderKind.Grok),
            };

            _form = new UsageStripForm();
            _form.RefreshRequested += async delegate { await RefreshAsync(); };

            _refreshMenuItem = new ToolStripMenuItem("Refresh now");
            _refreshMenuItem.Click += async delegate { await RefreshAsync(); };
            var quitMenuItem = new ToolStripMenuItem("Quit Usage");
            quitMenuItem.Click += delegate { ExitThread(); };
            _menu = new ContextMenuStrip();
            _menu.Items.Add(_refreshMenuItem);
            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(quitMenuItem);
            _form.ContextMenuStrip = _menu;

            _trayIcon = TrayIconFactory.Create();
            _notifyIcon = new NotifyIcon
            {
                Icon = _trayIcon,
                Text = "Usage · checking providers",
                ContextMenuStrip = _menu,
                Visible = true,
            };
            _notifyIcon.MouseClick += async delegate(object sender, MouseEventArgs eventArgs)
            {
                if (eventArgs.Button == MouseButtons.Left)
                {
                    await RefreshAsync();
                }
            };

            _host = new TaskbarHost(_form);
            _form.Shown += async delegate { await RefreshAsync(); };
            _form.Show();
            _host.EnsureHosted();

            _refreshTimer = new System.Windows.Forms.Timer { Interval = 5 * 60 * 1000 };
            _refreshTimer.Tick += async delegate { await RefreshAsync(); };
            _refreshTimer.Start();

            _hostTimer = new System.Windows.Forms.Timer { Interval = 10 * 1000 };
            _hostTimer.Tick += delegate
            {
                _host.EnsureHosted();
                _form.Invalidate();
            };
            _hostTimer.Start();
        }

        private async Task RefreshAsync()
        {
            if (_refreshing)
            {
                return;
            }

            _refreshing = true;
            _refreshMenuItem.Enabled = false;
            _refreshCancellation = new CancellationTokenSource(TimeSpan.FromSeconds(35));
            try
            {
                Task<ProviderPollResult>[] tasks = _clients
                    .Select(client => ProviderPoller.FetchSafelyAsync(client, _refreshCancellation.Token))
                    .ToArray();
                ProviderPollResult[] results = await Task.WhenAll(tasks);

                var byProvider = _states.ToDictionary(state => state.Provider);
                foreach (ProviderPollResult result in results)
                {
                    ProviderViewState state = byProvider[result.Provider];
                    if (result.Usage != null)
                    {
                        state.RemainingPercent = result.Usage.RemainingPercent;
                        state.ErrorMessage = null;
                    }
                    else
                    {
                        // Keep the previous value when one provider temporarily fails.
                        state.ErrorMessage = result.ErrorMessage;
                    }
                }

                _states = new[]
                {
                    byProvider[ProviderKind.Claude],
                    byProvider[ProviderKind.Codex],
                    byProvider[ProviderKind.Grok],
                };
                _form.SetStates(_states);
                UpdateTrayText();
            }
            finally
            {
                _refreshCancellation.Dispose();
                _refreshCancellation = null;
                _refreshMenuItem.Enabled = true;
                _refreshing = false;
            }
        }

        private void UpdateTrayText()
        {
            string text = "Usage · C " + SummaryFormatter.Value(_states[0].RemainingPercent) +
                " · O " + SummaryFormatter.Value(_states[1].RemainingPercent) +
                " · X " + SummaryFormatter.Value(_states[2].RemainingPercent);
            _notifyIcon.Text = text.Length <= 63 ? text : text.Substring(0, 63);
        }

        protected override void ExitThreadCore()
        {
            if (_refreshCancellation != null)
            {
                _refreshCancellation.Cancel();
            }
            _refreshTimer.Stop();
            _hostTimer.Stop();
            _notifyIcon.Visible = false;
            _notifyIcon.Dispose();
            _trayIcon.Dispose();
            _menu.Dispose();
            _refreshTimer.Dispose();
            _hostTimer.Dispose();
            _form.Dispose();
            base.ExitThreadCore();
        }
    }
}
