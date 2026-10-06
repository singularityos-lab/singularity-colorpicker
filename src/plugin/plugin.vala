using Gtk;

[ModuleInit]
public void peas_register_types (TypeModule module) {
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type (typeof (Singularity.Plugin), typeof (Singularity.Apps.ColorPicker.ColorPickerPlugin));
}

namespace Singularity.Apps.ColorPicker {

    [DBus (name = "dev.sinty.colorpicker.Picker")]
    public class ShellPicker : Object {
        private weak ColorPickerPlugin plugin;

        public ShellPicker (ColorPickerPlugin plugin) {
            this.plugin = plugin;
        }

        public void pick () throws Error {
            plugin.pick ();
        }
    }

    public class ColorPickerPlugin : Object, Singularity.Plugin {
        public const string APP_ID = "dev.sinty.colorpicker";
        private Singularity.PluginContext context;
        private Singularity.QuickTile tile;
        private RecentColorsProvider provider;
        private Button? panel_button;
        private GLib.Settings? settings;
        private History history;
        private FileMonitor? monitor;
        private DBusConnection? bus;
        private uint registration;
        private bool picking;

        public void activate (Singularity.PluginContext context) {
            this.context = context;
            bind_domain ();
            var source = SettingsSchemaSource.get_default ();
            if (source != null && source.lookup (APP_ID, true) != null) settings = new GLib.Settings (APP_ID);
            history = new History ();
            DirUtils.create_with_parents (Path.get_dirname (history.path), 0700);
            try {
                monitor = File.new_for_path (history.path).monitor_file (FileMonitorFlags.NONE);
                monitor.changed.connect ((f, other, ev) => {
                    if (ev == FileMonitorEvent.CHANGES_DONE_HINT || ev == FileMonitorEvent.CREATED || ev == FileMonitorEvent.DELETED)
                        history.reload ();
                });
            } catch (Error e) {
                warning ("colorpicker plugin: %s", e.message);
            }

            tile = new Singularity.QuickTile ("dev.sinty.colorpicker.pick", _("Pick a Color"), "color-select-symbolic");
            tile.toggleable = false;
            tile.detail_title = _("Recent Colors");
            tile.clicked.connect (() => pick ());
            tile.set_detail_page (() => new RecentColors (this, 2, true));
            history.changed.connect (update_tile);
            update_tile ();
            context.add_quick_tile (tile);

            provider = new RecentColorsProvider (this);
            context.add_overview_widget (provider);

            if (settings != null) {
                settings.changed["panel-button"].connect (update_panel_button);
                settings.changed["copy-format"].connect (update_tile);
            }
            update_panel_button ();

            bus = GLib.Application.get_default () != null ? GLib.Application.get_default ().get_dbus_connection () : null;
            if (bus != null) {
                try {
                    registration = bus.register_object ("/dev/sinty/colorpicker/Picker", new ShellPicker (this));
                } catch (IOError e) {
                    warning ("colorpicker plugin: %s", e.message);
                }
            }
        }

        public void deactivate () {
            if (bus != null && registration != 0) bus.unregister_object (registration);
            registration = 0;
            context.remove_quick_tile (tile);
            context.remove_overview_widget (provider);
            if (panel_button != null) context.remove_panel_widget (panel_button);
            panel_button = null;
            if (monitor != null) monitor.cancel ();
        }

        public Gtk.Widget? get_settings_widget () {
            if (settings == null) return null;
            var list = new ListBox ();
            list.selection_mode = SelectionMode.NONE;
            list.add_css_class ("preferences-list");
            var row = new Singularity.Widgets.SwitchRow (_("Button in the Top Bar"), _("Pick a color from the top bar of the desktop"));
            settings.bind ("panel-button", row.switch_btn, "active", SettingsBindFlags.DEFAULT);
            list.append (row);
            return list;
        }

        public History get_history () {
            return history;
        }

        public string format (Color c) {
            var f = settings != null ? Format.from_id (settings.get_string ("copy-format")) : Format.HEX;
            return Formatter.format (c, f);
        }

        public void copy (Color c) {
            string text = format (c);
            var display = Gdk.Display.get_default ();
            if (display != null) display.get_clipboard ().set_text (text);
            history.add (c);
        }

        public void pick () {
            if (picking) return;
            picking = true;
            tile.active = true;
            Portal.pick.begin ("", (o, res) => {
                picking = false;
                tile.active = false;
                try {
                    var c = Portal.pick.end (res);
                    copy (c);
                    send_notification (_("Color Copied"), format (c));
                } catch (PickError e) {
                    if (!(e is PickError.CANCELLED)) send_notification (_("Could Not Pick a Color"), e.message);
                }
            });
        }

        private void send_notification (string title, string body) {
            var app = GLib.Application.get_default ();
            if (app == null) return;
            var n = new GLib.Notification (title);
            n.set_body (body);
            n.set_icon (new ThemedIcon (APP_ID));
            app.send_notification ("colorpicker-pick", n);
        }

        public void open_app () {
            var info = new DesktopAppInfo (APP_ID + ".desktop");
            if (info == null) return;
            try {
                info.launch (null, Gdk.Display.get_default ().get_app_launch_context ());
            } catch (Error e) {
                warning ("colorpicker plugin: %s", e.message);
            }
        }

        private void update_tile () {
            tile.subtitle = history.items.size > 0 ? format (history.items[0]) : "";
        }

        private void update_panel_button () {
            bool wanted = settings != null && settings.get_boolean ("panel-button");
            if (wanted && panel_button == null) {
                panel_button = new Button.from_icon_name ("color-select-symbolic");
                panel_button.add_css_class ("flat");
                panel_button.add_css_class ("panel-button");
                panel_button.tooltip_text = _("Pick a Color");
                panel_button.clicked.connect (() => pick ());
                context.add_panel_widget (panel_button, Align.END);
            } else if (!wanted && panel_button != null) {
                context.remove_panel_widget (panel_button);
                panel_button = null;
            }
        }

        private static void bind_domain () {
            try {
                string exe = FileUtils.read_link ("/proc/self/exe");
                string dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
                Intl.bindtextdomain ("singularity-colorpicker", dir);
                Intl.bind_textdomain_codeset ("singularity-colorpicker", "UTF-8");
            } catch (Error e) {
            }
        }
    }

    public class RecentColorsProvider : Object, Singularity.OverviewWidgetProvider {
        private weak ColorPickerPlugin plugin;
        private Singularity.WidgetSize[] sizes = { Singularity.WidgetSize (2, 1), Singularity.WidgetSize (2, 2) };

        public RecentColorsProvider (ColorPickerPlugin plugin) {
            this.plugin = plugin;
        }

        public string id { get { return "colorpicker.recent"; } }
        public string provider_id { get { return ColorPickerPlugin.APP_ID; } }
        public string display_name { get { return _("Recent Colors"); } }
        public string icon_name { get { return "color-select-symbolic"; } }
        public Singularity.WidgetSize[] supported_sizes { get { return sizes; } }

        public Gtk.Widget create_instance (string instance_id, Singularity.WidgetSize size, Variant? config) {
            return new RecentColors (plugin, size.h, false);
        }
    }

    public class RecentColors : Box {
        private weak ColorPickerPlugin plugin;
        private FlowBox grid;
        private Label empty;
        private Label copied;
        private uint copied_id;
        private int rows;
        private ulong changed_id;

        public RecentColors (ColorPickerPlugin plugin, int rows, bool page) {
            Object (orientation: Orientation.VERTICAL, spacing: 6);
            this.plugin = plugin;
            this.rows = rows;
            hexpand = true;
            vexpand = true;
            if (page) {
                margin_start = 12;
                margin_end = 12;
            } else {
                add_css_class ("overview-widget-card");
                overflow = Overflow.HIDDEN;
                var title = new Label (_("Recent Colors"));
                title.add_css_class ("title-4");
                title.halign = Align.START;
                title.margin_start = 12;
                title.margin_top = 8;
                append (title);
            }

            grid = new FlowBox ();
            grid.selection_mode = SelectionMode.NONE;
            grid.homogeneous = true;
            grid.min_children_per_line = 6;
            grid.max_children_per_line = 6;
            grid.column_spacing = 6;
            grid.row_spacing = 6;
            grid.margin_start = 12;
            grid.margin_end = 12;
            grid.valign = Align.CENTER;
            grid.vexpand = true;
            append (grid);

            empty = new Label (_("Colors you pick appear here"));
            empty.add_css_class ("dim-label");
            empty.wrap = true;
            empty.justify = Justification.CENTER;
            empty.vexpand = true;
            append (empty);

            copied = new Label ("");
            copied.add_css_class ("caption");
            copied.add_css_class ("dim-label");
            copied.halign = Align.START;
            copied.margin_start = 12;
            copied.margin_bottom = 8;
            append (copied);

            if (page) {
                var open = new Button.with_label (_("Open Color Picker"));
                open.halign = Align.CENTER;
                open.margin_top = 6;
                open.clicked.connect (() => plugin.open_app ());
                append (open);
            }

            changed_id = plugin.get_history ().changed.connect (fill);
            destroy.connect (() => {
                if (changed_id != 0) plugin.get_history ().disconnect (changed_id);
                changed_id = 0;
                if (copied_id != 0) Source.remove (copied_id);
                copied_id = 0;
            });
            fill ();
        }

        private void fill () {
            Widget? child;
            while ((child = grid.get_first_child ()) != null) grid.remove (child);
            var items = plugin.get_history ().items;
            int limit = int.min (items.size, rows * 6);
            for (int i = 0; i < limit; i++) {
                var c = items[i];
                var swatch = new Swatch (30, 30, 8);
                swatch.color = c;
                var button = new Button ();
                button.child = swatch;
                button.add_css_class ("flat");
                button.tooltip_text = plugin.format (c);
                button.clicked.connect (() => {
                    plugin.copy (c);
                    show_copied (plugin.format (c));
                });
                grid.append (button);
            }
            grid.visible = limit > 0;
            empty.visible = limit == 0;
            if (copied_id == 0) copied.label = limit > 0 ? _("Click a color to copy it") : "";
        }

        private void show_copied (string text) {
            copied.label = _("Copied %s").printf (text);
            if (copied_id != 0) Source.remove (copied_id);
            copied_id = Timeout.add_seconds (3, () => {
                copied_id = 0;
                copied.label = _("Click a color to copy it");
                return Source.REMOVE;
            });
        }
    }
}
