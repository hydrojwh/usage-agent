using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace Whyun.Usage.Windows
{
    internal sealed class JsonRpcProcess : IDisposable
    {
        private readonly Process _process;
        private readonly JavaScriptSerializer _serializer;
        private readonly bool _includeJsonRpcVersion;
        private int _nextId = 1;
        private bool _disposed;

        public JsonRpcProcess(string executable, string arguments, bool includeJsonRpcVersion)
        {
            _includeJsonRpcVersion = includeJsonRpcVersion;
            _serializer = new JavaScriptSerializer { MaxJsonLength = 1024 * 1024 };
            _process = new Process { StartInfo = CliCommand.Create(executable, arguments), EnableRaisingEvents = true };
            _process.ErrorDataReceived += delegate { };
            if (!_process.Start())
            {
                throw new InvalidOperationException("Could not start " + executable + ".");
            }

            _process.BeginErrorReadLine();
            _process.StandardInput.NewLine = "\n";
            _process.StandardInput.AutoFlush = true;
        }

        public async Task<string> RequestAsync(string method, IDictionary<string, object> parameters,
            TimeSpan timeout, CancellationToken cancellationToken)
        {
            int id = _nextId++;
            var payload = NewPayload(method, parameters);
            payload["id"] = id;
            await WriteAsync(payload).ConfigureAwait(false);

            while (true)
            {
                string line = await ReadLineAsync(timeout, cancellationToken).ConfigureAwait(false);
                object parsed;
                try
                {
                    parsed = _serializer.DeserializeObject(line);
                }
                catch
                {
                    continue;
                }

                var message = parsed as IDictionary<string, object>;
                object responseId;
                if (message == null || !message.TryGetValue("id", out responseId) || Convert.ToInt32(responseId) != id)
                {
                    continue;
                }

                object error;
                if (message.TryGetValue("error", out error) && error != null)
                {
                    var errorObject = error as IDictionary<string, object>;
                    object errorText;
                    string messageText = errorObject != null && errorObject.TryGetValue("message", out errorText)
                        ? Convert.ToString(errorText)
                        : "Unknown JSON-RPC error";
                    throw new InvalidOperationException(messageText);
                }

                return line;
            }
        }

        public Task NotifyAsync(string method, IDictionary<string, object> parameters)
        {
            return WriteAsync(NewPayload(method, parameters));
        }

        private Dictionary<string, object> NewPayload(string method, IDictionary<string, object> parameters)
        {
            var payload = new Dictionary<string, object>
            {
                { "method", method },
                { "params", parameters ?? new Dictionary<string, object>() },
            };
            if (_includeJsonRpcVersion)
            {
                payload["jsonrpc"] = "2.0";
            }

            return payload;
        }

        private Task WriteAsync(IDictionary<string, object> payload)
        {
            if (_disposed)
            {
                throw new ObjectDisposedException("JsonRpcProcess");
            }

            return _process.StandardInput.WriteLineAsync(_serializer.Serialize(payload));
        }

        private async Task<string> ReadLineAsync(TimeSpan timeout, CancellationToken cancellationToken)
        {
            Task<string> read = _process.StandardOutput.ReadLineAsync();
            Task delay = Task.Delay(timeout, cancellationToken);
            Task completed = await Task.WhenAny(read, delay).ConfigureAwait(false);
            if (completed != read)
            {
                cancellationToken.ThrowIfCancellationRequested();
                throw new TimeoutException("The CLI usage request timed out.");
            }

            string line = await read.ConfigureAwait(false);
            if (line == null)
            {
                throw new EndOfStreamException("The CLI closed its usage channel.");
            }
            if (line.Length > 1024 * 1024)
            {
                throw new InvalidDataException("The CLI returned an oversized response.");
            }

            return line;
        }

        public void Dispose()
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            try { _process.StandardInput.Close(); } catch { }
            try
            {
                if (!_process.HasExited && !_process.WaitForExit(750))
                {
                    _process.Kill();
                }
            }
            catch { }
            _process.Dispose();
        }
    }
}
