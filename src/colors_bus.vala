namespace Singularity.Apps.ColorPicker {

    [DBus (name = "dev.sinty.ColorPicker1")]
    public class ColorsBus : Object {
        public string[] recent_colors (int max) throws Error {
            string[] result = {};
            var history = new History ();
            foreach (var c in history.items) {
                if (result.length >= int.max (1, max)) break;
                result += c.to_hex (false);
            }
            return result;
        }
    }

    [DBus (name = "dev.sinty.Collab.Color1")]
    public class ColorCollabBus : Object {
        private unowned ColorPickerApp app;

        public ColorCollabBus (ColorPickerApp app) {
            this.app = app;
        }

        public void receive (string title, string payload, string from) throws Error {
            var c = Color.from_hex (payload.strip ());
            if (c == null) throw new IOError.INVALID_DATA ("not a color");
            app.history.add (c);
            app.activate ();
            var w = app.get_active_window () as ColorPickerWindow;
            if (w != null) w.show_toast (_("%s sent you %s").printf (from, c.to_hex (false)));
        }

        public void join (string session, string title, string snapshot, string role, string from) throws Error {
            throw new IOError.NOT_SUPPORTED ("colors are not shared in a session");
        }
    }
}
