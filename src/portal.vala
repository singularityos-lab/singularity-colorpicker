namespace Singularity.Apps.ColorPicker {

    public errordomain PickError {
        UNSUPPORTED,
        CANCELLED,
        FAILED
    }

    namespace Portal {
        private const string BUS_NAME = "org.freedesktop.portal.Desktop";
        private const string OBJECT_PATH = "/org/freedesktop/portal/desktop";

        public Color parse_response (uint32 code, Variant results) throws PickError {
            if (code == 1) throw new PickError.CANCELLED ("cancelled");
            if (code != 0) throw new PickError.UNSUPPORTED (_("The desktop portal could not pick a color on this system."));
            var color = results.lookup_value ("color", new VariantType ("(ddd)"));
            if (color == null) throw new PickError.FAILED (_("The desktop portal did not return a color."));
            double r, g, b;
            color.get ("(ddd)", out r, out g, out b);
            if (r.is_nan () || g.is_nan () || b.is_nan ()) throw new PickError.FAILED (_("The desktop portal returned an invalid color."));
            return new Color (r, g, b);
        }

        public PickError map_dbus_error (Error e) {
            if (e is DBusError.SERVICE_UNKNOWN || e is DBusError.NAME_HAS_NO_OWNER || e is DBusError.UNKNOWN_METHOD
                || e is DBusError.UNKNOWN_INTERFACE || e is DBusError.UNKNOWN_OBJECT || e is DBusError.NOT_SUPPORTED) {
                return new PickError.UNSUPPORTED (_("No screen color picker is available: the desktop portal on this system does not support picking colors."));
            }
            return new PickError.FAILED (e.message);
        }

        public string request_path (string unique_name, string token) {
            string sender = unique_name.has_prefix (":") ? unique_name.substring (1) : unique_name;
            return "%s/request/%s/%s".printf (OBJECT_PATH, sender.replace (".", "_"), token);
        }

        private class Request : Object {
            public uint32 code = 2;
            public Variant results = new Variant.array (new VariantType ("{sv}"), {});
            public bool done;
            public SourceFunc? resume;

            public void on_response (DBusConnection conn, string? sender, string path, string iface, string name, Variant parameters) {
                if (done) return;
                done = true;
                parameters.get ("(u@a{sv})", out code, out results);
                if (resume != null) Idle.add ((owned) resume);
            }
        }

        public async Color pick (string parent_window = "") throws PickError {
            DBusConnection bus;
            try {
                bus = yield Bus.get (BusType.SESSION);
            } catch (Error e) {
                throw map_dbus_error (e);
            }
            string token = "sinty_colorpicker_%u".printf (Random.next_int ());
            string handle = request_path (bus.unique_name, token);
            var req = new Request ();
            uint sub = bus.signal_subscribe (BUS_NAME, "org.freedesktop.portal.Request", "Response", handle, null, DBusSignalFlags.NONE, req.on_response);
            try {
                var opts = new VariantBuilder (new VariantType ("a{sv}"));
                opts.add ("{sv}", "handle_token", new Variant.string (token));
                var reply = yield bus.call (BUS_NAME, OBJECT_PATH, "org.freedesktop.portal.Screenshot", "PickColor",
                    new Variant ("(s@a{sv})", parent_window, opts.end ()), new VariantType ("(o)"), DBusCallFlags.NONE, -1, null);
                string returned;
                reply.get ("(o)", out returned);
                if (returned != handle) {
                    bus.signal_unsubscribe (sub);
                    sub = bus.signal_subscribe (BUS_NAME, "org.freedesktop.portal.Request", "Response", returned, null, DBusSignalFlags.NONE, req.on_response);
                }
                if (!req.done) {
                    req.resume = pick.callback;
                    yield;
                }
            } catch (Error e) {
                throw map_dbus_error (e);
            } finally {
                bus.signal_unsubscribe (sub);
            }
            return parse_response (req.code, req.results);
        }
    }
}
