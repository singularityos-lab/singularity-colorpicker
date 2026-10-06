namespace Singularity.Apps.ColorPicker {

    public enum Deficiency {
        NONE,
        PROTANOPIA,
        DEUTERANOPIA,
        TRITANOPIA,
        ACHROMATOPSIA;

        public string id () {
            switch (this) {
                case PROTANOPIA: return "protanopia";
                case DEUTERANOPIA: return "deuteranopia";
                case TRITANOPIA: return "tritanopia";
                case ACHROMATOPSIA: return "achromatopsia";
                default: return "none";
            }
        }

        public string label () {
            switch (this) {
                case PROTANOPIA: return _("Protanopia");
                case DEUTERANOPIA: return _("Deuteranopia");
                case TRITANOPIA: return _("Tritanopia");
                case ACHROMATOPSIA: return _("Achromatopsia");
                default: return _("Typical Vision");
            }
        }

        public string description () {
            switch (this) {
                case PROTANOPIA: return _("No red cones: reds look dark and close to greens");
                case DEUTERANOPIA: return _("No green cones: reds and greens are hard to tell apart");
                case TRITANOPIA: return _("No blue cones: blues and greens, yellows and pinks merge");
                case ACHROMATOPSIA: return _("No color at all: only lightness is seen");
                default: return _("Colors as most people see them");
            }
        }

        public static Deficiency from_id (string id) {
            foreach (var d in all ()) if (d.id () == id) return d;
            return NONE;
        }

        public static Deficiency[] all () {
            return { NONE, PROTANOPIA, DEUTERANOPIA, TRITANOPIA, ACHROMATOPSIA };
        }

        public static Deficiency[] deficiencies () {
            return { PROTANOPIA, DEUTERANOPIA, TRITANOPIA, ACHROMATOPSIA };
        }
    }

    namespace Vision {
        private const double[] PROTAN = {
            0.152286, 1.052583, -0.204868,
            0.114503, 0.786281, 0.099216,
            -0.003882, -0.048116, 1.051998
        };

        private const double[] DEUTAN = {
            0.367322, 0.860646, -0.227968,
            0.280085, 0.672501, 0.047413,
            -0.011820, 0.042940, 0.968881
        };

        private const double[] TRITAN = {
            1.255528, -0.076749, -0.178779,
            -0.078411, 0.930809, 0.147602,
            0.004733, 0.691367, 0.303900
        };

        private const double[] MONO = {
            0.2126, 0.7152, 0.0722,
            0.2126, 0.7152, 0.0722,
            0.2126, 0.7152, 0.0722
        };

        private const double[] IDENTITY = {
            1, 0, 0,
            0, 1, 0,
            0, 0, 1
        };

        public double[] matrix (Deficiency d) {
            switch (d) {
                case Deficiency.PROTANOPIA: return PROTAN;
                case Deficiency.DEUTERANOPIA: return DEUTAN;
                case Deficiency.TRITANOPIA: return TRITAN;
                case Deficiency.ACHROMATOPSIA: return MONO;
                default: return IDENTITY;
            }
        }

        public void apply_linear (Deficiency d, double r, double g, double b, out double or, out double og, out double ob) {
            var m = matrix (d);
            or = (m[0] * r + m[1] * g + m[2] * b).clamp (0, 1);
            og = (m[3] * r + m[4] * g + m[5] * b).clamp (0, 1);
            ob = (m[6] * r + m[7] * g + m[8] * b).clamp (0, 1);
        }

        public Color simulate (Color c, Deficiency d) {
            if (d == Deficiency.NONE) return c.copy ();
            double r, g, b;
            apply_linear (d, Color.to_linear (c.r), Color.to_linear (c.g), Color.to_linear (c.b), out r, out g, out b);
            return new Color (Color.from_linear (r), Color.from_linear (g), Color.from_linear (b), c.a);
        }

        private const int OUT_STEPS = 16384;

        public void simulate_pixels (uint8[] data, int width, int height, int stride, Deficiency d) {
            if (d == Deficiency.NONE) return;
            var m = matrix (d);
            double[] to_lin = new double[256];
            for (int i = 0; i < 256; i++) to_lin[i] = Color.to_linear (i / 255.0);
            uint8[] to_srgb = new uint8[OUT_STEPS + 1];
            for (int i = 0; i <= OUT_STEPS; i++) {
                to_srgb[i] = (uint8) Math.round (Color.from_linear ((double) i / OUT_STEPS) * 255);
            }
            for (int y = 0; y < height; y++) {
                int row = y * stride;
                for (int x = 0; x < width; x++) {
                    int i = row + x * 4;
                    double r = to_lin[data[i]], g = to_lin[data[i + 1]], b = to_lin[data[i + 2]];
                    double nr = (m[0] * r + m[1] * g + m[2] * b).clamp (0, 1);
                    double ng = (m[3] * r + m[4] * g + m[5] * b).clamp (0, 1);
                    double nb = (m[6] * r + m[7] * g + m[8] * b).clamp (0, 1);
                    data[i] = to_srgb[(int) Math.round (nr * OUT_STEPS)];
                    data[i + 1] = to_srgb[(int) Math.round (ng * OUT_STEPS)];
                    data[i + 2] = to_srgb[(int) Math.round (nb * OUT_STEPS)];
                }
            }
        }
    }
}
