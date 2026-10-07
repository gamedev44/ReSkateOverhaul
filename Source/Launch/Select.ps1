#Requires -Version 5.1
param(
    [string]$Drive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing, System.Windows.Forms @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class UiBackdrop {
  public static Bitmap Make(string path, int width, int height) {
    byte[] bytes = System.IO.File.ReadAllBytes(path);
    Bitmap raw;
    using (var ms = new System.IO.MemoryStream(bytes))
    using (var img = Image.FromStream(ms)) {
      raw = Cover(img, Math.Max(1, width / 2), Math.Max(1, height / 2));
    }
    BoxBlur(raw, 8);
    BoxBlur(raw, 4);
    var full = new Bitmap(width, height, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(full)) {
      g.InterpolationMode = InterpolationMode.HighQualityBicubic;
      g.DrawImage(raw, 0, 0, width, height);
      using (var veil = new SolidBrush(Color.FromArgb(72, 0, 0, 0)))
        g.FillRectangle(veil, 0, 0, width, height);
    }
    raw.Dispose();
    return full;
  }
  static Bitmap Cover(Image src, int width, int height) {
    float scale = Math.Max(width / (float)src.Width, height / (float)src.Height);
    int dw = Math.Max(1, (int)(src.Width * scale));
    int dh = Math.Max(1, (int)(src.Height * scale));
    var bmp = new Bitmap(width, height, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(bmp)) {
      g.InterpolationMode = InterpolationMode.HighQualityBicubic;
      g.Clear(Color.Black);
      g.DrawImage(src, (width - dw) / 2, (height - dh) / 2, dw, dh);
    }
    return bmp;
  }
  static void BoxBlur(Bitmap bmp, int radius) {
    int w = bmp.Width, h = bmp.Height, r = Math.Max(1, radius);
    var rect = new Rectangle(0, 0, w, h);
    var data = bmp.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
    int stride = data.Stride;
    int bytes = stride * h;
    byte[] src = new byte[bytes];
    byte[] tmp = new byte[bytes];
    Marshal.Copy(data.Scan0, src, 0, bytes);
    for (int y = 0; y < h; y++) {
      int row = y * stride;
      for (int x = 0; x < w; x++) {
        int b = 0, g = 0, rd = 0, a = 0, c = 0;
        int x0 = Math.Max(0, x - r), x1 = Math.Min(w - 1, x + r);
        for (int i = x0; i <= x1; i++) {
          int p = row + i * 4;
          b += src[p]; g += src[p + 1]; rd += src[p + 2]; a += src[p + 3]; c++;
        }
        int o = row + x * 4;
        tmp[o] = (byte)(b / c); tmp[o + 1] = (byte)(g / c); tmp[o + 2] = (byte)(rd / c); tmp[o + 3] = (byte)(a / c);
      }
    }
    for (int x = 0; x < w; x++) {
      for (int y = 0; y < h; y++) {
        int b = 0, g = 0, rd = 0, a = 0, c = 0;
        int y0 = Math.Max(0, y - r), y1 = Math.Min(h - 1, y + r);
        for (int i = y0; i <= y1; i++) {
          int p = i * stride + x * 4;
          b += tmp[p]; g += tmp[p + 1]; rd += tmp[p + 2]; a += tmp[p + 3]; c++;
        }
        int o = y * stride + x * 4;
        src[o] = (byte)(b / c); src[o + 1] = (byte)(g / c); src[o + 2] = (byte)(rd / c); src[o + 3] = (byte)(a / c);
      }
    }
    Marshal.Copy(src, 0, data.Scan0, bytes);
    bmp.UnlockBits(data);
  }
}
public class GlassPanel : Panel {
  public GlassPanel() { BackColor = Color.Transparent; }
  protected override void OnPaintBackground(PaintEventArgs e) { PaintParent(this, e); }
  public static void PaintParent(Control self, PaintEventArgs e) {
    Form form = self.FindForm();
    PaintImage(self, e, form == null ? null : form.BackgroundImage);
  }
  public static void PaintImage(Control self, PaintEventArgs e, Image img) {
    Form form = self.FindForm();
    if (img == null || form == null || form.ClientSize.Width < 1 || form.ClientSize.Height < 1) { return; }
    Point screen = self.PointToScreen(Point.Empty);
    Point origin = form.PointToScreen(Point.Empty);
    int dx = screen.X - origin.X;
    int dy = screen.Y - origin.Y;
    Rectangle dest = e.ClipRectangle;
    float sx = img.Width / (float)form.ClientSize.Width;
    float sy = img.Height / (float)form.ClientSize.Height;
    var src = new RectangleF((dx + dest.X) * sx, (dy + dest.Y) * sy, Math.Max(1f, dest.Width * sx), Math.Max(1f, dest.Height * sy));
    e.Graphics.DrawImage(img, dest, src, GraphicsUnit.Pixel);
  }
}
public class FrostPanel : Panel {
  public Image Plate;
  public int Shade;
  public FrostPanel() {
    SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.Opaque | ControlStyles.ResizeRedraw, true);
    BackColor = Color.Black;
  }
  public static void PaintFrost(Control self, PaintEventArgs e) {
    FrostPanel card = self as FrostPanel;
    Control walk = self;
    while (card == null && walk != null) {
      walk = walk.Parent;
      card = walk as FrostPanel;
    }
    Image img = card == null ? null : card.Plate;
    if (img == null || card.Width < 1 || card.Height < 1) {
      GlassPanel.PaintParent(self, e);
    } else {
      Point origin = self.PointToScreen(Point.Empty);
      Point cardOrigin = card.PointToScreen(Point.Empty);
      float scale = Math.Max(card.Width / (float)img.Width, card.Height / (float)img.Height);
      int dw = Math.Max(1, (int)(img.Width * scale));
      int dh = Math.Max(1, (int)(img.Height * scale));
      int ox = cardOrigin.X - origin.X + (card.Width - dw) / 2;
      int oy = cardOrigin.Y - origin.Y + (card.Height - dh) / 2;
      e.Graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
      e.Graphics.DrawImage(img, ox, oy, dw, dh);
    }
    int alpha = Math.Min(200, 64 + (card == null ? 0 : card.Shade));
    using (var wash = new SolidBrush(Color.FromArgb(alpha, 0, 0, 0)))
      e.Graphics.FillRectangle(wash, e.ClipRectangle);
  }
  protected override void OnPaintBackground(PaintEventArgs e) { PaintFrost(this, e); }
}
public class MetalPlate : Control {
  public bool Light;
  bool hot;
  bool down;
  public MetalPlate() {
    SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
    Font = new Font("Segoe UI", 11f, FontStyle.Bold);
    Cursor = Cursors.Hand;
    Size = new Size(210, 36);
  }
  protected override void OnMouseEnter(EventArgs e) { hot = true; Invalidate(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { hot = false; down = false; Invalidate(); base.OnMouseLeave(e); }
  protected override void OnMouseDown(MouseEventArgs e) {
    if (e.Button == MouseButtons.Left) { down = true; Invalidate(); }
    base.OnMouseDown(e);
  }
  protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
  protected override void OnPaintBackground(PaintEventArgs e) { FrostPanel.PaintFrost(this, e); }
  protected override void OnPaint(PaintEventArgs e) {
    e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
    int inset = down ? 3 : 0;
    int shift = down ? 1 : 0;
    var rect = new Rectangle(shift, shift, Math.Max(1, Width - 1 - inset), Math.Max(1, Height - 1 - inset));
    Color top = Light ? Color.FromArgb(236, 236, 238) : Color.FromArgb(78, 80, 86);
    Color bottom = Light ? Color.FromArgb(168, 170, 176) : Color.FromArgb(28, 30, 34);
    Color edge = Light ? Color.FromArgb(250, 250, 252) : Color.FromArgb(120, 124, 132);
    if (down) {
      top = Light ? Color.FromArgb(150, 152, 158) : Color.FromArgb(36, 38, 42);
      bottom = Light ? Color.FromArgb(104, 106, 112) : Color.FromArgb(12, 14, 16);
      edge = Light ? Color.FromArgb(170, 172, 178) : Color.FromArgb(70, 74, 80);
    } else if (hot) {
      top = Light ? Color.FromArgb(196, 198, 204) : Color.FromArgb(56, 58, 64);
      bottom = Light ? Color.FromArgb(132, 134, 140) : Color.FromArgb(18, 20, 24);
      edge = Light ? Color.FromArgb(214, 216, 220) : Color.FromArgb(90, 94, 102);
    }
    Color ink = Light ? Color.FromArgb(28, 28, 30) : Color.White;
    using (var path = Rounded(rect, 8))
    using (var brush = new LinearGradientBrush(rect, top, bottom, LinearGradientMode.Vertical))
    using (var pen = new Pen(edge)) {
      e.Graphics.FillPath(brush, path);
      e.Graphics.DrawPath(pen, path);
    }
    TextRenderer.DrawText(e.Graphics, Text, Font, rect, ink, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
  }
  public static GraphicsPath Rounded(Rectangle rect, int radius) {
    int d = Math.Min(radius * 2, Math.Min(rect.Width, rect.Height));
    var path = new GraphicsPath();
    path.AddArc(rect.X, rect.Y, d, d, 180, 90);
    path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
    path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
    path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
    path.CloseFigure();
    return path;
  }
}
public class MetalButton : Button {
  bool hot;
  bool down;
  public MetalButton() {
    SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
    FlatStyle = FlatStyle.Flat;
    FlatAppearance.BorderSize = 0;
    Font = new Font("Segoe UI", 9f);
    ForeColor = Color.FromArgb(32, 32, 34);
    BackColor = Color.FromArgb(196, 198, 204);
    Height = 34;
  }
  protected override void OnMouseEnter(EventArgs e) { hot = true; Invalidate(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e) { hot = false; down = false; Invalidate(); base.OnMouseLeave(e); }
  protected override void OnMouseDown(MouseEventArgs e) {
    if (e.Button == MouseButtons.Left) { down = true; Invalidate(); }
    base.OnMouseDown(e);
  }
  protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
  protected override void OnPaint(PaintEventArgs e) {
    var back = Parent == null ? Color.FromArgb(12, 14, 18) : Parent.BackColor;
    e.Graphics.Clear(back);
    e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
    int inset = down ? 3 : 0;
    int shift = down ? 1 : 0;
    var rect = new Rectangle(shift, shift, Math.Max(1, Width - 1 - inset), Math.Max(1, Height - 1 - inset));
    Color top = Color.FromArgb(214, 216, 222);
    Color bottom = Color.FromArgb(154, 156, 164);
    Color edge = Color.FromArgb(238, 238, 242);
    if (down) {
      top = Color.FromArgb(108, 110, 118);
      bottom = Color.FromArgb(78, 80, 88);
      edge = Color.FromArgb(140, 142, 150);
    } else if (hot) {
      top = Color.FromArgb(164, 166, 174);
      bottom = Color.FromArgb(112, 114, 122);
      edge = Color.FromArgb(190, 192, 200);
    }
    using (var path = MetalPlate.Rounded(rect, 8))
    using (var brush = new LinearGradientBrush(rect, top, bottom, LinearGradientMode.Vertical))
    using (var pen = new Pen(edge)) {
      e.Graphics.FillPath(brush, path);
      e.Graphics.DrawPath(pen, path);
    }
    TextRenderer.DrawText(e.Graphics, Text, Font, rect, ForeColor, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
  }
  protected override void OnResize(EventArgs e) {
    base.OnResize(e);
    if (Width > 8 && Height > 8) Region = UiShape.Round(Width, Height, 8);
  }
}
public class GoldToggle : CheckBox {
  public GoldToggle() {
    SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
    AutoSize = false;
    Text = "";
    Size = new Size(52, 26);
  }
  protected override void OnPaint(PaintEventArgs e) {
    e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
    var back = Parent == null ? Color.FromArgb(12, 14, 18) : Parent.BackColor;
    e.Graphics.Clear(back);
    int tw = 54;
    int th = 26;
    int tx = Math.Max(0, Width - tw);
    int ty = Math.Max(0, (Height - th) / 2);
    var track = new Rectangle(tx, ty, tw - 1, th - 1);
    using (var path = MetalPlate.Rounded(track, th / 2))
    using (var fill = new SolidBrush(Color.FromArgb(62, 66, 74)))
    using (var pen = new Pen(Color.FromArgb(128, 132, 140))) {
      e.Graphics.FillPath(fill, path);
      e.Graphics.DrawPath(pen, path);
    }
    int knob = 18;
    int x = Checked ? tx + tw - knob - 5 : tx + 4;
    int y = ty + (th - knob) / 2;
    using (var brush = new SolidBrush(Checked ? Color.FromArgb(242, 196, 48) : Color.FromArgb(198, 200, 206)))
      e.Graphics.FillEllipse(brush, x, y, knob, knob);
  }
}
public class UiCaption {
  [DllImport("dwmapi.dll")]
  static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
  public static void Apply(IntPtr hwnd) {
    int on = 1;
    DwmSetWindowAttribute(hwnd, 19, ref on, 4);
    int caption = 0x00141416;
    int text = 0x00E4E4E4;
    int border = 0x002878E8;
    DwmSetWindowAttribute(hwnd, 20, ref on, 4);
    DwmSetWindowAttribute(hwnd, 35, ref caption, 4);
    DwmSetWindowAttribute(hwnd, 36, ref text, 4);
    DwmSetWindowAttribute(hwnd, 34, ref border, 4);
  }
}
public class LogoBox : PictureBox {
  Rectangle ink;
  bool inkReady;
  public LogoBox() {
    SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.Opaque, true);
  }
  Rectangle InkOf(Image img) {
    if (inkReady) return ink;
    inkReady = true;
    Bitmap bmp = img as Bitmap;
    if (bmp == null) { ink = new Rectangle(0, 0, img.Width, img.Height); return ink; }
    int minX = bmp.Width, minY = bmp.Height, maxX = -1, maxY = -1;
    for (int y = 0; y < bmp.Height; y += 2) {
      for (int x = 0; x < bmp.Width; x += 2) {
        if (bmp.GetPixel(x, y).A > 20) {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
    }
    ink = maxX < 0
      ? new Rectangle(0, 0, img.Width, img.Height)
      : Rectangle.FromLTRB(minX, minY, Math.Min(bmp.Width, maxX + 2), Math.Min(bmp.Height, maxY + 2));
    return ink;
  }
  protected override void OnPaintBackground(PaintEventArgs e) { FrostPanel.PaintFrost(this, e); }
  protected override void OnPaint(PaintEventArgs e) {
    FrostPanel.PaintFrost(this, e);
    if (Image == null || Width < 1 || Height < 1) return;
    float scale = Math.Min(Width / (float)Image.Width, Height / (float)Image.Height);
    int dw = Math.Max(1, (int)(Image.Width * scale));
    int dh = Math.Max(1, (int)(Image.Height * scale));
    int ix = (Width - dw) / 2;
    int iy = (Height - dh) / 2;
    Rectangle box = InkOf(Image);
    int lx = ix + (int)(box.X * scale);
    int ly = iy + (int)(box.Y * scale);
    int lw = Math.Max(8, (int)(box.Width * scale));
    int lh = Math.Max(8, (int)(box.Height * scale));
    int pad = Math.Max(10, (int)(Math.Min(lw, lh) * 0.08));
    int gx = lx - pad;
    int gy = ly - pad;
    int glowW = lw + pad * 2;
    int glowH = lh + pad * 2;
    int radius = Math.Max(18, Math.Min(glowW, glowH) / 5);
    e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
    e.Graphics.CompositingMode = CompositingMode.SourceOver;
    using (var path = new GraphicsPath()) {
      int d = radius * 2;
      path.AddArc(gx, gy, d, d, 180, 90);
      path.AddArc(gx + glowW - d, gy, d, d, 270, 90);
      path.AddArc(gx + glowW - d, gy + glowH - d, d, d, 0, 90);
      path.AddArc(gx, gy + glowH - d, d, d, 90, 90);
      path.CloseFigure();
      using (var brush = new PathGradientBrush(path)) {
        brush.CenterColor = Color.FromArgb(230, 255, 246, 232);
        brush.SurroundColors = new Color[] { Color.FromArgb(0, 232, 96, 18) };
        brush.FocusScales = new PointF(0.55f, 0.5f);
        e.Graphics.FillPath(brush, path);
      }
    }
    e.Graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
    e.Graphics.DrawImage(Image, ix, iy, dw, dh);
  }
}
public class GlassTable : TableLayoutPanel {
  public GlassTable() { BackColor = Color.Transparent; }
  protected override void OnPaintBackground(PaintEventArgs e) { GlassPanel.PaintParent(this, e); }
}
public class GlassFlow : FlowLayoutPanel {
  public GlassFlow() { BackColor = Color.Transparent; }
  protected override void OnPaintBackground(PaintEventArgs e) { GlassPanel.PaintParent(this, e); }
}
public class UiShape {
  public static Region Round(int width, int height, int radius) {
    int r = Math.Max(1, radius);
    int d = Math.Min(r * 2, Math.Min(width, height));
    var path = new GraphicsPath();
    path.AddArc(0, 0, d, d, 180, 90);
    path.AddArc(width - d, 0, d, d, 270, 90);
    path.AddArc(width - d, height - d, d, d, 0, 90);
    path.AddArc(0, height - d, d, d, 90, 90);
    path.CloseFigure();
    return new Region(path);
  }
  public static Region Chamfer(int width, int height, int cut) {
    int c = Math.Max(1, Math.Min(cut, Math.Min(width, height) / 3));
    var path = new GraphicsPath();
    path.AddPolygon(new Point[] {
      new Point(c, 0),
      new Point(width - c, 0),
      new Point(width, c),
      new Point(width, height - c),
      new Point(width - c, height),
      new Point(c, height),
      new Point(0, height - c),
      new Point(0, c)
    });
    return new Region(path);
  }
}
public class SessionCard : Control {
  public Image Plate;
  public Image Logo;
  public string Caption = "";
  public string Detail = "";
  public bool Light;
  int face;
  bool nameHot;
  bool nameDown;
  Rectangle nameHit;
  Rectangle ink;
  bool inkReady;
  readonly Font detailFont = new Font("Segoe UI", 9f);
  public SessionCard() {
    SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.Opaque, true);
    Cursor = Cursors.Hand;
    Font = new Font("Segoe UI", 11f, FontStyle.Bold);
  }
  static GraphicsPath ChamferPath(Rectangle r) {
    int c = Math.Max(16, Math.Min(r.Width, r.Height) / 7);
    var path = new GraphicsPath();
    path.AddPolygon(new Point[] {
      new Point(r.X + c, r.Y),
      new Point(r.Right - c, r.Y),
      new Point(r.Right, r.Y + c),
      new Point(r.Right, r.Bottom - c),
      new Point(r.Right - c, r.Bottom),
      new Point(r.X + c, r.Bottom),
      new Point(r.X, r.Bottom - c),
      new Point(r.X, r.Y + c)
    });
    return path;
  }
  Rectangle InkOf() {
    if (inkReady) return ink;
    inkReady = true;
    Bitmap bmp = Logo as Bitmap;
    if (bmp == null) {
      ink = Logo == null ? Rectangle.Empty : new Rectangle(0, 0, Logo.Width, Logo.Height);
      return ink;
    }
    int minX = bmp.Width, minY = bmp.Height, maxX = -1, maxY = -1;
    for (int y = 0; y < bmp.Height; y += 2) {
      for (int x = 0; x < bmp.Width; x += 2) {
        if (bmp.GetPixel(x, y).A > 20) {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
    }
    ink = maxX < 0
      ? new Rectangle(0, 0, bmp.Width, bmp.Height)
      : Rectangle.FromLTRB(minX, minY, Math.Min(bmp.Width, maxX + 2), Math.Min(bmp.Height, maxY + 2));
    return ink;
  }
  void SetFace(int next, bool hot, bool down) {
    if (face == next && nameHot == hot && nameDown == down) return;
    face = next;
    nameHot = hot;
    nameDown = down;
    Invalidate();
  }
  protected override void OnMouseMove(MouseEventArgs e) {
    int next = (e.Button & MouseButtons.Left) != 0 ? 2 : 1;
    bool hot = nameHit.Contains(e.Location);
    SetFace(next, hot, hot && next == 2);
    base.OnMouseMove(e);
  }
  protected override void OnMouseDown(MouseEventArgs e) {
    if (e.Button == MouseButtons.Left) {
      bool hot = nameHit.Contains(e.Location);
      SetFace(2, hot, hot);
    }
    base.OnMouseDown(e);
  }
  protected override void OnMouseUp(MouseEventArgs e) {
    bool inside = ClientRectangle.Contains(e.Location);
    SetFace(inside ? 1 : 0, inside && nameHit.Contains(e.Location), false);
    base.OnMouseUp(e);
  }
  protected override void OnMouseLeave(EventArgs e) {
    SetFace(0, false, false);
    base.OnMouseLeave(e);
  }
  protected override void OnPaint(PaintEventArgs e) {
    Graphics g = e.Graphics;
    g.SmoothingMode = SmoothingMode.AntiAlias;
    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
    GlassPanel.PaintImage(this, e, FindForm() == null ? null : FindForm().BackgroundImage);
    int inset = face == 1 ? 4 : face == 2 ? 10 : 18;
    var box = new Rectangle(inset, inset, Math.Max(8, Width - inset * 2), Math.Max(8, Height - inset * 2));
    using (GraphicsPath path = ChamferPath(box)) {
      g.SetClip(path);
      if (Plate != null) {
        float scale = Math.Max(box.Width / (float)Plate.Width, box.Height / (float)Plate.Height);
        int dw = Math.Max(1, (int)(Plate.Width * scale));
        int dh = Math.Max(1, (int)(Plate.Height * scale));
        g.DrawImage(Plate, box.X + (box.Width - dw) / 2, box.Y + (box.Height - dh) / 2, dw, dh);
      }
      if (Logo != null) {
        var art = new Rectangle(box.X + 6, box.Y + 6, Math.Max(1, box.Width - 12), Math.Max(1, box.Height - 84));
        float ls = Math.Min(art.Width / (float)Logo.Width, art.Height / (float)Logo.Height);
        int lw = Math.Max(1, (int)(Logo.Width * ls));
        int lh = Math.Max(1, (int)(Logo.Height * ls));
        int lx = art.X + (art.Width - lw) / 2;
        int ly = art.Y + (art.Height - lh) / 2;
        Rectangle mark = InkOf();
        if (mark.Width > 0 && mark.Height > 0) {
          int mx = lx + (int)(mark.X * ls);
          int my = ly + (int)(mark.Y * ls);
          int mw = Math.Max(8, (int)(mark.Width * ls));
          int mh = Math.Max(8, (int)(mark.Height * ls));
          int pad = Math.Max(8, Math.Min(mw, mh) / 12);
          var glow = new Rectangle(mx - pad, my - pad, mw + pad * 2, mh + pad * 2);
          using (GraphicsPath glowPath = MetalPlate.Rounded(glow, Math.Max(16, Math.Min(glow.Width, glow.Height) / 5)))
          using (var brush = new PathGradientBrush(glowPath)) {
            brush.CenterColor = Color.FromArgb(210, 255, 246, 232);
            brush.SurroundColors = new Color[] { Color.FromArgb(0, 232, 96, 18) };
            brush.FocusScales = new PointF(0.55f, 0.5f);
            g.FillPath(brush, glowPath);
          }
        }
        g.DrawImage(Logo, lx, ly, lw, lh);
      }
      int nw = Math.Min(240, Math.Max(48, box.Width - 28));
      int nh = 36;
      int nx = box.X + (box.Width - nw) / 2;
      int ny = box.Bottom - 62;
      nameHit = new Rectangle(nx, ny, nw, nh);
      var plateBox = nameHit;
      if (nameDown) plateBox = new Rectangle(nx + 3, ny + 2, nw - 6, nh - 4);
      Color top = Light ? Color.FromArgb(236, 236, 238) : Color.FromArgb(78, 80, 86);
      Color bottom = Light ? Color.FromArgb(168, 170, 176) : Color.FromArgb(28, 30, 34);
      Color edge = Light ? Color.FromArgb(250, 250, 252) : Color.FromArgb(120, 124, 132);
      if (nameDown) {
        top = Light ? Color.FromArgb(150, 152, 158) : Color.FromArgb(36, 38, 42);
        bottom = Light ? Color.FromArgb(104, 106, 112) : Color.FromArgb(12, 14, 16);
        edge = Light ? Color.FromArgb(170, 172, 178) : Color.FromArgb(70, 74, 80);
      } else if (nameHot) {
        top = Light ? Color.FromArgb(196, 198, 204) : Color.FromArgb(56, 58, 64);
        bottom = Light ? Color.FromArgb(132, 134, 140) : Color.FromArgb(18, 20, 24);
        edge = Light ? Color.FromArgb(214, 216, 220) : Color.FromArgb(90, 94, 102);
      }
      using (GraphicsPath plate = MetalPlate.Rounded(plateBox, 8))
      using (var fill = new LinearGradientBrush(plateBox, top, bottom, LinearGradientMode.Vertical))
      using (var pen = new Pen(edge)) {
        g.FillPath(fill, plate);
        g.DrawPath(pen, plate);
      }
      Color inkColor = Light ? Color.FromArgb(28, 28, 30) : Color.White;
      TextRenderer.DrawText(g, Caption ?? "", Font, plateBox, inkColor, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
      var detail = new Rectangle(box.X + 8, plateBox.Bottom + 2, Math.Max(1, box.Width - 16), 22);
      TextRenderer.DrawText(g, Detail ?? "", detailFont, detail, Color.FromArgb(186, 186, 186), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
      g.ResetClip();
      Color rim = face == 0 ? Color.FromArgb(214, 220, 228) : face == 2 ? Color.FromArgb(180, 70, 4) : Color.FromArgb(232, 93, 4);
      using (var rimPen = new Pen(rim, face == 0 ? 2f : 4f)) {
        rimPen.LineJoin = LineJoin.Miter;
        g.DrawPath(rimPen, path);
      }
    }
  }
}
"@
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class ExplorerFolder {
  public static string Pick(IntPtr owner, string title, string initial) {
    var dialog = (IFileOpenDialog)new FileOpenDialog();
    uint options;
    dialog.GetOptions(out options);
    dialog.SetOptions(options | 0x20u | 0x40u | 0x800u | 0x8u);
    if (!string.IsNullOrEmpty(title)) dialog.SetTitle(title);
    dialog.SetOkButtonLabel("Open");
    if (!string.IsNullOrEmpty(initial) && System.IO.Directory.Exists(initial)) {
      Guid iid = typeof(IShellItem).GUID;
      IShellItem start;
      if (SHCreateItemFromParsingName(initial, IntPtr.Zero, ref iid, out start) == 0 && start != null)
        dialog.SetFolder(start);
    }
    int hr = dialog.Show(owner);
    if (hr == unchecked((int)0x800704C7)) return null;
    if (hr != 0) Marshal.ThrowExceptionForHR(hr);
    IShellItem result;
    dialog.GetResult(out result);
    IntPtr name;
    result.GetDisplayName(0x80058000, out name);
    try { return Marshal.PtrToStringUni(name); }
    finally { if (name != IntPtr.Zero) Marshal.FreeCoTaskMem(name); }
  }
  [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
  static extern int SHCreateItemFromParsingName(
    [MarshalAs(UnmanagedType.LPWStr)] string pszPath,
    IntPtr pbc,
    ref Guid riid,
    [MarshalAs(UnmanagedType.Interface)] out IShellItem ppv);
}
[ComImport, Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")]
public class FileOpenDialog {}
[ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IShellItem {
  void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
  void GetParent(out IShellItem ppsi);
  void GetDisplayName(uint sigdnName, out IntPtr ppszName);
  void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
  void Compare(IShellItem psi, uint hint, out int piOrder);
}
[ComImport, Guid("d57c7288-d4ad-4768-be02-9d969532d960"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IFileOpenDialog {
  [PreserveSig] int Show(IntPtr parent);
  void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
  void SetFileTypeIndex(uint iFileType);
  void GetFileTypeIndex(out uint piFileType);
  void Advise(IntPtr pfde, out uint pdwCookie);
  void Unadvise(uint dwCookie);
  void SetOptions(uint fos);
  void GetOptions(out uint pfos);
  void SetDefaultFolder(IShellItem psi);
  void SetFolder(IShellItem psi);
  void GetFolder(out IShellItem ppsi);
  void GetCurrentSelection(out IShellItem ppsi);
  void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
  void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
  void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
  void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
  void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
  void GetResult(out IShellItem ppsi);
  void AddPlace(IShellItem psi, uint fdap);
  void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
  void Close(int hr);
  void SetClientGuid(ref Guid guid);
  void ClearClientData();
  void SetFilter(IntPtr pFilter);
  void GetResults(out IntPtr ppenum);
  void GetSelectedItems(out IntPtr ppsai);
}
"@
[System.Windows.Forms.Application]::EnableVisualStyles()

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$ReSkateArt = Join-Path $RepoRoot "Assets\Logos\reskate.png"
$SkateArt = Join-Path $RepoRoot "Assets\Logos\skate.png"
$Script:SkateRoot = $null

function Find-SkateRoots {
    $hits = New-Object System.Collections.Generic.List[string]
    $rels = @(
        "Steam\steamapps\common\Skate",
        "Program Files (x86)\Steam\steamapps\common\Skate",
        "Program Files\Steam\steamapps\common\Skate"
    )
    $letters = New-Object System.Collections.Generic.List[string]
    if ($Drive) {
        $clean = ($Drive.ToUpper() -replace "[^A-Z]", "")
        if ($clean.Length -ge 1) { $letters.Add($clean.Substring(0, 1)) }
    }
    foreach ($disk in [System.IO.DriveInfo]::GetDrives()) {
        if ($disk.DriveType -ne [System.IO.DriveType]::Fixed -or -not $disk.IsReady) { continue }
        $letters.Add($disk.Name.Substring(0, 1))
    }
    foreach ($letter in ($letters | Select-Object -Unique)) {
        foreach ($rel in $rels) {
            $path = "{0}:\{1}" -f $letter, $rel
            if (Test-Path -LiteralPath (Join-Path $path "Skate.exe")) {
                $full = [IO.Path]::GetFullPath($path).TrimEnd("\")
                $seen = $false
                foreach ($item in $hits) { if ($item -ieq $full) { $seen = $true; break } }
                if (-not $seen) { $hits.Add($full) }
            }
        }
    }
    return $hits
}

function Start-PowerShell {
    param([string]$Arguments, [switch]$Wait, [switch]$Hidden)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $info.Arguments = $Arguments
    $info.UseShellExecute = $false
    if ($Hidden) {
        $info.CreateNoWindow = $true
        $info.WindowStyle = "Hidden"
    }
    $proc = [System.Diagnostics.Process]::Start($info)
    if ($Wait) { $proc.WaitForExit() }
    return $proc
}

function Invoke-ModeSwitch {
    param([string]$Mode)
    $unpacker = Join-Path $RepoRoot "Source\Setup\Install.ps1"
    $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$unpacker`" -Action $Mode -Quiet -SkatePath `"$Script:SkateRoot`""
    $proc = Start-PowerShell -Arguments $argLine -Wait -Hidden
    if ($proc.ExitCode -ne 0) {
        throw "Could not switch to $Mode mode."
    }
}

function Start-ChosenGame {
    param([string]$Mode)
    if (-not $Script:SkateRoot) { throw "Choose the Skate folder first." }
    Invoke-ModeSwitch $Mode
    $exeName = $(if ($Mode -eq "ReSkate") { "ReSkateLauncher.exe" } else { "Skate.exe" })
    $exe = Join-Path $Script:SkateRoot $exeName
    if (-not (Test-Path -LiteralPath $exe)) {
        throw "$exeName is not in the Skate folder yet."
    }
    Start-Process -FilePath $exe -WorkingDirectory $Script:SkateRoot
    $form.Close()
}

function Set-ButtonChamfer($Control) {
    $apply = {
        param($sender, $e)
        if ($sender.Width -lt 16 -or $sender.Height -lt 16) { return }
        $sender.Region = [UiShape]::Round($sender.Width, $sender.Height, 14)
    }
    $Control.Add_Resize($apply)
    $Control.Add_HandleCreated($apply)
}

function New-LogoCard {
    param(
        [string]$ImagePath,
        [string]$Caption,
        [string]$Detail,
        [string]$Mode,
        [System.Drawing.Color]$Hot,
        [System.Drawing.Image]$CardArt
    )

    $card = New-Object SessionCard
    $card.Dock = "Fill"
    $card.Margin = New-Object System.Windows.Forms.Padding(8, 4, 8, 6)
    $card.Plate = $CardArt
    $card.Caption = $Caption
    $card.Detail = $Detail
    $card.Light = ($Mode -eq "Skate")
    $card.Tag = $Mode
    if (Test-Path -LiteralPath $ImagePath) {
        $card.Logo = [System.Drawing.Image]::FromFile($ImagePath)
    }
    $card.Add_Click({
        try { Start-ChosenGame ([string]$this.Tag) }
        catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "ReSkate") | Out-Null }
    })
    return $card
}

function Get-ReSkateSettings {
    $path = Join-Path $RepoRoot "ReSkate.settings.json"
    $settings = @{ reskate = $false; mods = $false; allowed = @() }
    if (-not (Test-Path -LiteralPath $path)) { return $settings }
    try {
        $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        foreach ($key in @("reskate", "mods")) {
            $prop = $json.PSObject.Properties[$key]
            if ($prop) { $settings[$key] = [bool]$prop.Value }
        }
        $allowed = $json.PSObject.Properties["allowed"]
        if ($allowed) { $settings.allowed = @($allowed.Value | ForEach-Object { [string]$_ }) }
    }
    catch {}
    return $settings
}

function Save-ReSkateSettings {
    param($Settings)
    $payload = [ordered]@{
        reskate = [bool]$Settings.reskate
        mods    = [bool]$Settings.mods
        allowed = @($Settings.allowed)
    }
    $payload | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $RepoRoot "ReSkate.settings.json") -Encoding UTF8
}

function Test-PathAllowed {
    param([string]$Folder)
    if ([string]::IsNullOrWhiteSpace($Folder)) { return $true }
    $full = [System.IO.Path]::GetFullPath($Folder).TrimEnd("\")
    foreach ($item in @((Get-ReSkateSettings).allowed)) {
        if (-not $item) { continue }
        $have = [System.IO.Path]::GetFullPath([string]$item).TrimEnd("\")
        if ($have -ieq $full) { return $true }
    }
    return $false
}

function Request-DefenderAllow {
    param([string[]]$Paths)
    if (-not (Get-Command Get-MpPreference -ErrorAction SilentlyContinue)) { return }
    $need = New-Object System.Collections.Generic.List[string]
    foreach ($folder in @($Paths)) {
        if ($folder -and -not (Test-PathAllowed $folder)) { [void]$need.Add($folder) }
    }
    if ($need.Count -eq 0) { return }
    $allow = Join-Path $RepoRoot "Source\Setup\Allow.ps1"
    $cmd = "-NoProfile -ExecutionPolicy Bypass -File `"$allow`" -RepoRoot `"$RepoRoot`""
    foreach ($folder in $need) { $cmd += " -Path `"$folder`"" }
    try {
        $proc = Start-Process `
            -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -ArgumentList $cmd `
            -Wait `
            -PassThru
        $code = 1
        if ($null -ne $proc -and $null -ne $proc.ExitCode) { $code = $proc.ExitCode }
        if ($code -eq 0 -or $code -eq 2 -or $code -eq 1223) { return }
        throw "Windows antivirus exclusion was not added."
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Press Yes on the Windows prompt so ReSkate is allowed through antivirus.`r`nYou can also run ReSkate.bat allow.",
            "ReSkate"
        ) | Out-Null
    }
}

function Select-GameFolder {
    param([IntPtr]$Owner, [string]$Start)
    try {
        return [ExplorerFolder]::Pick($Owner, "Select the folder that contains Skate.exe", $Start)
    }
    catch {
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = "Open the folder that contains Skate.exe"
        $dialog.Filter = "Skate (Skate.exe)|Skate.exe|All files (*.*)|*.*"
        $dialog.FileName = "Skate.exe"
        $dialog.CheckFileExists = $false
        $dialog.CheckPathExists = $true
        $dialog.ValidateNames = $false
        if ($Start -and (Test-Path -LiteralPath $Start)) { $dialog.InitialDirectory = $Start }
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
        $chosen = $dialog.FileName
        if (Test-Path -LiteralPath $chosen -PathType Container) { return $chosen }
        return (Split-Path -Parent $chosen)
    }
}

function Start-ReSkateUpdate {
    if (-not $Script:SkateRoot) { return }
    $script = Join-Path $RepoRoot "Source\Setup\Install.ps1"
    $argLine = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`" -Action Update -Quiet -SkatePath `"$Script:SkateRoot`""
    Start-PowerShell -Arguments $argLine -Hidden | Out-Null
}

function Open-Tool {
    param([string]$Action)
    if ($Action -eq "Mods") {
        $script = Join-Path $RepoRoot "Source\Mods\Mods.ps1"
        $argLine = "-NoProfile -Sta -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
        Start-PowerShell -Arguments $argLine -Hidden | Out-Null
        return
    }
    $script = Join-Path $RepoRoot "Source\Setup\Install.ps1"
    $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -Action $Action"
    if ($Script:SkateRoot) { $argLine += " -SkatePath `"$Script:SkateRoot`"" }
    Start-PowerShell -Arguments $argLine | Out-Null
}

$bg = [System.Drawing.Color]::FromArgb(8, 8, 8)
$panelBg = [System.Drawing.Color]::FromArgb(16, 16, 16)

$form = New-Object System.Windows.Forms.Form
$form.Text = "ReSkate"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(1180, 820)
$form.MinimumSize = New-Object System.Drawing.Size(980, 680)
$form.BackColor = $bg
$form.ForeColor = [System.Drawing.Color]::White
$bgArt = Join-Path $RepoRoot "Assets\Backgrounds\window.jpg"
if (Test-Path -LiteralPath $bgArt) {
    $form.BackgroundImage = [UiBackdrop]::Make($bgArt, 1180, 760)
    $form.BackgroundImageLayout = "Stretch"
}

$title = New-Object System.Windows.Forms.Label
$title.Text = "C H O O S E   A   S E S S I O N"
$title.Dock = "Top"
$title.Height = 58
$title.TextAlign = "BottomCenter"
$title.ForeColor = [System.Drawing.Color]::FromArgb(196, 200, 208)
$title.BackColor = [System.Drawing.Color]::Transparent
$title.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)

$footer = New-Object System.Windows.Forms.Panel
$footer.Dock = "Bottom"
$footer.Height = 58
$footer.BackColor = [System.Drawing.Color]::FromArgb(12, 14, 18)
$footer.Padding = New-Object System.Windows.Forms.Padding(14, 12, 18, 12)

$pathBox = New-Object System.Windows.Forms.ComboBox
$pathBox.Dock = "Fill"
$pathBox.DropDownStyle = "DropDownList"
$pathBox.FlatStyle = "Flat"
$pathBox.BackColor = $panelBg
$pathBox.ForeColor = [System.Drawing.Color]::FromArgb(210, 210, 210)
$pathBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$pathBox.DrawMode = "OwnerDrawFixed"
$pathBox.ItemHeight = 22
$pathBox.Add_DrawItem({
    param($sender, $e)
    if ($e.Index -lt 0) { return }
    $selected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
    $fill = $(if ($selected) { [System.Drawing.Color]::FromArgb(78, 78, 78) } else { $panelBg })
    $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush $fill), $e.Bounds)
    $e.Graphics.DrawString(
        [string]$sender.Items[$e.Index],
        $e.Font,
        [System.Drawing.Brushes]::White,
        ($e.Bounds.X + 6),
        ($e.Bounds.Y + 3)
    )
})

$bar = New-Object System.Windows.Forms.TableLayoutPanel
$bar.Dock = "Fill"
$bar.ColumnCount = 6
$bar.RowCount = 1
$bar.BackColor = $footer.BackColor
$bar.Margin = New-Object System.Windows.Forms.Padding(0)
$bar.Padding = New-Object System.Windows.Forms.Padding(0)
[void]$bar.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$bar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
foreach ($width in 104, 104, 104, 104, 210) {
    [void]$bar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, $width)))
}
$pathBox.Dock = "Fill"
$pathBox.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$bar.Controls.Add($pathBox, 0, 0)

$browse = New-Object MetalButton
$browse.Text = "Folder"
$browse.Dock = "Fill"
$browse.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$bar.Controls.Add($browse, 1, 0)

$col = 2
foreach ($pair in @(
    @{ Text = "Update"; Action = "All" },
    @{ Text = "Mods"; Action = "Mods" },
    @{ Text = "Check"; Action = "Check" }
)) {
    $button = New-Object MetalButton
    $button.Text = $pair.Text
    $button.Dock = "Fill"
    $button.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    $button.Tag = $pair.Action
    $button.Add_Click({
        try { Open-Tool ([string]$this.Tag) }
        catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "ReSkate") | Out-Null }
    })
    $bar.Controls.Add($button, $col, 0)
    $col++
}

$autoHost = New-Object System.Windows.Forms.Panel
$autoHost.Dock = "Fill"
$autoHost.BackColor = $footer.BackColor
$autoHost.Margin = New-Object System.Windows.Forms.Padding(0)
$autoLabel = New-Object System.Windows.Forms.Label
$autoLabel.Text = "Auto-update"
$autoLabel.Dock = "Left"
$autoLabel.Width = 108
$autoLabel.TextAlign = "MiddleLeft"
$autoLabel.ForeColor = [System.Drawing.Color]::White
$autoLabel.BackColor = $footer.BackColor
$autoLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$autoBox = New-Object GoldToggle
$autoBox.Size = New-Object System.Drawing.Size(58, 28)
$autoBox.Anchor = "Right"
$autoHost.Add_Resize({
    $autoBox.Left = [Math]::Max(0, $autoHost.ClientSize.Width - $autoBox.Width)
    $autoBox.Top = [Math]::Max(0, [int](($autoHost.ClientSize.Height - $autoBox.Height) / 2))
}.GetNewClosure())
$autoBox.Checked = [bool](Get-ReSkateSettings).reskate
$autoBox.Add_CheckedChanged({
    $saved = Get-ReSkateSettings
    $saved.reskate = $autoBox.Checked
    Save-ReSkateSettings $saved
    if ($autoBox.Checked) { Start-ReSkateUpdate }
})
$autoHost.Controls.Add($autoBox)
$autoHost.Controls.Add($autoLabel)
$bar.Controls.Add($autoHost, 5, 0)
$footer.Controls.Add($bar)

$table = New-Object GlassTable
$table.Dock = "Fill"
$table.ColumnCount = 2
$table.RowCount = 1
$table.BackColor = [System.Drawing.Color]::Transparent
$table.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 0)
[void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
[void]$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$orange = [System.Drawing.Color]::FromArgb(232, 93, 4)
$steel = [System.Drawing.Color]::FromArgb(210, 210, 210)
$Script:CardStreams = New-Object System.Collections.Generic.List[object]
function Open-CardArt([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $stream = New-Object System.IO.MemoryStream(,$bytes)
    [void]$Script:CardStreams.Add($stream)
    return [System.Drawing.Image]::FromStream($stream)
}
$rePlate = Open-CardArt (Join-Path $RepoRoot "Assets\Backgrounds\reskate-card.jpg")
$skPlate = Open-CardArt (Join-Path $RepoRoot "Assets\Backgrounds\skate-card.jpg")
$table.Controls.Add((New-LogoCard $ReSkateArt "RESKATE" "Overhaul, mods, offline play" "ReSkate" $orange $rePlate), 0, 0)
$table.Controls.Add((New-LogoCard $SkateArt "SKATE" "Official game" "Skate" $steel $skPlate), 1, 0)

$edgeLine = [System.Drawing.Color]::FromArgb(232, 120, 40)
$topLine = New-Object System.Windows.Forms.Panel
$topLine.Height = 2
$topLine.Dock = "Top"
$topLine.BackColor = $edgeLine
$bottomLine = New-Object System.Windows.Forms.Panel
$bottomLine.Height = 2
$bottomLine.Dock = "Bottom"
$bottomLine.BackColor = $edgeLine
$form.Controls.Add($table)
$form.Controls.Add($footer)
$form.Controls.Add($title)
$form.Controls.Add($topLine)
$form.Controls.Add($bottomLine)

$pathBox.Add_SelectedIndexChanged({
    if ($pathBox.SelectedItem) { $Script:SkateRoot = [string]$pathBox.SelectedItem }
})

$browse.Add_Click({
    try {
        $start = $Script:SkateRoot
        if (-not $start -and $pathBox.SelectedItem) { $start = [string]$pathBox.SelectedItem }
        $picked = Select-GameFolder -Owner $form.Handle -Start $start
        if (-not $picked) { return }
        $Script:SkateRoot = [System.IO.Path]::GetFullPath($picked)
        if (-not $pathBox.Items.Contains($Script:SkateRoot)) { [void]$pathBox.Items.Add($Script:SkateRoot) }
        $pathBox.SelectedItem = $Script:SkateRoot
        Request-DefenderAllow -Paths @($Script:SkateRoot)
    }
    catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "ReSkate") | Out-Null }
})

$form.Add_HandleCreated({ try { [UiCaption]::Apply($form.Handle) } catch {} })
$Script:FoundRoots = @()
$form.Add_Shown({
    try { [UiCaption]::Apply($form.Handle) } catch {}
    foreach ($hit in @($Script:FoundRoots)) { [void]$pathBox.Items.Add($hit) }
    if ($pathBox.Items.Count -gt 0) { $pathBox.SelectedIndex = 0 }
    if ($autoBox.Checked) { Start-ReSkateUpdate }
})

$Script:FoundRoots = @(Find-SkateRoots)
$allowPaths = New-Object System.Collections.Generic.List[string]
[void]$allowPaths.Add($RepoRoot)
foreach ($hit in @($Script:FoundRoots)) { [void]$allowPaths.Add($hit) }
Request-DefenderAllow -Paths $allowPaths.ToArray()

[void]$form.ShowDialog()
