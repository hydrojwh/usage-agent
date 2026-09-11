using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;
using Whyun.Usage.Core;

namespace Whyun.Usage.Windows
{
    internal sealed class UsageStripForm : Form
    {
        private readonly Dictionary<ProviderKind, Image> _logos;
        private readonly ToolTip _toolTip;
        private ProviderViewState[] _states;

        public UsageStripForm()
        {
            AutoScaleMode = AutoScaleMode.None;
            DoubleBuffered = true;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            ClientSize = new Size(162, 30);
            MaximizeBox = false;
            MinimizeBox = false;
            Text = "Usage";
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);

            _states = new[]
            {
                new ProviderViewState(ProviderKind.Claude),
                new ProviderViewState(ProviderKind.Codex),
                new ProviderViewState(ProviderKind.Grok),
            };
            _logos = new Dictionary<ProviderKind, Image>
            {
                { ProviderKind.Claude, LoadImage("claude.png") },
                { ProviderKind.Codex, LoadImage("openai.png") },
                { ProviderKind.Grok, LoadImage("x.png") },
            };
            _toolTip = new ToolTip
            {
                InitialDelay = 350,
                ReshowDelay = 100,
                AutoPopDelay = 10000,
                ShowAlways = true,
            };
            UpdateAccessibilityAndTooltip();
        }

        public event EventHandler RefreshRequested;

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                const int wsExToolWindow = 0x00000080;
                const int wsExNoActivate = 0x08000000;
                CreateParams parameters = base.CreateParams;
                parameters.ExStyle |= wsExToolWindow | wsExNoActivate;
                return parameters;
            }
        }

        public void SetStates(IEnumerable<ProviderViewState> states)
        {
            _states = states.Select(state => state.Copy()).ToArray();
            UpdateAccessibilityAndTooltip();
            Invalidate();
        }

        protected override void OnMouseUp(MouseEventArgs eventArgs)
        {
            base.OnMouseUp(eventArgs);
            if (eventArgs.Button == MouseButtons.Left)
            {
                EventHandler handler = RefreshRequested;
                if (handler != null)
                {
                    handler(this, EventArgs.Empty);
                }
            }
        }

        protected override void OnPaintBackground(PaintEventArgs eventArgs)
        {
            // The complete opaque strip is painted in OnPaint to avoid flicker inside Explorer.
        }

        protected override void OnPaint(PaintEventArgs eventArgs)
        {
            base.OnPaint(eventArgs);
            ThemePalette palette = ThemePalette.Current();
            eventArgs.Graphics.Clear(palette.Background);
            eventArgs.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            eventArgs.Graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            eventArgs.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;

            int tileWidth = Math.Max(1, ClientSize.Width / 3);
            float scale = ClientSize.Height / 30.0f;
            int iconSize = Math.Max(10, (int)Math.Round(14 * scale));
            int iconLeft = Math.Max(4, (int)Math.Round(6 * scale));
            int gap = Math.Max(3, (int)Math.Round(5 * scale));

            using (var valueFont = new Font("Segoe UI Semibold", 9.0f, FontStyle.Regular, GraphicsUnit.Point))
            using (var separatorPen = new Pen(palette.Separator))
            {
                for (int index = 0; index < _states.Length; index++)
                {
                    ProviderViewState state = _states[index];
                    int tileX = index * tileWidth;
                    int iconY = Math.Max(0, (ClientSize.Height - iconSize) / 2);
                    DrawTintedImage(eventArgs.Graphics, _logos[state.Provider],
                        new Rectangle(tileX + iconLeft, iconY, iconSize, iconSize),
                        palette.ProviderColor(state.Provider));

                    string value = SummaryFormatter.Value(state.RemainingPercent);
                    Color textColor = state.RemainingPercent.HasValue ? palette.Foreground : palette.Muted;
                    int textX = tileX + iconLeft + iconSize + gap;
                    var textBounds = new Rectangle(textX, 0,
                        Math.Max(1, tileWidth - (textX - tileX) - 3), ClientSize.Height);
                    TextRenderer.DrawText(eventArgs.Graphics, value, valueFont, textBounds, textColor,
                        TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix |
                        TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter | TextFormatFlags.Left);

                    if (index < _states.Length - 1)
                    {
                        int separatorX = tileX + tileWidth;
                        eventArgs.Graphics.DrawLine(separatorPen, separatorX, ClientSize.Height / 4,
                            separatorX, ClientSize.Height * 3 / 4);
                    }
                }
            }
        }

        private void UpdateAccessibilityAndTooltip()
        {
            string[] lines = _states.Select(state =>
            {
                string name = SummaryFormatter.ProviderName(state.Provider);
                if (state.RemainingPercent.HasValue)
                {
                    return name + " " + SummaryFormatter.Value(state.RemainingPercent) + "% remaining";
                }

                return name + " unavailable" +
                    (string.IsNullOrWhiteSpace(state.ErrorMessage) ? string.Empty : ": " + state.ErrorMessage);
            }).ToArray();

            AccessibleName = "Usage";
            AccessibleDescription = string.Join(", ", lines);
            _toolTip.SetToolTip(this, string.Join(Environment.NewLine, lines));
        }

        private static Image LoadImage(string fileName)
        {
            string name = "Whyun.Usage.Windows.Assets." + fileName;
            using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
            {
                if (stream == null)
                {
                    throw new InvalidOperationException("Embedded provider logo missing: " + fileName);
                }

                using (Image image = Image.FromStream(stream))
                {
                    return new Bitmap(image);
                }
            }
        }

        private static void DrawTintedImage(Graphics graphics, Image image, Rectangle destination, Color color)
        {
            float red = color.R / 255.0f;
            float green = color.G / 255.0f;
            float blue = color.B / 255.0f;
            var matrix = new ColorMatrix(new[]
            {
                new[] { 0f, 0f, 0f, 0f, 0f },
                new[] { 0f, 0f, 0f, 0f, 0f },
                new[] { 0f, 0f, 0f, 0f, 0f },
                new[] { 0f, 0f, 0f, 1f, 0f },
                new[] { red, green, blue, 0f, 1f },
            });
            using (var attributes = new ImageAttributes())
            {
                attributes.SetColorMatrix(matrix);
                graphics.DrawImage(image, destination, 0, 0, image.Width, image.Height,
                    GraphicsUnit.Pixel, attributes);
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                foreach (Image image in _logos.Values)
                {
                    image.Dispose();
                }
                _toolTip.Dispose();
            }

            base.Dispose(disposing);
        }
    }
}
