using System.Drawing;
using Microsoft.Win32;

namespace Whyun.Usage.Windows
{
    internal sealed class ThemePalette
    {
        private ThemePalette(bool dark)
        {
            IsDark = dark;
            Background = dark ? Color.FromArgb(32, 32, 32) : Color.FromArgb(243, 243, 243);
            Foreground = dark ? Color.FromArgb(245, 245, 245) : Color.FromArgb(31, 31, 31);
            Muted = dark ? Color.FromArgb(150, 150, 150) : Color.FromArgb(104, 104, 104);
            Separator = dark ? Color.FromArgb(58, 58, 58) : Color.FromArgb(218, 218, 218);
        }

        public bool IsDark { get; private set; }
        public Color Background { get; private set; }
        public Color Foreground { get; private set; }
        public Color Muted { get; private set; }
        public Color Separator { get; private set; }

        public static readonly Color Claude = Color.FromArgb(217, 119, 87);
        public static readonly Color OpenAI = Color.FromArgb(25, 195, 125);

        public Color ProviderColor(Whyun.Usage.Core.ProviderKind provider)
        {
            switch (provider)
            {
                case Whyun.Usage.Core.ProviderKind.Claude:
                    return Claude;
                case Whyun.Usage.Core.ProviderKind.Codex:
                    return OpenAI;
                case Whyun.Usage.Core.ProviderKind.Grok:
                    return IsDark ? Color.White : Color.Black;
                default:
                    return Foreground;
            }
        }

        public static ThemePalette Current()
        {
            bool dark = false;
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
                {
                    object value = key == null ? null : key.GetValue("SystemUsesLightTheme");
                    dark = value != null && System.Convert.ToInt32(value) == 0;
                }
            }
            catch
            {
                dark = false;
            }

            return new ThemePalette(dark);
        }
    }
}
