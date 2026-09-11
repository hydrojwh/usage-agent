using System;
using System.Drawing;
using System.Windows.Forms;

namespace Whyun.Usage.Windows
{
    internal sealed class TaskbarHost
    {
        private const int LogicalWidth = 162;
        private const int LogicalHeight = 30;
        private readonly UsageStripForm _form;
        private IntPtr _taskbar;

        public TaskbarHost(UsageStripForm form)
        {
            _form = form;
        }

        public void EnsureHosted()
        {
            IntPtr taskbar = NativeMethods.FindWindow("Shell_TrayWnd", null);
            if (taskbar == IntPtr.Zero || !NativeMethods.IsWindow(taskbar) || !TryAttach(taskbar))
            {
                ShowFloating();
            }
        }

        private bool TryAttach(IntPtr taskbar)
        {
            NativeMethods.Rect taskbarRect;
            if (!NativeMethods.GetWindowRect(taskbar, out taskbarRect) || taskbarRect.Width <= taskbarRect.Height)
            {
                return false;
            }

            IntPtr tray = NativeMethods.FindWindowEx(taskbar, IntPtr.Zero, "TrayNotifyWnd", null);
            NativeMethods.Rect trayRect;
            if (tray == IntPtr.Zero || !NativeMethods.GetWindowRect(tray, out trayRect))
            {
                return false;
            }

            int dpi = NativeMethods.DpiForWindow(taskbar);
            int width = Scale(LogicalWidth, dpi);
            int height = Math.Min(Scale(LogicalHeight, dpi), Math.Max(18, taskbarRect.Height - Scale(4, dpi)));
            int x = trayRect.Left - taskbarRect.Left - width - Scale(4, dpi);
            int y = Math.Max(0, (taskbarRect.Height - height) / 2);
            if (x < 0 || x + width > taskbarRect.Width)
            {
                return false;
            }

            IntPtr handle = _form.Handle;
            if (_taskbar != taskbar || NativeMethods.GetParent(handle) != taskbar)
            {
                NativeMethods.SetParent(handle, taskbar);
                if (NativeMethods.GetParent(handle) != taskbar)
                {
                    return false;
                }

                int style = NativeMethods.GetWindowLong(handle, NativeMethods.GwlStyle);
                style = (style | NativeMethods.WsChild) & ~NativeMethods.WsPopup;
                NativeMethods.SetWindowLong(handle, NativeMethods.GwlStyle, style);
                _taskbar = taskbar;
            }

            _form.TopMost = false;
            return NativeMethods.SetWindowPos(handle, IntPtr.Zero, x, y, width, height,
                NativeMethods.SwpNoActivate | NativeMethods.SwpShowWindow | NativeMethods.SwpFrameChanged);
        }

        private void ShowFloating()
        {
            IntPtr handle = _form.Handle;
            if (NativeMethods.GetParent(handle) != IntPtr.Zero)
            {
                NativeMethods.SetParent(handle, IntPtr.Zero);
            }

            int style = NativeMethods.GetWindowLong(handle, NativeMethods.GwlStyle);
            style = (style | NativeMethods.WsPopup) & ~NativeMethods.WsChild;
            NativeMethods.SetWindowLong(handle, NativeMethods.GwlStyle, style);
            _taskbar = IntPtr.Zero;

            Screen screen = Screen.PrimaryScreen;
            Rectangle working = screen == null ? SystemInformation.WorkingArea : screen.WorkingArea;
            int dpi = NativeMethods.DpiForWindow(handle);
            int width = Scale(LogicalWidth, dpi);
            int height = Scale(LogicalHeight, dpi);
            int margin = Scale(8, dpi);
            int x = working.Right - width - margin;
            int y = working.Bottom - height - margin;

            _form.TopMost = true;
            NativeMethods.SetWindowPos(handle, NativeMethods.HwndTopmost, x, y, width, height,
                NativeMethods.SwpNoActivate | NativeMethods.SwpShowWindow | NativeMethods.SwpFrameChanged);
        }

        private static int Scale(int value, int dpi)
        {
            return Math.Max(1, (int)Math.Round(value * dpi / 96.0));
        }
    }
}
