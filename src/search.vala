namespace Singularity.Apps.ColorPicker {

    public class ColorSearchProvider : Singularity.SearchProviderService {
        private ColorPickerApp app;

        public ColorSearchProvider (ColorPickerApp app) {
            this.app = app;
        }

        public static Color? parse_query (string[] terms) {
            string text = string.joinv (" ", terms).strip ();
            if (text.has_prefix ("#")) return Color.from_hex (text);
            if (!text.contains ("(") || !text.has_suffix (")")) return null;
            return Parser.parse (text);
        }

        public override async string[] get_initial_results (string[] terms, Cancellable? cancellable) throws Error {
            var c = parse_query (terms);
            if (c == null) return {};
            return { c.to_hex (c.a < 1.0) };
        }

        public override async Singularity.SearchResultMeta[] get_result_metas (string[] ids, Cancellable? cancellable) throws Error {
            Singularity.SearchResultMeta[] metas = {};
            foreach (var id in ids) {
                var c = Color.from_hex (id);
                if (c == null) continue;
                var meta = new Singularity.SearchResultMeta (id, Formatter.format (c, Format.HEX));
                meta.description = "%s · %s · %s".printf (Formatter.format (c, Format.RGB), Formatter.format (c, Format.HSL),
                    NamedColors.name_of (c));
                meta.preview_color = c.to_hex (c.a < 1.0);
                meta.icon = new ThemedIcon ("dev.sinty.colorpicker");
                foreach (var f in extra_formats ()) meta.add_action (f.id (), _("Copy %s").printf (f.label ()), "edit-copy-symbolic");
                metas += meta;
            }
            return metas;
        }

        public override async Singularity.SearchActivationReply? activate_result (string id, string[] terms, uint32 timestamp) throws Error {
            return copy (id, copy_format ());
        }

        public override async Singularity.SearchActivationReply? activate_action (string id, string action_id, string[] terms, uint32 timestamp) throws Error {
            return copy (id, Format.from_id (action_id));
        }

        public override void launch_search (string[] terms, uint32 timestamp) {
            var c = parse_query (terms);
            app.activate ();
            var w = app.get_active_window () as ColorPickerWindow;
            if (w != null && c != null) w.show_color (c);
        }

        private Singularity.SearchActivationReply? copy (string id, Format f) {
            var c = Color.from_hex (id);
            if (c == null) return null;
            app.history.add (c);
            return Singularity.SearchActivationReply.copy (Formatter.format (c, f));
        }

        private Format copy_format () {
            return Format.from_id (app.settings.get_string ("copy-format"));
        }

        private Format[] extra_formats () {
            Format[] r = {};
            var preferred = copy_format ();
            foreach (var f in new Format[] { Format.HEX, Format.RGB, Format.HSL, Format.OKLCH }) {
                if (f != preferred && r.length < 3) r += f;
            }
            return r;
        }
    }
}
