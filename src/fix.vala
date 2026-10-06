namespace Singularity.Apps.ColorPicker {

    public class ContrastSuggestion : Object {
        public Color original;
        public Color other;
        public Color suggested;
        public double target;
        public double before;
        public double after;
        public double lightness_before;
        public double lightness_after;
        public bool already_passes;
        public bool found;
        public bool chroma_kept = true;
    }

    namespace ContrastFix {
        private const double SCAN_STEP = 0.002;
        private const double NUDGE_STEP = 0.0005;
        private const double GAMUT_EPSILON = 1e-7;

        public double required (bool aaa, bool large) {
            if (large) return aaa ? Contrast.AAA_LARGE : Contrast.AA_LARGE;
            return aaa ? Contrast.AAA : Contrast.AA;
        }

        public bool oklch_in_gamut (double l, double c, double h) {
            double rad = h * Math.PI / 180;
            double lr, lg, lb;
            Color.oklab_to_linear (l, c * Math.cos (rad), c * Math.sin (rad), out lr, out lg, out lb);
            return lr >= -GAMUT_EPSILON && lr <= 1 + GAMUT_EPSILON
                && lg >= -GAMUT_EPSILON && lg <= 1 + GAMUT_EPSILON
                && lb >= -GAMUT_EPSILON && lb <= 1 + GAMUT_EPSILON;
        }

        private bool passes (double l, double c, double h, Color other, double target) {
            if (!oklch_in_gamut (l, c, h)) return false;
            return Contrast.ratio (Color.from_oklch (l, c, h), other) >= target;
        }

        private Color? quantized (double l, double c, double h) {
            return Color.from_hex (Color.from_oklch (l, c, h).to_hex ());
        }

        private bool search (double l0, double c, double h, int dir, Color other, double target, out double found_l, out Color? found) {
            found_l = l0;
            found = null;
            double prev = l0;
            double l = l0;
            while (true) {
                l += dir * SCAN_STEP;
                if (l < 0) l = 0;
                if (l > 1) l = 1;
                if (!oklch_in_gamut (l, c, h)) return false;
                if (passes (l, c, h, other, target)) break;
                if (l <= 0 || l >= 1) return false;
                prev = l;
            }
            double fail = prev, ok = l;
            for (int i = 0; i < 40; i++) {
                double mid = (fail + ok) / 2;
                if (passes (mid, c, h, other, target)) ok = mid;
                else fail = mid;
            }
            double candidate = ok;
            for (int i = 0; i < 400; i++) {
                if (!oklch_in_gamut (candidate, c, h)) return false;
                var q = quantized (candidate, c, h);
                if (q != null && Contrast.ratio (q, other) >= target) {
                    found_l = candidate;
                    found = q;
                    return true;
                }
                candidate += dir * NUDGE_STEP;
                if (candidate < 0 || candidate > 1) return false;
            }
            return false;
        }

        private bool best_for_chroma (double l0, double c, double h, Color other, double target, out double best_l, out Color? best) {
            best_l = l0;
            best = null;
            double up_l, down_l;
            Color? up, down;
            bool has_up = search (l0, c, h, 1, other, target, out up_l, out up);
            bool has_down = search (l0, c, h, -1, other, target, out down_l, out down);
            if (!has_up && !has_down) return false;
            if (has_up && (!has_down || Math.fabs (up_l - l0) <= Math.fabs (down_l - l0))) {
                best_l = up_l;
                best = up;
            } else {
                best_l = down_l;
                best = down;
            }
            return true;
        }

        public ContrastSuggestion suggest (Color adjust, Color other, double target) {
            var s = new ContrastSuggestion ();
            var solid_other = other.over (new Color (1, 1, 1));
            var solid = adjust.over (solid_other);
            s.original = solid;
            s.other = solid_other;
            s.target = target;
            s.before = Contrast.ratio (solid, solid_other);
            double l0, c0, h0;
            solid.to_oklch (out l0, out c0, out h0);
            s.lightness_before = l0;
            s.lightness_after = l0;
            s.suggested = solid.copy ();
            s.after = s.before;
            if (s.before >= target) {
                s.already_passes = true;
                s.found = true;
                return s;
            }
            for (int step = 0; step <= 10; step++) {
                double scale = (10 - step) / 10.0;
                double best_l;
                Color? best;
                if (!best_for_chroma (l0, c0 * scale, h0, solid_other, target, out best_l, out best)) continue;
                if (step > 0) {
                    double works = scale, fails = scale + 0.1;
                    for (int i = 0; i < 12; i++) {
                        double mid = (works + fails) / 2;
                        double mid_l;
                        Color? mid_best;
                        if (best_for_chroma (l0, c0 * mid, h0, solid_other, target, out mid_l, out mid_best)) {
                            works = mid;
                            best_l = mid_l;
                            best = mid_best;
                        } else {
                            fails = mid;
                        }
                    }
                }
                s.found = true;
                s.chroma_kept = step == 0;
                s.suggested = best;
                s.lightness_after = best_l;
                s.after = Contrast.ratio (best, solid_other);
                return s;
            }
            return s;
        }
    }
}
