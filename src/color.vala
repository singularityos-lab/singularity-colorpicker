namespace Singularity.Apps.ColorPicker {

    public class Color : Object {
        public double r;
        public double g;
        public double b;
        public double a;

        public Color (double r, double g, double b, double a = 1.0) {
            this.r = r.clamp (0, 1);
            this.g = g.clamp (0, 1);
            this.b = b.clamp (0, 1);
            this.a = a.clamp (0, 1);
        }

        public Color.rgb8 (int r, int g, int b, double a = 1.0) {
            this (r / 255.0, g / 255.0, b / 255.0, a);
        }

        public Color copy () {
            return new Color (r, g, b, a);
        }

        public bool equals (Color o) {
            return to_hex (true) == o.to_hex (true);
        }

        public static double to_linear (double c) {
            return c <= 0.04045 ? c / 12.92 : Math.pow ((c + 0.055) / 1.055, 2.4);
        }

        public static double from_linear (double c) {
            if (c <= 0.0031308) return 12.92 * c;
            return 1.055 * Math.pow (c, 1 / 2.4) - 0.055;
        }

        private static int byte_of (double v) {
            return (int) Math.round (v.clamp (0, 1) * 255);
        }

        public int red8 { get { return byte_of (r); } }
        public int green8 { get { return byte_of (g); } }
        public int blue8 { get { return byte_of (b); } }

        public string to_hex (bool with_alpha = false, bool upper = false) {
            string s = "#%02x%02x%02x".printf (byte_of (r), byte_of (g), byte_of (b));
            if (with_alpha || a < 1.0) {
                if (byte_of (a) < 255 || with_alpha) s += "%02x".printf (byte_of (a));
            }
            return upper ? s.up () : s;
        }

        public static Color? from_hex (string text) {
            string s = text.strip ();
            if (s.has_prefix ("#")) s = s.substring (1);
            if (s.length != 3 && s.length != 4 && s.length != 6 && s.length != 8) return null;
            for (int i = 0; i < s.length; i++) {
                if (!s[i].isxdigit ()) return null;
            }
            if (s.length <= 4) {
                var sb = new StringBuilder ();
                for (int i = 0; i < s.length; i++) {
                    sb.append_c (s[i]);
                    sb.append_c (s[i]);
                }
                s = sb.str;
            }
            int[] v = {};
            for (int i = 0; i < s.length; i += 2) {
                v += s[i].xdigit_value () * 16 + s[i + 1].xdigit_value ();
            }
            return new Color.rgb8 (v[0], v[1], v[2], v.length == 4 ? v[3] / 255.0 : 1.0);
        }

        public void to_hsl (out double h, out double s, out double l) {
            double max = double.max (r, double.max (g, b));
            double min = double.min (r, double.min (g, b));
            double d = max - min;
            l = (max + min) / 2;
            h = hue_of (max, d);
            s = d < 1e-12 ? 0 : d / (1 - Math.fabs (2 * l - 1));
            s = s.clamp (0, 1);
        }

        public static Color from_hsl (double h, double s, double l, double a = 1.0) {
            double c = (1 - Math.fabs (2 * l - 1)) * s;
            double x = c * (1 - Math.fabs (Math.fmod (norm_hue (h) / 60, 2) - 1));
            double m = l - c / 2;
            double r1, g1, b1;
            sector (norm_hue (h), c, x, out r1, out g1, out b1);
            return new Color (r1 + m, g1 + m, b1 + m, a);
        }

        public void to_hsv (out double h, out double s, out double v) {
            double max = double.max (r, double.max (g, b));
            double min = double.min (r, double.min (g, b));
            double d = max - min;
            v = max;
            h = hue_of (max, d);
            s = max < 1e-12 ? 0 : d / max;
        }

        public static Color from_hsv (double h, double s, double v, double a = 1.0) {
            double c = v * s;
            double x = c * (1 - Math.fabs (Math.fmod (norm_hue (h) / 60, 2) - 1));
            double m = v - c;
            double r1, g1, b1;
            sector (norm_hue (h), c, x, out r1, out g1, out b1);
            return new Color (r1 + m, g1 + m, b1 + m, a);
        }

        private double hue_of (double max, double d) {
            if (d < 1e-12) return 0;
            double h;
            if (max == r) h = 60 * Math.fmod ((g - b) / d, 6);
            else if (max == g) h = 60 * ((b - r) / d + 2);
            else h = 60 * ((r - g) / d + 4);
            return norm_hue (h);
        }

        private static void sector (double h, double c, double x, out double r1, out double g1, out double b1) {
            if (h < 60) { r1 = c; g1 = x; b1 = 0; }
            else if (h < 120) { r1 = x; g1 = c; b1 = 0; }
            else if (h < 180) { r1 = 0; g1 = c; b1 = x; }
            else if (h < 240) { r1 = 0; g1 = x; b1 = c; }
            else if (h < 300) { r1 = x; g1 = 0; b1 = c; }
            else { r1 = c; g1 = 0; b1 = x; }
        }

        public static double norm_hue (double h) {
            double n = Math.fmod (h, 360);
            if (n < 0) n += 360;
            if (n >= 360) n -= 360;
            return n;
        }

        public void to_cmyk (out double c, out double m, out double y, out double k) {
            double max = double.max (r, double.max (g, b));
            k = 1 - max;
            if (max < 1e-12) {
                c = m = y = 0;
                return;
            }
            c = (1 - r - k) / (1 - k);
            m = (1 - g - k) / (1 - k);
            y = (1 - b - k) / (1 - k);
        }

        public static Color from_cmyk (double c, double m, double y, double k, double a = 1.0) {
            return new Color ((1 - c) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k), a);
        }

        public void to_xyz (out double x, out double y, out double z) {
            double lr = to_linear (r), lg = to_linear (g), lb = to_linear (b);
            x = 0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb;
            y = 0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb;
            z = 0.0193339 * lr + 0.1191920 * lg + 0.9503041 * lb;
        }

        public static Color from_xyz (double x, double y, double z, double a = 1.0) {
            double lr = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z;
            double lg = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z;
            double lb = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z;
            return new Color (from_linear (lr), from_linear (lg), from_linear (lb), a);
        }

        public const double WHITE_X = 0.95047;
        public const double WHITE_Y = 1.0;
        public const double WHITE_Z = 1.08883;
        private const double EPSILON = 216.0 / 24389.0;
        private const double KAPPA = 24389.0 / 27.0;

        private static double lab_f (double t) {
            return t > EPSILON ? Math.cbrt (t) : (KAPPA * t + 16) / 116;
        }

        public void to_lab (out double l, out double la, out double lb) {
            double x, y, z;
            to_xyz (out x, out y, out z);
            double fx = lab_f (x / WHITE_X), fy = lab_f (y / WHITE_Y), fz = lab_f (z / WHITE_Z);
            l = 116 * fy - 16;
            la = 500 * (fx - fy);
            lb = 200 * (fy - fz);
        }

        public static Color from_lab (double l, double la, double lb, double a = 1.0) {
            double fy = (l + 16) / 116;
            double fx = fy + la / 500;
            double fz = fy - lb / 200;
            double x3 = fx * fx * fx, z3 = fz * fz * fz;
            double xr = x3 > EPSILON ? x3 : (116 * fx - 16) / KAPPA;
            double yr = l > KAPPA * EPSILON ? fy * fy * fy : l / KAPPA;
            double zr = z3 > EPSILON ? z3 : (116 * fz - 16) / KAPPA;
            return from_xyz (xr * WHITE_X, yr * WHITE_Y, zr * WHITE_Z, a);
        }

        public void to_lch (out double l, out double c, out double h) {
            double la, lb;
            to_lab (out l, out la, out lb);
            polar (la, lb, out c, out h);
        }

        public static Color from_lch (double l, double c, double h, double a = 1.0) {
            double rad = h * Math.PI / 180;
            return from_lab (l, c * Math.cos (rad), c * Math.sin (rad), a);
        }

        public void to_oklab (out double l, out double oa, out double ob) {
            linear_to_oklab (to_linear (r), to_linear (g), to_linear (b), out l, out oa, out ob);
        }

        public static void oklab_to_linear (double l, double oa, double ob, out double lr, out double lg, out double lb) {
            double lc = l + 0.3963377774 * oa + 0.2158037573 * ob;
            double mc = l - 0.1055613458 * oa - 0.0638541728 * ob;
            double sc = l - 0.0894841775 * oa - 1.2914855480 * ob;
            double l3 = lc * lc * lc, m3 = mc * mc * mc, s3 = sc * sc * sc;
            lr = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3;
            lg = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3;
            lb = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3;
        }

        public static void linear_to_oklab (double lr, double lg, double lb, out double l, out double oa, out double ob) {
            double lc = Math.cbrt (0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
            double mc = Math.cbrt (0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
            double sc = Math.cbrt (0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
            l = 0.2104542553 * lc + 0.7936177850 * mc - 0.0040720468 * sc;
            oa = 1.9779984951 * lc - 2.4285922050 * mc + 0.4505937099 * sc;
            ob = 0.0259040371 * lc + 0.7827717662 * mc - 0.8086757660 * sc;
        }

        public static Color from_oklab (double l, double oa, double ob, double a = 1.0) {
            double lr, lg, lb;
            oklab_to_linear (l, oa, ob, out lr, out lg, out lb);
            return new Color (from_linear (lr), from_linear (lg), from_linear (lb), a);
        }

        public void to_oklch (out double l, out double c, out double h) {
            double oa, ob;
            to_oklab (out l, out oa, out ob);
            polar (oa, ob, out c, out h);
            if (c < 1e-4) h = 0;
        }

        public static Color from_oklch (double l, double c, double h, double a = 1.0) {
            double rad = h * Math.PI / 180;
            return from_oklab (l, c * Math.cos (rad), c * Math.sin (rad), a);
        }

        private static void polar (double x, double y, out double c, out double h) {
            c = Math.sqrt (x * x + y * y);
            h = c < 1e-9 ? 0 : norm_hue (Math.atan2 (y, x) * 180 / Math.PI);
        }

        public double luminance () {
            return 0.2126 * to_linear (r) + 0.7152 * to_linear (g) + 0.0722 * to_linear (b);
        }

        public Color over (Color bg) {
            if (a >= 1.0) return new Color (r, g, b, 1);
            return new Color (r * a + bg.r * (1 - a), g * a + bg.g * (1 - a), b * a + bg.b * (1 - a), 1);
        }

        public Color mix (Color o, double t) {
            return new Color (r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t, a + (o.a - a) * t);
        }

        public double delta_e (Color o) {
            double l1, a1, b1, l2, a2, b2;
            to_lab (out l1, out a1, out b1);
            o.to_lab (out l2, out a2, out b2);
            double c1 = Math.sqrt (a1 * a1 + b1 * b1), c2 = Math.sqrt (a2 * a2 + b2 * b2);
            double cm7 = Math.pow ((c1 + c2) / 2, 7);
            double g = 0.5 * (1 - Math.sqrt (cm7 / (cm7 + Math.pow (25, 7))));
            double ap1 = a1 * (1 + g), ap2 = a2 * (1 + g);
            double cp1 = Math.sqrt (ap1 * ap1 + b1 * b1), cp2 = Math.sqrt (ap2 * ap2 + b2 * b2);
            double hp1 = cp1 < 1e-9 ? 0 : norm_hue (Math.atan2 (b1, ap1) * 180 / Math.PI);
            double hp2 = cp2 < 1e-9 ? 0 : norm_hue (Math.atan2 (b2, ap2) * 180 / Math.PI);
            double dl = l2 - l1, dc = cp2 - cp1;
            double dh = 0;
            if (cp1 * cp2 > 1e-9) {
                dh = hp2 - hp1;
                if (dh > 180) dh -= 360;
                else if (dh < -180) dh += 360;
            }
            double dhh = 2 * Math.sqrt (cp1 * cp2) * Math.sin (dh * Math.PI / 360);
            double lm = (l1 + l2) / 2, cm = (cp1 + cp2) / 2;
            double hm = hp1 + hp2;
            if (cp1 * cp2 > 1e-9) {
                if (Math.fabs (hp1 - hp2) <= 180) hm /= 2;
                else hm = hm < 360 ? (hm + 360) / 2 : (hm - 360) / 2;
            }
            double rad = Math.PI / 180;
            double t = 1 - 0.17 * Math.cos ((hm - 30) * rad) + 0.24 * Math.cos (2 * hm * rad)
                + 0.32 * Math.cos ((3 * hm + 6) * rad) - 0.20 * Math.cos ((4 * hm - 63) * rad);
            double dtheta = 30 * Math.exp (-((hm - 275) / 25) * ((hm - 275) / 25));
            double cm7p = Math.pow (cm, 7);
            double rc = 2 * Math.sqrt (cm7p / (cm7p + Math.pow (25, 7)));
            double sl = 1 + 0.015 * (lm - 50) * (lm - 50) / Math.sqrt (20 + (lm - 50) * (lm - 50));
            double sc = 1 + 0.045 * cm;
            double sh = 1 + 0.015 * cm * t;
            double rt = -Math.sin (2 * dtheta * rad) * rc;
            double tl = dl / sl, tc = dc / sc, th = dhh / sh;
            return Math.sqrt (tl * tl + tc * tc + th * th + rt * tc * th);
        }

        public Color rotate_hue (double degrees) {
            double h, s, l;
            to_hsl (out h, out s, out l);
            return from_hsl (h + degrees, s, l, a);
        }
    }

    public enum Format {
        HEX,
        RGB,
        HSL,
        HSV,
        CMYK,
        LAB,
        LCH,
        OKLCH;

        public string label () {
            switch (this) {
                case HEX: return "Hex";
                case RGB: return "RGB";
                case HSL: return "HSL";
                case HSV: return "HSV";
                case CMYK: return "CMYK";
                case LAB: return "CIELAB";
                case LCH: return "LCH";
                default: return "OKLCH";
            }
        }

        public static Format[] all () {
            return { HEX, RGB, HSL, HSV, CMYK, LAB, LCH, OKLCH };
        }

        public string id () {
            switch (this) {
                case HEX: return "hex";
                case RGB: return "rgb";
                case HSL: return "hsl";
                case HSV: return "hsv";
                case CMYK: return "cmyk";
                case LAB: return "lab";
                case LCH: return "lch";
                default: return "oklch";
            }
        }

        public static Format from_id (string? id) {
            foreach (var f in all ()) {
                if (f.id () == id) return f;
            }
            return HEX;
        }
    }

    namespace Formatter {
        public string num (double v, int decimals) {
            double p = Math.pow (10, decimals);
            double rounded = Math.round (v * p) / p;
            if (rounded == 0) rounded = 0;
            char[] buf = new char[double.DTOSTR_BUF_SIZE];
            string s = rounded.format (buf, "%." + decimals.to_string () + "f");
            if (s.contains (".")) {
                while (s.has_suffix ("0")) s = s.substring (0, s.length - 1);
                if (s.has_suffix (".")) s = s.substring (0, s.length - 1);
            }
            if (s == "-0") s = "0";
            return s;
        }

        private string alpha_suffix (Color c, string sep) {
            return c.a < 1.0 ? sep + num (c.a, 3) : "";
        }

        public string format (Color c, Format f, bool upper_hex = false) {
            switch (f) {
                case Format.HEX:
                    return c.to_hex (false, upper_hex);
                case Format.RGB:
                    if (c.a < 1.0) return "rgba(%d, %d, %d, %s)".printf (c.red8, c.green8, c.blue8, num (c.a, 3));
                    return "rgb(%d, %d, %d)".printf (c.red8, c.green8, c.blue8);
                case Format.HSL:
                    double h, s, l;
                    c.to_hsl (out h, out s, out l);
                    return "hsl(%s, %s%%, %s%%%s)".printf (num (h, 1), num (s * 100, 1), num (l * 100, 1), alpha_suffix (c, ", "));
                case Format.HSV:
                    double hh, ss, vv;
                    c.to_hsv (out hh, out ss, out vv);
                    return "hsv(%s, %s%%, %s%%%s)".printf (num (hh, 1), num (ss * 100, 1), num (vv * 100, 1), alpha_suffix (c, ", "));
                case Format.CMYK:
                    double cc, mm, yy, kk;
                    c.to_cmyk (out cc, out mm, out yy, out kk);
                    return "cmyk(%s%%, %s%%, %s%%, %s%%)".printf (num (cc * 100, 1), num (mm * 100, 1), num (yy * 100, 1), num (kk * 100, 1));
                case Format.LAB:
                    double ll, la, lb;
                    c.to_lab (out ll, out la, out lb);
                    return "lab(%s%% %s %s%s)".printf (num (ll, 2), num (la, 2), num (lb, 2), alpha_suffix (c, " / "));
                case Format.LCH:
                    double l2, c2, h2;
                    c.to_lch (out l2, out c2, out h2);
                    return "lch(%s%% %s %s%s)".printf (num (l2, 2), num (c2, 2), num (h2, 2), alpha_suffix (c, " / "));
                default:
                    double l3, c3, h3;
                    c.to_oklch (out l3, out c3, out h3);
                    return "oklch(%s%% %s %s%s)".printf (num (l3 * 100, 2), num (c3, 4), num (h3, 2), alpha_suffix (c, " / "));
            }
        }
    }

    namespace Parser {
        private struct Arg {
            public double value;
            public bool percent;
        }

        private bool parse_args (string body, out Arg[] args) {
            Arg[] list = {};
            args = list;
            string cleaned = body.replace (",", " ").replace ("/", " ");
            foreach (string raw in cleaned.split (" ")) {
                string t = raw.strip ().down ();
                if (t == "") continue;
                var arg = Arg ();
                if (t.has_suffix ("%")) {
                    arg.percent = true;
                    t = t.substring (0, t.length - 1);
                } else if (t.has_suffix ("deg")) {
                    t = t.substring (0, t.length - 3);
                }
                if (t == "none") t = "0";
                double v;
                if (!double.try_parse (t, out v)) return false;
                arg.value = v;
                list += arg;
            }
            args = list;
            return true;
        }

        private double unit (Arg a, double scale) {
            return a.percent ? a.value / 100 : a.value / scale;
        }

        private double alpha_of (Arg[] args, int index) {
            if (args.length <= index) return 1.0;
            return args[index].percent ? args[index].value / 100 : args[index].value;
        }

        public Color? parse (string text) {
            string s = text.strip ().down ();
            if (s == "") return null;
            var hex = Color.from_hex (s);
            if (hex != null) return hex;
            var named = NamedColors.lookup (s);
            if (named != null) return named;
            int open = s.index_of ("(");
            if (open <= 0 || !s.has_suffix (")")) return null;
            string fn = s.substring (0, open).strip ();
            Arg[] args;
            if (!parse_args (s.substring (open + 1, s.length - open - 2), out args)) return null;
            if (args.length < 3) return null;
            switch (fn) {
                case "rgb":
                case "rgba":
                    return new Color (unit (args[0], 255), unit (args[1], 255), unit (args[2], 255), alpha_of (args, 3));
                case "hsl":
                case "hsla":
                    return Color.from_hsl (args[0].value, args[1].value / 100, args[2].value / 100, alpha_of (args, 3));
                case "hsv":
                case "hsb":
                    return Color.from_hsv (args[0].value, args[1].value / 100, args[2].value / 100, alpha_of (args, 3));
                case "cmyk":
                    if (args.length < 4) return null;
                    bool fractions = true;
                    for (int i = 0; i < 4; i++) if (args[i].percent || args[i].value > 1) fractions = false;
                    double scale = fractions ? 1 : 100;
                    return Color.from_cmyk (unit (args[0], scale), unit (args[1], scale), unit (args[2], scale), unit (args[3], scale), alpha_of (args, 4));
                case "lab":
                    return Color.from_lab (args[0].value, args[1].value, args[2].value, alpha_of (args, 3));
                case "lch":
                    return Color.from_lch (args[0].value, args[1].value, args[2].value, alpha_of (args, 3));
                case "oklab":
                    return Color.from_oklab (unit (args[0], 1), args[1].value, args[2].value, alpha_of (args, 3));
                case "oklch":
                    return Color.from_oklch (unit (args[0], 1), args[1].value, args[2].value, alpha_of (args, 3));
                default:
                    return null;
            }
        }
    }

    namespace Contrast {
        public const double AA = 4.5;
        public const double AA_LARGE = 3.0;
        public const double AAA = 7.0;
        public const double AAA_LARGE = 4.5;

        public double ratio (Color fg, Color bg) {
            var solid_bg = bg.over (new Color (1, 1, 1));
            var solid_fg = fg.over (solid_bg);
            double l1 = solid_fg.luminance (), l2 = solid_bg.luminance ();
            double hi = double.max (l1, l2), lo = double.min (l1, l2);
            return (hi + 0.05) / (lo + 0.05);
        }

        public string format_ratio (double ratio) {
            return Formatter.num (Math.floor (ratio * 100) / 100, 2) + ":1";
        }
    }

    public enum Harmony {
        SHADES,
        TINTS,
        COMPLEMENTARY,
        ANALOGOUS,
        TRIADIC;

        public string id () {
            switch (this) {
                case SHADES: return "shades";
                case TINTS: return "tints";
                case COMPLEMENTARY: return "complementary";
                case ANALOGOUS: return "analogous";
                default: return "triadic";
            }
        }

        public static Harmony from_id (string id) {
            foreach (var h in all ()) if (h.id () == id) return h;
            return SHADES;
        }

        public static Harmony[] all () {
            return { SHADES, TINTS, COMPLEMENTARY, ANALOGOUS, TRIADIC };
        }
    }

    namespace Palette {
        public Color[] generate (Color c, Harmony kind, int steps = 6) {
            Color[] out_v = {};
            switch (kind) {
                case Harmony.SHADES:
                    var black = new Color (0, 0, 0, c.a);
                    for (int i = 0; i < steps; i++) out_v += c.mix (black, (double) i / steps);
                    break;
                case Harmony.TINTS:
                    var white = new Color (1, 1, 1, c.a);
                    for (int i = 0; i < steps; i++) out_v += c.mix (white, (double) i / steps);
                    break;
                case Harmony.COMPLEMENTARY:
                    out_v += c.copy ();
                    out_v += c.rotate_hue (180);
                    break;
                case Harmony.ANALOGOUS:
                    out_v += c.rotate_hue (-30);
                    out_v += c.copy ();
                    out_v += c.rotate_hue (30);
                    break;
                case Harmony.TRIADIC:
                    out_v += c.copy ();
                    out_v += c.rotate_hue (120);
                    out_v += c.rotate_hue (240);
                    break;
            }
            return out_v;
        }
    }

    public class History : Object {
        public const int LIMIT = 50;
        public Gee.ArrayList<Color> items = new Gee.ArrayList<Color> ();
        public string path { get; private set; }
        public string? load_error { get; private set; }
        public signal void changed ();

        public History (string? file = null) {
            path = file ?? Path.build_filename (Environment.get_user_data_dir (), "singularity", "colorpicker", "history.json");
            load ();
        }

        private void load () {
            items.clear ();
            if (!FileUtils.test (path, FileTest.EXISTS)) return;
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (path);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.ARRAY) return;
                foreach (var node in root.get_array ().get_elements ()) {
                    if (node.get_value_type () != typeof (string)) continue;
                    var c = Color.from_hex (node.get_string ());
                    if (c != null && items.size < LIMIT) items.add (c);
                }
            } catch (Error e) {
                load_error = e.message;
            }
        }

        public void reload () {
            string before = serialize ();
            load ();
            if (serialize () != before) changed ();
        }

        private string serialize () {
            var sb = new StringBuilder ();
            foreach (var c in items) sb.append (c.to_hex (c.a < 1.0)).append_c (' ');
            return sb.str;
        }

        public bool save () {
            var b = new Json.Builder ();
            b.begin_array ();
            foreach (var c in items) b.add_string_value (c.to_hex (c.a < 1.0));
            b.end_array ();
            var gen = new Json.Generator ();
            gen.pretty = true;
            gen.set_root (b.get_root ());
            try {
                DirUtils.create_with_parents (Path.get_dirname (path), 0700);
                FileUtils.set_contents (path, gen.to_data (null));
            } catch (Error e) {
                warning ("colorpicker: %s", e.message);
                return false;
            }
            return true;
        }

        public void add (Color c) {
            for (int i = 0; i < items.size; i++) {
                if (items[i].equals (c)) {
                    items.remove_at (i);
                    break;
                }
            }
            items.insert (0, c.copy ());
            while (items.size > LIMIT) items.remove_at (items.size - 1);
            save ();
            changed ();
        }

        public void remove (Color c) {
            for (int i = 0; i < items.size; i++) {
                if (items[i].equals (c)) {
                    items.remove_at (i);
                    break;
                }
            }
            save ();
            changed ();
        }

        public void clear () {
            items.clear ();
            save ();
            changed ();
        }
    }
}
