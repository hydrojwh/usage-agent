using System;
using System.Runtime.InteropServices;

namespace Whyun.Usage.Windows
{
    internal static class NativeMethods
    {
        internal const int GwlStyle = -16;
        internal const int WsChild = 0x40000000;
        internal const int WsPopup = unchecked((int)0x80000000);
        internal const uint SwpNoActivate = 0x0010;
        internal const uint SwpShowWindow = 0x0040;
        internal const uint SwpFrameChanged = 0x0020;
        internal static readonly IntPtr HwndTopmost = new IntPtr(-1);
        internal static readonly IntPtr HwndNotTopmost = new IntPtr(-2);

        [StructLayout(LayoutKind.Sequential)]
        internal struct Rect
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;

            public int Width { get { return Right - Left; } }
            public int Height { get { return Bottom - Top; } }
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        internal static extern IntPtr FindWindow(string className, string windowName);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        internal static extern IntPtr FindWindowEx(IntPtr parent, IntPtr childAfter, string className, string windowName);

        [DllImport("user32.dll", SetLastError = true)]
        internal static extern IntPtr SetParent(IntPtr child, IntPtr newParent);

        [DllImport("user32.dll")]
        internal static extern IntPtr GetParent(IntPtr window);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsWindow(IntPtr window);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetWindowRect(IntPtr window, out Rect rect);

        [DllImport("user32.dll", SetLastError = true)]
        internal static extern int GetWindowLong(IntPtr window, int index);

        [DllImport("user32.dll", SetLastError = true)]
        internal static extern int SetWindowLong(IntPtr window, int index, int value);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y,
            int width, int height, uint flags);

        [DllImport("user32.dll")]
        private static extern uint GetDpiForWindow(IntPtr window);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetProcessDpiAwarenessContext(IntPtr value);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool DestroyIcon(IntPtr icon);

        internal static int DpiForWindow(IntPtr window)
        {
            try
            {
                uint dpi = GetDpiForWindow(window);
                return dpi == 0 ? 96 : (int)dpi;
            }
            catch (EntryPointNotFoundException)
            {
                return 96;
            }
        }

        internal static void TryEnablePerMonitorDpi()
        {
            try
            {
                SetProcessDpiAwarenessContext(new IntPtr(-4));
            }
            catch (EntryPointNotFoundException)
            {
            }
        }
    }
}
