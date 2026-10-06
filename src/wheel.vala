using Gtk;

namespace Singularity.Apps.ColorPicker {

    namespace Paint {
        public void rounded (Cairo.Context cr, double x, double y, double w, double h, double r) {
            r = double.min (r, double.min (w, h) / 2);
            cr.new_sub_path ();
            cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
            cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
            cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
            cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
            cr.close_path ();
        }

        public void checkerboard (Cairo.Context cr, double w, double h) {
            cr.save ();
            cr.clip_preserve ();
            cr.set_source_rgb (1, 1, 1);
            cr.fill ();
            cr.set_source_rgb (0.8, 0.8, 0.8);
            int cell = 8;
            for (int y = 0; y * cell < h; y++) {
                for (int x = 0; x * cell < w; x++) {
                    if ((x + y) % 2 == 0) cr.rectangle (x * cell, y * cell, cell, cell);
                }
            }
            cr.fill ();
            cr.restore ();
        }
    }

    public class Swatch : DrawingArea {
        private Color _color = new Color (0, 0, 0);
        public double radius { get; set; default = 12; }

        public Color color {
            get { return _color; }
            set {
                _color = value;
                queue_draw ();
            }
        }

        public Swatch (int w, int h, double radius = 12) {
            this.radius = radius;
            set_size_request (w, h);
            set_draw_func (draw);
        }

        private void draw (DrawingArea da, Cairo.Context cr, int w, int h) {
            Paint.rounded (cr, 0.5, 0.5, w - 1, h - 1, radius);
            if (_color.a < 1.0) {
                Paint.checkerboard (cr, w, h);
                Paint.rounded (cr, 0.5, 0.5, w - 1, h - 1, radius);
            }
            cr.set_source_rgba (_color.r, _color.g, _color.b, _color.a);
            cr.fill_preserve ();
            cr.set_source_rgba (0, 0, 0, 0.14);
            cr.set_line_width (1);
            cr.stroke ();
        }
    }

    public class ColorWheel : DrawingArea {
        public double hue { get; private set; }
        public double saturation { get; private set; }
        public double brightness { get; private set; default = 1; }
        public signal void changed ();

        private Cairo.ImageSurface? cache;
        private int cache_size;
        private double cache_brightness = -1;

        public ColorWheel () {
            set_size_request (240, 240);
            focusable = true;
            can_focus = true;
            add_css_class ("colorpicker-wheel");
            tooltip_text = _("Drag to change the hue and saturation. Arrow keys adjust them too.");
            set_draw_func (draw);

            var drag = new GestureDrag ();
            double sx = 0, sy = 0;
            drag.drag_begin.connect ((x, y) => {
                sx = x;
                sy = y;
                grab_focus ();
                pick_at (x, y);
            });
            drag.drag_update.connect ((dx, dy) => pick_at (sx + dx, sy + dy));
            add_controller (drag);

            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((keyval, code, state) => {
                switch (keyval) {
                    case Gdk.Key.Left:
                        set_hsv (hue + 2, saturation, brightness, true);
                        return true;
                    case Gdk.Key.Right:
                        set_hsv (hue - 2, saturation, brightness, true);
                        return true;
                    case Gdk.Key.Up:
                        set_hsv (hue, saturation + 0.02, brightness, true);
                        return true;
                    case Gdk.Key.Down:
                        set_hsv (hue, saturation - 0.02, brightness, true);
                        return true;
                }
                return false;
            });
            add_controller (keys);
        }

        public void set_hsv (double h, double s, double v, bool notify_change = false) {
            hue = Color.norm_hue (h);
            saturation = s.clamp (0, 1);
            brightness = v.clamp (0, 1);
            queue_draw ();
            if (notify_change) changed ();
        }

        private void geometry (out double cx, out double cy, out double radius) {
            int w = get_width (), h = get_height ();
            cx = w / 2.0;
            cy = h / 2.0;
            radius = double.min (w, h) / 2.0 - 8;
        }

        private void pick_at (double x, double y) {
            double cx, cy, radius;
            geometry (out cx, out cy, out radius);
            double dx = x - cx, dy = cy - y;
            double dist = Math.sqrt (dx * dx + dy * dy);
            double h = Math.atan2 (dy, dx) * 180 / Math.PI;
            set_hsv (h, dist / radius, brightness, true);
        }

        private void render (int size, double radius) {
            cache = new Cairo.ImageSurface (Cairo.Format.ARGB32, size, size);
            unowned uchar[] data = cache.get_data ();
            int stride = cache.get_stride ();
            double c = size / 2.0;
            for (int y = 0; y < size; y++) {
                for (int x = 0; x < size; x++) {
                    double dx = x + 0.5 - c, dy = c - (y + 0.5);
                    double dist = Math.sqrt (dx * dx + dy * dy);
                    double alpha = (radius + 0.5 - dist).clamp (0, 1);
                    int i = y * stride + x * 4;
                    if (alpha <= 0) {
                        data[i] = data[i + 1] = data[i + 2] = data[i + 3] = 0;
                        continue;
                    }
                    var col = Color.from_hsv (Math.atan2 (dy, dx) * 180 / Math.PI, double.min (dist / radius, 1), brightness);
                    data[i] = (uchar) Math.round (col.b * 255 * alpha);
                    data[i + 1] = (uchar) Math.round (col.g * 255 * alpha);
                    data[i + 2] = (uchar) Math.round (col.r * 255 * alpha);
                    data[i + 3] = (uchar) Math.round (255 * alpha);
                }
            }
            cache.mark_dirty ();
            cache_size = size;
            cache_brightness = brightness;
        }

        private void draw (DrawingArea da, Cairo.Context cr, int w, int h) {
            double cx, cy, radius;
            geometry (out cx, out cy, out radius);
            if (radius <= 4) return;
            int size = (int) Math.ceil (radius * 2 + 2);
            if (cache == null || cache_size != size || cache_brightness != brightness) render (size, radius);
            double ox = Math.round (cx - size / 2.0), oy = Math.round (cy - size / 2.0);
            cr.set_source_surface (cache, ox, oy);
            cr.paint ();
            cr.arc (cx, cy, radius, 0, 2 * Math.PI);
            cr.set_source_rgba (0, 0, 0, 0.12);
            cr.set_line_width (1);
            cr.stroke ();

            double rad = hue * Math.PI / 180;
            double mx = cx + Math.cos (rad) * saturation * radius;
            double my = cy - Math.sin (rad) * saturation * radius;
            var current = Color.from_hsv (hue, saturation, brightness);
            cr.arc (mx, my, 9, 0, 2 * Math.PI);
            cr.set_source_rgb (current.r, current.g, current.b);
            cr.fill_preserve ();
            cr.set_source_rgb (1, 1, 1);
            cr.set_line_width (3);
            cr.stroke_preserve ();
            cr.arc (mx, my, 10.5, 0, 2 * Math.PI);
            cr.set_source_rgba (0, 0, 0, 0.45);
            cr.set_line_width (1);
            cr.stroke ();
            if (has_focus) {
                cr.arc (cx, cy, radius + 4, 0, 2 * Math.PI);
                var accent = get_color ();
                cr.set_source_rgba (accent.red, accent.green, accent.blue, 0.5);
                cr.set_line_width (2);
                cr.stroke ();
            }
        }

        public override void state_flags_changed (StateFlags previous) {
            base.state_flags_changed (previous);
            queue_draw ();
        }
    }

    public class ContrastPreview : DrawingArea {
        public Color foreground { get; set; default = new Color (0, 0, 0); }
        public Color background { get; set; default = new Color (1, 1, 1); }

        public ContrastPreview () {
            set_size_request (-1, 96);
            hexpand = true;
            set_draw_func (draw);
            notify["foreground"].connect (() => queue_draw ());
            notify["background"].connect (() => queue_draw ());
        }

        private void draw (DrawingArea da, Cairo.Context cr, int w, int h) {
            Paint.rounded (cr, 0.5, 0.5, w - 1, h - 1, 12);
            if (background.a < 1.0) {
                Paint.checkerboard (cr, w, h);
                Paint.rounded (cr, 0.5, 0.5, w - 1, h - 1, 12);
            }
            cr.set_source_rgba (background.r, background.g, background.b, background.a);
            cr.fill_preserve ();
            cr.set_source_rgba (0, 0, 0, 0.14);
            cr.set_line_width (1);
            cr.stroke ();

            var layout = Pango.cairo_create_layout (cr);
            layout.set_font_description (Pango.FontDescription.from_string ("Sans Bold 26"));
            layout.set_text (_("Large Text"), -1);
            int lw, lh;
            layout.get_pixel_size (out lw, out lh);
            var small = Pango.cairo_create_layout (cr);
            small.set_font_description (Pango.FontDescription.from_string ("Sans 11"));
            small.set_width ((w - 32) * Pango.SCALE);
            small.set_ellipsize (Pango.EllipsizeMode.END);
            small.set_text (_("Normal text should be easy to read on this background."), -1);
            int sw, sh;
            small.get_pixel_size (out sw, out sh);
            double top = (h - lh - sh - 4) / 2.0;
            cr.set_source_rgba (foreground.r, foreground.g, foreground.b, foreground.a);
            cr.move_to (16, top);
            Pango.cairo_show_layout (cr, layout);
            cr.move_to (16, top + lh + 4);
            Pango.cairo_show_layout (cr, small);
        }
    }
}
