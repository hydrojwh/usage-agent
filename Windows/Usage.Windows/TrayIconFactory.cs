using System;
using System.Drawing;
using System.Drawing.Drawing2D;

namespace Whyun.Usage.Windows
{
    internal static class TrayIconFactory
    {
        public static Icon Create()
        {
            using (var bitmap = new Bitmap(32, 32))
            using (Graphics graphics = Graphics.FromImage(bitmap))
            {
                graphics.SmoothingMode = SmoothingMode.AntiAlias;
                graphics.Clear(Color.Transparent);
                using (var background = new SolidBrush(Color.FromArgb(38, 38, 38)))
                {
                    graphics.FillEllipse(background, 1, 1, 30, 30);
                }

                DrawBar(graphics, 7, 16, 4, 9, ThemePalette.Claude);
                DrawBar(graphics, 14, 11, 4, 14, ThemePalette.OpenAI);
                DrawBar(graphics, 21, 7, 4, 18, Color.White);

                IntPtr handle = bitmap.GetHicon();
                try
                {
                    using (Icon temporary = Icon.FromHandle(handle))
                    {
                        return (Icon)temporary.Clone();
                    }
                }
                finally
                {
                    NativeMethods.DestroyIcon(handle);
                }
            }
        }

        private static void DrawBar(Graphics graphics, int x, int y, int width, int height, Color color)
        {
            using (var brush = new SolidBrush(color))
            {
                graphics.FillRectangle(brush, x, y, width, height);
            }
        }
    }
}
