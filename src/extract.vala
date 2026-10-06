namespace Singularity.Apps.ColorPicker {

    public class PaletteColor : Object {
        public Color color;
        public double share;

        public PaletteColor (Color color, double share) {
            this.color = color;
            this.share = share;
        }
    }

    namespace Extract {
        public const int MIN_COLORS = 5;
        public const int MAX_COLORS = 12;
        private const int MAX_ITERATIONS = 60;
        private const double MERGE_DISTANCE = 0.015;

        public class Points : Object {
            public double[] lab = {};
            public double[] weight = {};
            public int count { get { return weight.length; } }
        }

        private const int BINS = 32768;

        public Points bin_pixels (uint8[] data, int width, int height, int stride) {
            double[] sr = new double[BINS];
            double[] sg = new double[BINS];
            double[] sb = new double[BINS];
            int[] n = new int[BINS];
            for (int y = 0; y < height; y++) {
                int row = y * stride;
                for (int x = 0; x < width; x++) {
                    int i = row + x * 4;
                    if (data[i + 3] < 128) continue;
                    int key = ((data[i] >> 3) << 10) | ((data[i + 1] >> 3) << 5) | (data[i + 2] >> 3);
                    sr[key] += data[i];
                    sg[key] += data[i + 1];
                    sb[key] += data[i + 2];
                    n[key]++;
                }
            }
            int used = 0;
            for (int s = 0; s < BINS; s++) if (n[s] > 0) used++;
            double[] lab = new double[used * 3];
            double[] weight = new double[used];
            int p = 0;
            for (int s = 0; s < BINS; s++) {
                if (n[s] == 0) continue;
                double l, a, b;
                Color.linear_to_oklab (Color.to_linear (sr[s] / n[s] / 255.0), Color.to_linear (sg[s] / n[s] / 255.0),
                    Color.to_linear (sb[s] / n[s] / 255.0), out l, out a, out b);
                lab[p * 3] = l;
                lab[p * 3 + 1] = a;
                lab[p * 3 + 2] = b;
                weight[p] = n[s];
                p++;
            }
            var points = new Points ();
            points.lab = lab;
            points.weight = weight;
            return points;
        }

        private double dist2 (double[] p, int i, double[] c, int j) {
            double dl = p[i * 3] - c[j * 3];
            double da = p[i * 3 + 1] - c[j * 3 + 1];
            double db = p[i * 3 + 2] - c[j * 3 + 2];
            return dl * dl + da * da + db * db;
        }

        private int nearest (double[] p, int i, double[] c, int k, out double best) {
            int index = 0;
            best = double.MAX;
            for (int j = 0; j < k; j++) {
                double d = dist2 (p, i, c, j);
                if (d < best) {
                    best = d;
                    index = j;
                }
            }
            return index;
        }

        private double[] seed_centers (Points pts, int k, Rand rand) {
            int n = pts.count;
            double[] centers = new double[k * 3];
            double total = 0;
            int first = 0;
            for (int i = 0; i < n; i++) {
                if (pts.weight[i] > pts.weight[first]) first = i;
            }
            for (int d = 0; d < 3; d++) centers[d] = pts.lab[first * 3 + d];
            double[] closest = new double[n];
            for (int i = 0; i < n; i++) closest[i] = dist2 (pts.lab, i, centers, 0);
            for (int c = 1; c < k; c++) {
                total = 0;
                for (int i = 0; i < n; i++) total += closest[i] * pts.weight[i];
                int pick = 0;
                if (total <= 0) {
                    pick = rand.int_range (0, n);
                } else {
                    double target = rand.next_double () * total;
                    double acc = 0;
                    for (int i = 0; i < n; i++) {
                        acc += closest[i] * pts.weight[i];
                        if (acc >= target) {
                            pick = i;
                            break;
                        }
                    }
                }
                for (int d = 0; d < 3; d++) centers[c * 3 + d] = pts.lab[pick * 3 + d];
                for (int i = 0; i < n; i++) {
                    double dd = dist2 (pts.lab, i, centers, c);
                    if (dd < closest[i]) closest[i] = dd;
                }
            }
            return centers;
        }

        public PaletteColor[] kmeans (Points pts, int k, uint32 seed = 7) {
            PaletteColor[] result = {};
            int n = pts.count;
            if (n == 0 || k <= 0) return result;
            if (k > n) k = n;
            var rand = new Rand.with_seed (seed);
            double[] centers = seed_centers (pts, k, rand);
            int[] owner = new int[n];
            for (int i = 0; i < n; i++) owner[i] = -1;
            double[] mass = new double[k];
            for (int iter = 0; iter < MAX_ITERATIONS; iter++) {
                bool moved = false;
                for (int i = 0; i < n; i++) {
                    double d;
                    int j = nearest (pts.lab, i, centers, k, out d);
                    if (j != owner[i]) {
                        owner[i] = j;
                        moved = true;
                    }
                }
                double[] sum = new double[k * 3];
                for (int j = 0; j < k; j++) mass[j] = 0;
                for (int i = 0; i < n; i++) {
                    int j = owner[i];
                    double w = pts.weight[i];
                    mass[j] += w;
                    for (int d = 0; d < 3; d++) sum[j * 3 + d] += pts.lab[i * 3 + d] * w;
                }
                for (int j = 0; j < k; j++) {
                    if (mass[j] <= 0) continue;
                    for (int d = 0; d < 3; d++) centers[j * 3 + d] = sum[j * 3 + d] / mass[j];
                }
                if (!moved) break;
            }
            merge_close (centers, mass, k);
            double total = 0;
            for (int j = 0; j < k; j++) total += mass[j];
            int[] order = {};
            for (int j = 0; j < k; j++) if (mass[j] > 0) order += j;
            for (int a = 1; a < order.length; a++) {
                int v = order[a];
                int b = a - 1;
                while (b >= 0 && mass[order[b]] < mass[v]) {
                    order[b + 1] = order[b];
                    b--;
                }
                order[b + 1] = v;
            }
            foreach (int j in order) {
                var c = Color.from_oklab (centers[j * 3], centers[j * 3 + 1], centers[j * 3 + 2]);
                result += new PaletteColor (c, mass[j] / total);
            }
            return result;
        }

        private void merge_close (double[] centers, double[] mass, int k) {
            double limit = MERGE_DISTANCE * MERGE_DISTANCE;
            for (int a = 0; a < k; a++) {
                if (mass[a] <= 0) continue;
                for (int b = a + 1; b < k; b++) {
                    if (mass[b] <= 0) continue;
                    if (dist2 (centers, a, centers, b) > limit) continue;
                    double total = mass[a] + mass[b];
                    for (int d = 0; d < 3; d++) {
                        centers[a * 3 + d] = (centers[a * 3 + d] * mass[a] + centers[b * 3 + d] * mass[b]) / total;
                    }
                    mass[a] = total;
                    mass[b] = 0;
                }
            }
        }

        public PaletteColor[] from_pixels (uint8[] data, int width, int height, int stride, int k) {
            k = k.clamp (MIN_COLORS, MAX_COLORS);
            return kmeans (bin_pixels (data, width, height, stride), k);
        }
    }
}
