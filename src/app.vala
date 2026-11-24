using Gtk;

namespace Singularity.Apps.ColorPicker {

    public class ColorPickerApp : Singularity.Application, Singularity.Migration.Migratable, Singularity.Startup.Bootable {
        public History history;
        public GLib.Settings settings;
        private FileMonitor? history_monitor;
        private bool pick_on_activate;

        public ColorPickerApp () {
            Object (application_id: "dev.sinty.colorpicker", flags: ApplicationFlags.HANDLES_OPEN);
            add_main_option ("pick", 0, OptionFlags.NONE, OptionArg.NONE, _("Pick a color from the screen"), null);
            new ColorSearchProvider (this).export (this);
        }

        private uint colors_bus_id = 0;
        private uint color_collab_id = 0;

        public override bool dbus_register (DBusConnection connection, string object_path) throws Error {
            if (!base.dbus_register (connection, object_path)) return false;
            colors_bus_id = connection.register_object ("/dev/sinty/colorpicker/Colors", new ColorsBus ());
            color_collab_id = connection.register_object ("/dev/sinty/colorpicker/Collab", new ColorCollabBus (this));
            return true;
        }

        public override void dbus_unregister (DBusConnection connection, string object_path) {
            if (colors_bus_id != 0) connection.unregister_object (colors_bus_id);
            if (color_collab_id != 0) connection.unregister_object (color_collab_id);
            color_collab_id = 0;
            colors_bus_id = 0;
            base.dbus_unregister (connection, object_path);
        }

        protected override int handle_local_options (VariantDict options) {
            if (!options.contains ("pick")) return -1;
            if (pick_in_shell ()) return 0;
            try {
                register (null);
            } catch (Error e) {
                return 1;
            }
            if (get_is_remote ()) {
                activate_action ("pick-screen", null);
                return 0;
            }
            pick_on_activate = true;
            return -1;
        }

        private bool pick_in_shell () {
            try {
                var bus = Bus.get_sync (BusType.SESSION);
                bus.call_sync ("dev.sinty.desktop", "/dev/sinty/colorpicker/Picker", "dev.sinty.colorpicker.Picker", "Pick",
                    null, null, DBusCallFlags.NO_AUTO_START, 2000);
                return true;
            } catch (Error e) {
                return false;
            }
        }

        protected override void startup () {
            base.startup ();
            history = new History ();
            ColorPickerIntents.install (this);
            DirUtils.create_with_parents (Path.get_dirname (history.path), 0700);
            try {
                history_monitor = File.new_for_path (history.path).monitor_file (FileMonitorFlags.NONE);
                history_monitor.changed.connect ((f, other, ev) => {
                    if (ev == FileMonitorEvent.CHANGES_DONE_HINT || ev == FileMonitorEvent.CREATED || ev == FileMonitorEvent.DELETED)
                        history.reload ();
                });
            } catch (Error e) {
                warning ("colorpicker: %s", e.message);
            }
            settings = new GLib.Settings ("dev.sinty.colorpicker");
            var provider = new CssProvider ();
            provider.load_from_string (CSS);
            StyleContext.add_provider_for_display (Gdk.Display.get_default (), provider, STYLE_PROVIDER_PRIORITY_USER + 1);
            var menu = new GLib.Menu ();
            var file = new GLib.Menu ();
            var f1 = new GLib.Menu ();
            f1.append (_("Pick a Color"), "win.pick");
            f1.append (_("Enter a Color…"), "win.enter");
            file.append_section (null, f1);
            var f_image = new GLib.Menu ();
            f_image.append (_("Open an Image…"), "win.open-image");
            f_image.append (_("Paste an Image"), "win.paste-image");
            f_image.append (_("Close Image"), "win.close-image");
            file.append_section (null, f_image);
            var f_export = new GLib.Menu ();
            f_export.append (_("Export Palette…"), "win.export-palette");
            file.append_section (null, f_export);
            var f2 = new GLib.Menu ();
            f2.append (_("Close Window"), "win.close");
            f2.append (_("Quit"), "app.quit");
            file.append_section (null, f2);
            menu.append_submenu (_("File"), file);
            var edit = new GLib.Menu ();
            var e1 = new GLib.Menu ();
            e1.append (_("Copy Hex"), "win.copy-hex");
            e1.append (_("Paste Color"), "win.paste");
            edit.append_section (null, e1);
            var e2 = new GLib.Menu ();
            e2.append (_("Add to History"), "win.remember");
            e2.append (_("Save Palette to History"), "win.palette-to-history");
            e2.append (_("Clear History…"), "win.clear-history");
            edit.append_section (null, e2);
            var e3 = new GLib.Menu ();
            e3.append (_("Apply Contrast Fix"), "win.apply-fix");
            e3.append (_("Copy Suggested Color"), "win.copy-fix");
            edit.append_section (null, e3);
            var e4 = new GLib.Menu ();
            e4.append (_("Settings"), "app.settings");
            edit.append_section (null, e4);
            menu.append_submenu (_("Edit"), edit);
            var view = new GLib.Menu ();
            var v1 = new GLib.Menu ();
            v1.append (_("Color"), "win.show-color");
            v1.append (_("Image"), "win.show-image");
            view.append_section (null, v1);
            var v2 = new GLib.Menu ();
            v2.append (_("Uppercase Hex"), "win.uppercase-hex");
            v2.append (_("Swap Contrast Colors"), "win.swap-contrast");
            view.append_section (null, v2);
            var simulate = new GLib.Menu ();
            foreach (var d in Deficiency.all ()) simulate.append (d.label (), "win.vision::" + d.id ());
            view.append_submenu (_("Simulate Color Vision"), simulate);
            menu.append_submenu (_("View"), view);
            set_menubar (menu);
            var quit = new SimpleAction ("quit", null);
            quit.activate.connect (() => {
                foreach (var w in get_windows ().copy ()) w.close ();
            });
            add_action (quit);
            var pick_screen = new SimpleAction ("pick-screen", null);
            pick_screen.activate.connect (() => {
                show_window ();
                var w = get_active_window () as ColorPickerWindow;
                if (w != null) w.pick_color ();
            });
            add_action (pick_screen);
            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.colorpicker");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            add_action (settings_action);
            set_accels_for_action ("app.settings", { "<Control>comma" });
            set_accels_for_action ("win.open-image", { "<Control>o" });
            set_accels_for_action ("win.paste-image", { "<Control><Alt>v" });
            set_accels_for_action ("win.close-image", { "<Control><Shift>w" });
            set_accels_for_action ("win.export-palette", { "<Control>e" });
            set_accels_for_action ("win.palette-to-history", { "<Control><Shift>d" });
            set_accels_for_action ("win.apply-fix", { "<Control>j" });
            set_accels_for_action ("win.copy-fix", { "<Control><Shift>j" });
            set_accels_for_action ("win.show-color", { "<Control>1" });
            set_accels_for_action ("win.show-image", { "<Control>2" });
            var kinds = Deficiency.all ();
            for (int i = 0; i < kinds.length; i++) {
                set_accels_for_action ("win.vision::" + kinds[i].id (), { "<Control><Alt>%d".printf (i) });
            }
            set_accels_for_action ("app.quit", { "<Control>q" });
            set_accels_for_action ("win.close", { "<Control>w" });
            set_accels_for_action ("win.pick", { "<Control>p" });
            set_accels_for_action ("win.enter", { "<Control>l" });
            set_accels_for_action ("win.copy-hex", { "<Control><Shift>c" });
            set_accels_for_action ("win.paste", { "<Control><Shift>v" });
            set_accels_for_action ("win.remember", { "<Control>d" });
            set_accels_for_action ("win.swap-contrast", { "<Control><Shift>x" });
        }

        public Singularity.Startup.Plan build_plan (Singularity.Startup.Request request) {
            var plan = new Singularity.Startup.Plan ();
            plan.version = "colorpicker-1";
            if (request.kind == Singularity.Startup.RequestKind.SERVICE) {
                plan.main ("ready", Singularity.Startup.Category.PREPARE, (c) => {})
                    .reaches (Singularity.Startup.Milestone.SHELL_READY)
                    .reaches (Singularity.Startup.Milestone.CONTENT_READY)
                    .reaches (Singularity.Startup.Milestone.INTERACTIVE);
                return plan;
            }
            var window = plan.main ("window", Singularity.Startup.Category.SHELL, (c) => {
                show_window ();
                c.window = get_active_window ();
            }).reaches (Singularity.Startup.Milestone.SHELL_READY);
            if (request.kind == Singularity.Startup.RequestKind.OPEN) {
                var files = request.files ();
                plan.main ("open-file", Singularity.Startup.Category.CONTENT, (c) => open_files (files))
                    .depends_on ("window")
                    .reaches (Singularity.Startup.Milestone.CONTENT_READY)
                    .reaches (Singularity.Startup.Milestone.INTERACTIVE);
            } else {
                window.reaches (Singularity.Startup.Milestone.CONTENT_READY).reaches (Singularity.Startup.Milestone.INTERACTIVE);
            }
            return plan;
        }

        public void handle_request (Singularity.Startup.Request request) {
            if (request.kind == Singularity.Startup.RequestKind.OPEN) open_files (request.files ());
            else show_window ();
        }

        internal void show_window () {
            var w = get_active_window ();
            if (w == null) w = new ColorPickerWindow (this);
            w.present ();
            if (pick_on_activate) {
                pick_on_activate = false;
                ((ColorPickerWindow) w).pick_color ();
            }
        }

        private void open_files (File[] files) {
            show_window ();
            var w = get_active_window () as ColorPickerWindow;
            if (w != null && files.length > 0) w.open_file (files[0]);
        }

        private const string[] MOVED_KEYS = { "vision", "palette-size", "contrast-level", "contrast-large-text", "contrast-adjust" };

        public Variant save_model () {
            var d = new VariantDict ();
            foreach (unowned string key in MOVED_KEYS) d.insert_value (key, settings.get_value (key));
            return d.end ();
        }

        public async void restore_model (Variant model) throws Error {
            var d = new VariantDict (model);
            foreach (unowned string key in MOVED_KEYS) {
                var v = d.lookup_value (key, null);
                if (v != null && v.is_of_type (settings.get_value (key).get_type ()) && !v.equal (settings.get_value (key))) settings.set_value (key, v);
            }
        }

        public string window_kind (Gtk.Window w) {
            return (w is ColorPickerWindow) ? "colorpicker" : "";
        }

        public Variant save_window (Gtk.Window w) {
            return ((ColorPickerWindow) w).save_migration ();
        }

        public string[] files () {
            string[] list = {};
            foreach (var w in get_windows ()) {
                string? path = (w is ColorPickerWindow) ? ((ColorPickerWindow) w).image_path () : null;
                if (path != null) list += Singularity.Migration.portable_path (File.new_for_path (path));
            }
            return list;
        }

        public async Gtk.Window? rebuild_window (string kind, Variant data) throws Error {
            if (kind != "colorpicker") return null;
            foreach (var old in get_windows ().copy ()) {
                if (old is ColorPickerWindow) old.destroy ();
            }
            var w = new ColorPickerWindow (this, data);
            yield w.restore_migration (data);
            return w;
        }

        private const string CSS = """
.colorpicker-swatch-hex {
    font-size: 22px;
    font-weight: 800;
    font-feature-settings: "tnum";
    color: white;
}

.colorpicker-swatch-name {
    font-size: 13px;
    color: alpha(white, 0.8);
}

.colorpicker-swatch-hex.colorpicker-on-light {
    color: #1a1a1a;
}

.colorpicker-swatch-name.colorpicker-on-light {
    color: alpha(#1a1a1a, 0.75);
}

.colorpicker-chip {
    padding: 2px;
    border-radius: 12px;
    background: transparent;
    box-shadow: none;
    min-width: 0;
    min-height: 0;
}

.colorpicker-chip:hover,
.colorpicker-chip:focus-visible {
    box-shadow: 0 0 0 2px alpha(@accent_bg_color, 0.6);
}

.colorpicker-mono {
    font-family: monospace;
}

.colorpicker-ratio {
    font-size: 28px;
    font-weight: 800;
    font-feature-settings: "tnum";
}

.colorpicker-verdict {
    font-weight: 700;
    padding: 2px 12px;
    border-radius: 99px;
}

.colorpicker-pass {
    color: #1c7a3e;
    background-color: alpha(#2ec27e, 0.18);
}

.colorpicker-fail {
    color: #b3261e;
    background-color: alpha(#e01b24, 0.15);
}

.colorpicker-wheel:focus-visible {
    outline: none;
}

.colorpicker-image {
    border-radius: 12px;
}

.colorpicker-toast {
    padding: 8px 16px;
    border-radius: 18px;
    background-color: alpha(black, 0.7);
    color: white;
}
""";
    }

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            locale_dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain ("singularity-colorpicker", locale_dir);
        Intl.bind_textdomain_codeset ("singularity-colorpicker", "UTF-8");
        Intl.textdomain ("singularity-colorpicker");
        return new ColorPickerApp ().run (args);
    }
}
