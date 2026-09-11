using System;
using System.Net;
using System.Threading;
using System.Windows.Forms;

namespace Whyun.Usage.Windows
{
    internal static class Program
    {
        private static Mutex _singleInstance;

        [STAThread]
        private static void Main()
        {
            bool created;
            _singleInstance = new Mutex(true, @"Local\Whyun.Usage.Windows", out created);
            if (!created)
            {
                return;
            }

            NativeMethods.TryEnablePerMonitorDpi();
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new UsageApplicationContext());

            _singleInstance.ReleaseMutex();
            _singleInstance.Dispose();
        }
    }
}
