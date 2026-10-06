using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.ColorPicker {

    public class ColorPickerWindow : Singularity.Widgets.Window {
        private ColorPickerApp app;
        private History history;
        private Color current = new Color.rgb8 (53, 132, 228);
        private Color contrast_bg = new Color (1, 1, 1);
        private Harmony harmony = Harmony.SHADES;
        private bool upper_hex;
        private bool picking;

        private Stack stack;
        private Swatch big_swatch;
        private Label swatch_hex;
        private Label swatch_name;
        private ColorWheel wheel;
        private Scale brightness_scale;
        private Scale alpha_scale;
        private bool syncing;
        private Gee.HashMap<Format, ActionRow> format_rows = new Gee.HashMap<Format, ActionRow> ();
        private ActionRow name_row;
        private Swatch name_swatch;
        private Box palette_box;
        private ContrastPreview preview;
        private Label ratio_label;
        private Label ratio_caption;
        private ColorPickerButton bg_button;
        private Gee.ArrayList<Label> verdicts = new Gee.ArrayList<Label> ();
        private double[] verdict_needs = { Contrast.AA, Contrast.AAA, Contrast.AA_LARGE, Contrast.AAA_LARGE };
        private FlowBox history_box;
        private Label history_empty;
        private Button clear_button;
        private Button pick_bubble;
        private Button copy_bubble;
        private Overlay overlay;
        private Label? toast;
        private uint toast_id;
        private uint save_id;
        private KeyFile state = new KeyFile ();
        private string state_path;
        private GLib.Settings settings;
        private Stack view_stack;
        private BubbleSwitcher switcher;
        private Button open_bubble;
        private Stack image_stack;
        private LoadedImage? image;
        private uint load_serial;
        private Deficiency vision = Deficiency.NONE;
        private PreferencesGroup image_group;
        private Picture picture;
        private SelectionRow vision_row;
        private PreferencesGroup image_palette_group;
        private SpinRow size_row;
        private FlowBox image_palette_box;
        private Label vision_note;
        private Gee.ArrayList<VisionRow> vision_rows = new Gee.ArrayList<VisionRow> ();
        private SelectionRow level_control;
        private SelectionRow size_control;
        private SelectionRow adjust_control;
        private ListBoxRow compare_row;
        private ContrastPreview before_preview;
        private ContrastPreview after_preview;
        private Label before_label;
        private Label after_label;
        private ActionRow result_row;
        private Swatch result_swatch;
        private Button copy_fix_button;
        private Button apply_fix_button;
        private ContrastSuggestion? suggestion;
        private bool suggestion_for_background;

        private class VisionRow : Object {
            public Deficiency kind;
            public Swatch swatch;
            public Box strip;
            public Label ratio;
        }

        public ColorPickerWindow (ColorPickerApp app) {
            Object (application: app);
            this.app = app;
            history = app.history;
            settings = app.settings;
            vision = Deficiency.from_id (settings.get_string ("vision"));
            set_default_size (1000, 780);
            set_title (_("Color Picker"));
            state_path = Path.build_filename (Environment.get_user_config_dir (), "singularity", "colorpicker.ini");
            bool has_state = load_state ();

            stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;
            stack.add_named (build_welcome (), "welcome");
            stack.add_named (build_views (), "main");
            overlay = new Overlay ();
            overlay.child = stack;
            set_content (overlay);

            switcher = new BubbleSwitcher (view_stack);
            add_bubble_widget (switcher);
            open_bubble = add_bubble_icon ("document-open-symbolic", _("Open an Image (Ctrl+O)"), () => open_image ());
            pick_bubble = add_bubble_icon ("color-select-symbolic", _("Pick a Color (Ctrl+P)"), () => pick_color ());
            add_bubble_icon ("document-edit-symbolic", _("Enter a Color (Ctrl+L)"), () => enter_color ());
            copy_bubble = add_bubble_icon ("edit-copy-symbolic", _("Copy Hex (Ctrl+Shift+C)"), () => copy_format (Format.HEX));

            add_actions ();
            history.changed.connect (fill_history);
            close_request.connect (() => {
                save_state ();
                return false;
            });

            setup_drop ();
            settings.changed["palette-size"].connect (() => {
                int n = settings.get_int ("palette-size");
                if ((int) size_row.value != n) size_row.value = n;
            });
            settings.changed["contrast-level"].connect (() => {
                level_control.current_value = settings.get_string ("contrast-level").up ();
                update_fix ();
            });

            apply_color (current, true);
            fill_history ();
            update_view_actions ();
            bool restoring = restore_image ();
            show_page (has_state || restoring || history.items.size > 0 ? "main" : "welcome");
        }

        private void add_actions () {
            action ("pick", () => pick_color ());
            action ("enter", () => enter_color ());
            action ("copy-hex", () => copy_format (Format.HEX));
            action ("paste", () => paste_color ());
            action ("remember", () => {
                history.add (current);
                show_toast (_("Added to history"));
            });
            action ("clear-history", () => confirm_clear ());
            action ("swap-contrast", () => swap_contrast ());
            action ("open-image", () => open_image ());
            action ("paste-image", () => paste_image ());
            action ("close-image", () => close_image ());
            action ("export-palette", () => export_palette_as (PaletteFormat.from_id (settings.get_string ("export-format"))));
            action ("palette-to-history", () => palette_to_history ());
            action ("apply-fix", () => apply_fix ());
            action ("copy-fix", () => copy_fix ());
            action ("show-color", () => show_view ("color"));
            action ("show-image", () => show_view ("image"));
            action ("close", () => close ());
            var vision_action = new SimpleAction.stateful ("vision", VariantType.STRING, new Variant.string (vision.id ()));
            vision_action.activate.connect ((param) => set_vision (Deficiency.from_id (param.get_string ())));
            add_action (vision_action);
            var upper = new SimpleAction.stateful ("uppercase-hex", null, new Variant.boolean (upper_hex));
            upper.activate.connect (() => {
                upper_hex = !upper_hex;
                upper.set_state (new Variant.boolean (upper_hex));
                update_details ();
                fill_image_palette ();
                schedule_save ();
            });
            add_action (upper);
        }

        private void action (string name, owned Callback cb) {
            var a = new SimpleAction (name, null);
            a.activate.connect (() => cb ());
            add_action (a);
        }

        private Widget build_welcome () {
            var wp = new WelcomePage ();
            wp.app_icon_name = "dev.sinty.colorpicker";
            wp.title = _("Color Picker");
            wp.subtitle = _("Pick any color on your screen and get it as Hex, RGB, HSL, OKLCH and more.");
            wp.add_action ("dev.sinty.colorpicker", _("Pick a Color"), _("Click anywhere on the screen to take its color"), () => pick_color ());
            wp.add_action ("input-keyboard", _("Enter a Color"), _("Type a hex code, a CSS color or a color name"), () => enter_color ());
            wp.add_action ("image-x-generic", _("Palette from an Image"), _("Take the dominant colors of a picture"), () => open_image ());
            return wp;
        }

        private Widget build_views () {
            view_stack = new Stack ();
            view_stack.transition_type = StackTransitionType.CROSSFADE;
            view_stack.add_titled (build_main (), "color", _("Color"));
            view_stack.add_titled (build_image_page (), "image", _("Image"));
            string last = settings.get_string ("last-view");
            if (view_stack.get_child_by_name (last) != null) view_stack.visible_child_name = last;
            view_stack.notify["visible-child-name"].connect (() => {
                settings.set_string ("last-view", view_stack.visible_child_name);
                update_view_actions ();
            });
            return view_stack;
        }

        private Widget build_image_page () {
            image_stack = new Stack ();
            image_stack.transition_type = StackTransitionType.CROSSFADE;
            var wp = new WelcomePage ();
            wp.app_icon_name = "dev.sinty.colorpicker";
            wp.title = _("Palette from an Image");
            wp.subtitle = _("Take the dominant colors of a picture, or drop one anywhere in this window.");
            wp.is_section = true;
            var ctrl = Gdk.ModifierType.CONTROL_MASK;
            wp.add_action_with_caption ("image-x-generic", _("Open an Image"), _("Choose a photo, a screenshot or any picture"),
                accelerator_get_label (Gdk.Key.o, ctrl), () => open_image ());
            wp.add_action_with_caption ("edit-paste", _("Paste an Image"), _("Use a picture you copied"),
                accelerator_get_label (Gdk.Key.v, ctrl | Gdk.ModifierType.ALT_MASK), () => paste_image ());
            image_stack.add_named (wp, "empty");
            image_stack.add_named (build_image_loaded (), "loaded");
            return image_stack;
        }

        private Widget build_image_loaded () {
            image_group = new PreferencesGroup ("", "");
            var close = new Button.from_icon_name ("window-close-symbolic");
            close.valign = Align.CENTER;
            close.tooltip_text = _("Close Image");
            close.clicked.connect (() => close_image ());
            image_group.add_header_suffix (close);
            picture = new Picture ();
            picture.content_fit = ContentFit.CONTAIN;
            picture.can_shrink = true;
            picture.height_request = 320;
            picture.overflow = Overflow.HIDDEN;
            picture.add_css_class ("colorpicker-image");
            picture.margin_top = 12;
            picture.margin_bottom = 12;
            picture.margin_start = 12;
            picture.margin_end = 12;
            var picture_row = new ListBoxRow ();
            picture_row.activatable = false;
            picture_row.child = picture;
            image_group.add_row (picture_row);
            string[] labels = {};
            string[] subtitles = {};
            foreach (var d in Deficiency.all ()) {
                labels += d.label ();
                subtitles += d.description ();
            }
            vision_row = new SelectionRow.with_details (_("Simulate Color Vision"), labels, subtitles, null, vision.label ());
            vision_row.subtitle = _("See the image and its palette as people with color blindness do");
            vision_row.selected.connect ((item) => {
                foreach (var d in Deficiency.all ()) {
                    if (d.label () == item) set_vision (d);
                }
            });
            image_group.add_row (vision_row);

            image_palette_group = new PreferencesGroup (_("Palette"), "");
            var to_history = new Button.with_label (_("Save to History"));
            to_history.valign = Align.CENTER;
            to_history.tooltip_text = _("Save to History (Ctrl+Shift+D)");
            to_history.clicked.connect (() => palette_to_history ());
            image_palette_group.add_header_suffix (to_history);
            var export_button = new Button.from_icon_name ("document-save-as-symbolic");
            export_button.valign = Align.CENTER;
            export_button.tooltip_text = _("Export Palette");
            export_button.clicked.connect (() => export_menu (export_button));
            image_palette_group.add_header_suffix (export_button);
            size_row = new SpinRow (_("Colors"), _("How many dominant colors to take from the image"),
                Extract.MIN_COLORS, Extract.MAX_COLORS, 1, settings.get_int ("palette-size"));
            size_row.spin_btn.value_changed.connect (() => {
                int n = (int) size_row.value;
                if (settings.get_int ("palette-size") != n) settings.set_int ("palette-size", n);
                fill_image_palette ();
            });
            image_palette_group.add_row (size_row);
            var inner = new Box (Orientation.VERTICAL, 10);
            inner.margin_top = 12;
            inner.margin_bottom = 12;
            inner.margin_start = 12;
            inner.margin_end = 12;
            image_palette_box = new FlowBox ();
            image_palette_box.selection_mode = SelectionMode.NONE;
            image_palette_box.homogeneous = true;
            image_palette_box.min_children_per_line = 3;
            image_palette_box.max_children_per_line = 12;
            image_palette_box.column_spacing = 10;
            image_palette_box.row_spacing = 12;
            inner.append (image_palette_box);
            vision_note = new Label ("");
            vision_note.add_css_class ("dim-label");
            vision_note.add_css_class ("caption");
            vision_note.wrap = true;
            vision_note.xalign = 0;
            inner.append (vision_note);
            var palette_row = new ListBoxRow ();
            palette_row.activatable = false;
            palette_row.child = inner;
            image_palette_group.add_row (palette_row);

            var column = new Box (Orientation.VERTICAL, 18);
            column.margin_start = 24;
            column.margin_end = 24;
            column.margin_top = 12;
            column.margin_bottom = 32;
            column.append (image_group);
            column.append (image_palette_group);
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.child = column;
            apply_view_edge (scroll);
            return scroll;
        }

        private Widget build_main () {
            var flow = new FlowBox ();
            flow.selection_mode = SelectionMode.NONE;
            flow.min_children_per_line = 1;
            flow.max_children_per_line = 2;
            flow.column_spacing = 24;
            flow.row_spacing = 12;
            flow.homogeneous = false;
            flow.valign = Align.START;
            flow.append (build_editor ());
            flow.append (build_formats ());
            for (var child = flow.get_first_child (); child != null; child = child.get_next_sibling ()) {
                child.focusable = false;
                child.valign = Align.START;
            }

            var column = new Box (Orientation.VERTICAL, 18);
            column.margin_start = 24;
            column.margin_end = 24;
            column.margin_top = 12;
            column.margin_bottom = 32;
            column.append (flow);
            column.append (build_palette ());
            column.append (build_contrast ());
            column.append (build_fix ());
            column.append (build_vision ());
            column.append (build_history ());

            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.child = column;
            apply_view_edge (scroll);
            return scroll;
        }

        private Widget build_editor () {
            var box = new Box (Orientation.VERTICAL, 14);
            box.width_request = 320;

            var swatch_overlay = new Overlay ();
            big_swatch = new Swatch (320, 150, 18);
            big_swatch.hexpand = true;
            swatch_overlay.child = big_swatch;
            var caption = new Box (Orientation.VERTICAL, 0);
            caption.halign = Align.START;
            caption.valign = Align.END;
            caption.margin_start = 16;
            caption.margin_bottom = 12;
            caption.can_target = false;
            swatch_hex = new Label ("");
            swatch_hex.add_css_class ("colorpicker-swatch-hex");
            swatch_hex.xalign = 0;
            swatch_name = new Label ("");
            swatch_name.add_css_class ("colorpicker-swatch-name");
            swatch_name.xalign = 0;
            caption.append (swatch_hex);
            caption.append (swatch_name);
            swatch_overlay.add_overlay (caption);
            box.append (swatch_overlay);

            wheel = new ColorWheel ();
            wheel.halign = Align.CENTER;
            wheel.set_size_request (260, 260);
            wheel.changed.connect (() => {
                if (syncing) return;
                var c = Color.from_hsv (wheel.hue, wheel.saturation, wheel.brightness, current.a);
                apply_color (c, false);
            });
            box.append (wheel);

            var group = new PreferencesGroup ();
            brightness_scale = new Scale.with_range (Orientation.HORIZONTAL, 0, 100, 1);
            brightness_scale.draw_value = false;
            brightness_scale.width_request = 170;
            brightness_scale.value_changed.connect (() => {
                if (syncing) return;
                wheel.set_hsv (wheel.hue, wheel.saturation, brightness_scale.get_value () / 100);
                apply_color (Color.from_hsv (wheel.hue, wheel.saturation, wheel.brightness, current.a), false);
            });
            var brightness_row = new ActionRow (_("Brightness"));
            brightness_row.activatable = false;
            brightness_row.add_suffix (brightness_scale);
            group.add_row (brightness_row);

            alpha_scale = new Scale.with_range (Orientation.HORIZONTAL, 0, 100, 1);
            alpha_scale.draw_value = false;
            alpha_scale.width_request = 170;
            alpha_scale.value_changed.connect (() => {
                if (syncing) return;
                var c = current.copy ();
                c.a = alpha_scale.get_value () / 100;
                apply_color (c, false);
            });
            var alpha_row = new ActionRow (_("Opacity"));
            alpha_row.activatable = false;
            alpha_row.add_suffix (alpha_scale);
            group.add_row (alpha_row);
            box.append (group);
            return box;
        }

        private Widget build_formats () {
            var group = new PreferencesGroup (_("Formats"), _("Click a value to copy it"));
            group.hexpand = true;
            group.width_request = 340;
            foreach (var f in Format.all ()) {
                var fmt = f;
                var row = new ActionRow (fmt.label (), "");
                row.add_suffix (copy_button (() => copy_format (fmt)));
                row.activated.connect (() => copy_format (fmt));
                format_rows[fmt] = row;
                group.add_row (row);
            }
            name_row = new ActionRow (_("Name"), "");
            name_swatch = new Swatch (24, 24, 6);
            name_swatch.valign = Align.CENTER;
            name_swatch.margin_end = 12;
            name_row.add_prefix (name_swatch);
            name_row.add_suffix (copy_button (() => copy_name ()));
            name_row.activated.connect (() => copy_name ());
            group.add_row (name_row);
            return group;
        }

        private delegate void Callback ();

        private Button copy_button (owned Callback cb) {
            var b = new Button.from_icon_name ("edit-copy-symbolic");
            b.add_css_class ("flat");
            b.valign = Align.CENTER;
            b.tooltip_text = _("Copy");
            b.clicked.connect (() => cb ());
            return b;
        }

        private Widget build_palette () {
            var group = new PreferencesGroup (_("Palette"));
            string[] labels = { _("Shades"), _("Tints"), _("Complementary"), _("Analogous"), _("Triadic") };
            var all = Harmony.all ();
            string current_label = labels[0];
            for (int i = 0; i < all.length; i++) {
                if (all[i] == harmony) current_label = labels[i];
            }
            var modes = new SelectionRow (_("Harmony"), labels, current_label);
            modes.selected.connect ((item) => {
                for (int i = 0; i < all.length; i++) {
                    if (labels[i] == item) harmony = all[i];
                }
                fill_palette ();
                schedule_save ();
            });
            group.add_row (modes);
            var export_button = new Button.from_icon_name ("document-save-as-symbolic");
            export_button.valign = Align.CENTER;
            export_button.tooltip_text = _("Export Palette");
            export_button.clicked.connect (() => export_menu (export_button));
            group.add_header_suffix (export_button);
            palette_box = new Box (Orientation.HORIZONTAL, 10);
            palette_box.homogeneous = true;
            palette_box.margin_top = 12;
            palette_box.margin_bottom = 12;
            palette_box.margin_start = 12;
            palette_box.margin_end = 12;
            var row = new ListBoxRow ();
            row.activatable = false;
            row.child = palette_box;
            group.add_row (row);
            return group;
        }

        private Widget build_contrast () {
            var group = new PreferencesGroup (_("Contrast"), _("How readable this color is as text on a background, following WCAG 2"));
            var swap = new Button.from_icon_name ("object-flip-horizontal-symbolic");
            swap.valign = Align.CENTER;
            swap.tooltip_text = _("Swap Text and Background");
            swap.clicked.connect (() => swap_contrast ());
            group.add_header_suffix (swap);

            var top = new Box (Orientation.HORIZONTAL, 16);
            top.margin_top = 12;
            top.margin_bottom = 12;
            top.margin_start = 12;
            top.margin_end = 12;
            preview = new ContrastPreview ();
            top.append (preview);
            var ratio_box = new Box (Orientation.VERTICAL, 2);
            ratio_box.valign = Align.CENTER;
            ratio_box.width_request = 120;
            ratio_label = new Label ("");
            ratio_label.add_css_class ("colorpicker-ratio");
            ratio_caption = new Label (_("Contrast Ratio"));
            ratio_caption.add_css_class ("dim-label");
            ratio_caption.add_css_class ("caption");
            ratio_box.append (ratio_label);
            ratio_box.append (ratio_caption);
            top.append (ratio_box);
            var top_row = new ListBoxRow ();
            top_row.activatable = false;
            top_row.child = top;
            group.add_row (top_row);

            var bg_row = new ActionRow (_("Background"), _("The text uses the current color"));
            bg_button = new ColorPickerButton ();
            bg_button.valign = Align.CENTER;
            bg_button.tooltip_text = _("Choose Background");
            bg_button.color_changed.connect ((rgba) => {
                contrast_bg = new Color (rgba.red, rgba.green, rgba.blue, rgba.alpha);
                update_contrast ();
                schedule_save ();
            });
            bg_row.add_suffix (bg_button);
            var bg_pick = new Button.from_icon_name ("color-select-symbolic");
            bg_pick.add_css_class ("flat");
            bg_pick.valign = Align.CENTER;
            bg_pick.tooltip_text = _("Pick Background from Screen");
            bg_pick.clicked.connect (() => pick_background ());
            bg_row.add_suffix (bg_pick);
            bg_row.activatable = false;
            group.add_row (bg_row);

            string[] titles = { _("Normal Text"), _("Normal Text"), _("Large Text"), _("Large Text") };
            string[] levels = { "AA", "AAA", "AA", "AAA" };
            for (int i = 0; i < 4; i++) {
                var row = new ActionRow ("%s %s".printf (titles[i], levels[i]), _("Needs %s").printf (Contrast.format_ratio (verdict_needs[i])));
                row.activatable = false;
                var verdict = new Label ("");
                verdict.add_css_class ("colorpicker-verdict");
                row.add_suffix (verdict);
                verdicts.add (verdict);
                group.add_row (row);
            }
            return group;
        }

        private Widget build_fix () {
            var group = new PreferencesGroup (_("Contrast Fix"), _("The nearest color that passes, found by changing only its lightness and keeping its hue and chroma"));
            level_control = new SelectionRow (_("Level"), { "AA", "AAA" }, settings.get_string ("contrast-level").up ());
            level_control.selected.connect ((item) => {
                settings.set_string ("contrast-level", item.down ());
                update_fix ();
            });
            group.add_row (level_control);
            string normal_label = _("Normal Text");
            string large_label = _("Large Text");
            size_control = new SelectionRow (_("Text Size"), { normal_label, large_label },
                settings.get_boolean ("contrast-large-text") ? large_label : normal_label);
            size_control.selected.connect ((item) => {
                settings.set_boolean ("contrast-large-text", item == large_label);
                update_fix ();
            });
            group.add_row (size_control);
            string text_label = _("Text Color");
            string background_label = _("Background");
            adjust_control = new SelectionRow (_("Change"), { text_label, background_label },
                settings.get_string ("contrast-adjust") == "background" ? background_label : text_label);
            adjust_control.selected.connect ((item) => {
                settings.set_string ("contrast-adjust", item == background_label ? "background" : "text");
                update_fix ();
            });
            group.add_row (adjust_control);

            var compare = new Box (Orientation.HORIZONTAL, 12);
            compare.homogeneous = true;
            compare.margin_top = 12;
            compare.margin_bottom = 12;
            compare.margin_start = 12;
            compare.margin_end = 12;
            before_preview = new ContrastPreview ();
            before_label = new Label ("");
            compare.append (compare_column (_("Before"), before_preview, before_label));
            after_preview = new ContrastPreview ();
            after_label = new Label ("");
            compare.append (compare_column (_("After"), after_preview, after_label));
            compare_row = new ListBoxRow ();
            compare_row.activatable = false;
            compare_row.child = compare;
            group.add_row (compare_row);

            result_row = new ActionRow ("", "");
            result_row.activatable = false;
            result_swatch = new Swatch (28, 28, 8);
            result_swatch.valign = Align.CENTER;
            result_swatch.margin_end = 12;
            result_row.add_prefix (result_swatch);
            copy_fix_button = copy_button (() => copy_fix ());
            copy_fix_button.tooltip_text = _("Copy Suggested Color (Ctrl+Shift+J)");
            result_row.add_suffix (copy_fix_button);
            apply_fix_button = new Button.with_label (_("Apply"));
            apply_fix_button.add_css_class ("suggested-action");
            apply_fix_button.valign = Align.CENTER;
            apply_fix_button.tooltip_text = _("Apply Contrast Fix (Ctrl+J)");
            apply_fix_button.clicked.connect (() => apply_fix ());
            result_row.add_suffix (apply_fix_button);
            group.add_row (result_row);
            return group;
        }

        private Widget compare_column (string title, ContrastPreview preview, Label caption) {
            var box = new Box (Orientation.VERTICAL, 6);
            var heading = new Label (title);
            heading.add_css_class ("heading");
            heading.xalign = 0;
            box.append (heading);
            preview.set_size_request (-1, 84);
            box.append (preview);
            caption.add_css_class ("caption");
            caption.add_css_class ("colorpicker-mono");
            caption.xalign = 0;
            caption.selectable = true;
            box.append (caption);
            return box;
        }

        private Widget build_vision () {
            var group = new PreferencesGroup (_("Color Vision"), _("How this color, its palette and its contrast look with color blindness"));
            foreach (var d in Deficiency.deficiencies ()) {
                var parts = new VisionRow ();
                parts.kind = d;
                var row = new ActionRow (d.label (), d.description ());
                row.activatable = false;
                parts.strip = new Box (Orientation.HORIZONTAL, 4);
                parts.strip.valign = Align.CENTER;
                parts.strip.margin_end = 12;
                row.add_suffix (parts.strip);
                parts.ratio = new Label ("");
                parts.ratio.add_css_class ("caption");
                parts.ratio.add_css_class ("dim-label");
                parts.ratio.add_css_class ("colorpicker-mono");
                parts.ratio.width_chars = 7;
                parts.ratio.xalign = 1;
                parts.ratio.margin_end = 12;
                row.add_suffix (parts.ratio);
                parts.swatch = new Swatch (40, 40, 10);
                parts.swatch.valign = Align.CENTER;
                row.add_suffix (parts.swatch);
                vision_rows.add (parts);
                group.add_row (row);
            }
            return group;
        }

        private Widget build_history () {
            var group = new PreferencesGroup (_("History"), _("Colors you picked or entered, newest first"));
            clear_button = new Button.with_label (_("Clear"));
            clear_button.valign = Align.CENTER;
            clear_button.clicked.connect (() => confirm_clear ());
            group.add_header_suffix (clear_button);
            var inner = new Box (Orientation.VERTICAL, 0);
            inner.margin_top = 12;
            inner.margin_bottom = 12;
            inner.margin_start = 12;
            inner.margin_end = 12;
            history_box = new FlowBox ();
            history_box.selection_mode = SelectionMode.NONE;
            history_box.max_children_per_line = 50;
            history_box.min_children_per_line = 4;
            history_box.column_spacing = 8;
            history_box.row_spacing = 8;
            history_box.homogeneous = true;
            inner.append (history_box);
            history_empty = new Label (_("Colors you pick appear here."));
            history_empty.add_css_class ("dim-label");
            history_empty.xalign = 0;
            inner.append (history_empty);
            var row = new ListBoxRow ();
            row.activatable = false;
            row.child = inner;
            group.add_row (row);
            return group;
        }

        private Button chip (Color c, int size, Color? shown = null, bool copy_on_click = false) {
            var b = new Button ();
            b.add_css_class ("colorpicker-chip");
            var sw = new Swatch (size, size, 10);
            sw.color = shown ?? c;
            b.child = sw;
            b.tooltip_text = copy_on_click ? _("%s, click to copy").printf (c.to_hex (false, upper_hex))
                : "%s  %s".printf (c.to_hex (false, upper_hex), NamedColors.name_of (c));
            b.update_property (AccessibleProperty.LABEL, c.to_hex (false, upper_hex), -1);
            b.clicked.connect (() => {
                if (copy_on_click) copy_text (c.to_hex (false, upper_hex));
                else apply_color (c, true);
            });
            var right = new GestureClick ();
            right.button = Gdk.BUTTON_SECONDARY;
            right.pressed.connect ((n, x, y) => chip_menu (b, c, x, y));
            b.add_controller (right);
            var press = new GestureLongPress ();
            press.pressed.connect ((x, y) => chip_menu (b, c, x, y));
            b.add_controller (press);
            return b;
        }

        private void chip_menu (Widget anchor, Color c, double x, double y) {
            var menu = new ContextMenu (anchor);
            menu.add_item (_("Use This Color"), "color-select-symbolic", () => apply_color (c, true));
            menu.add_item (_("Copy Hex"), "edit-copy-symbolic", () => copy_text (c.to_hex (false, upper_hex)));
            menu.add_item (_("Use as Contrast Background"), "object-flip-horizontal-symbolic", () => {
                contrast_bg = c.copy ();
                update_contrast ();
                schedule_save ();
            });
            bool in_history = anchor.get_parent () is FlowBoxChild && anchor.get_parent ().get_parent () == history_box;
            if (!in_history) {
                menu.add_item (_("Add to History"), "document-save-symbolic", () => {
                    history.add (c);
                    show_toast (_("Added to history"));
                });
            }
            if (in_history) {
                menu.add_separator ();
                menu.add_item (_("Remove from History"), "user-trash-symbolic", () => history.remove (c), "destructive");
            }
            menu.pointing_to = { (int) x, (int) y, 1, 1 };
            menu.closed.connect (() => Idle.add (() => {
                menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }

        private void show_page (string name) {
            stack.visible_child_name = name;
            update_view_actions ();
        }

        private void show_view (string name) {
            view_stack.visible_child_name = name;
            show_page ("main");
        }

        private bool on_image_view () {
            return stack.visible_child_name == "main" && view_stack.visible_child_name == "image";
        }

        private void set_enabled (string name, bool enabled) {
            var a = lookup_action (name) as SimpleAction;
            if (a != null) a.set_enabled (enabled);
        }

        private void update_view_actions () {
            if (copy_bubble == null) return;
            bool main = stack.visible_child_name == "main";
            bool on_color = main && view_stack.visible_child_name == "color";
            switcher.visible = main;
            copy_bubble.visible = on_color;
            bool has_palette = on_color || (on_image_view () && image != null);
            set_enabled ("export-palette", has_palette);
            set_enabled ("palette-to-history", has_palette);
            set_enabled ("close-image", image != null);
            set_enabled ("apply-fix", suggestion != null && suggestion.found && !suggestion.already_passes);
            set_enabled ("copy-fix", suggestion != null && suggestion.found && !suggestion.already_passes);
        }

        private void apply_color (Color c, bool sync_wheel) {
            current = c.copy ();
            syncing = true;
            if (sync_wheel) {
                double h, s, v;
                current.to_hsv (out h, out s, out v);
                if (s < 1e-6 || v < 1e-6) h = wheel.hue;
                if (v < 1e-6) s = wheel.saturation;
                wheel.set_hsv (h, s, v);
            }
            brightness_scale.set_value (wheel.brightness * 100);
            alpha_scale.set_value (current.a * 100);
            syncing = false;
            update_details ();
            schedule_save ();
        }

        private void update_details () {
            big_swatch.color = current;
            swatch_hex.label = current.to_hex (false, upper_hex);
            double d;
            string name = NamedColors.nearest (current, out d);
            swatch_name.label = name;
            var solid = current.over (new Color (1, 1, 1));
            bool dark = Contrast.ratio (new Color (1, 1, 1), solid) > Contrast.ratio (new Color (0, 0, 0), solid);
            if (dark) {
                swatch_hex.remove_css_class ("colorpicker-on-light");
                swatch_name.remove_css_class ("colorpicker-on-light");
            } else {
                swatch_hex.add_css_class ("colorpicker-on-light");
                swatch_name.add_css_class ("colorpicker-on-light");
            }
            foreach (var f in Format.all ()) format_rows[f].subtitle = Formatter.format (current, f, upper_hex);
            name_row.subtitle = d < 0.5 ? name : _("Close to %s").printf (name);
            name_swatch.color = NamedColors.lookup (name);
            fill_palette ();
            update_contrast ();
        }

        private void fill_palette () {
            Widget? child;
            while ((child = palette_box.get_first_child ()) != null) palette_box.remove (child);
            foreach (var c in Palette.generate (current, harmony)) {
                var cell = new Box (Orientation.VERTICAL, 6);
                var b = chip (c, 56);
                b.halign = Align.CENTER;
                cell.append (b);
                var l = new Label (c.to_hex (false, upper_hex));
                l.add_css_class ("caption");
                l.add_css_class ("colorpicker-mono");
                l.selectable = true;
                cell.append (l);
                palette_box.append (cell);
            }
        }

        private void update_contrast () {
            preview.foreground = current;
            preview.background = contrast_bg;
            var rgba = Gdk.RGBA ();
            rgba.red = (float) contrast_bg.r;
            rgba.green = (float) contrast_bg.g;
            rgba.blue = (float) contrast_bg.b;
            rgba.alpha = (float) contrast_bg.a;
            bg_button.color = rgba;
            double ratio = Contrast.ratio (current, contrast_bg);
            ratio_label.label = Contrast.format_ratio (ratio);
            for (int i = 0; i < verdicts.size; i++) {
                var v = verdicts[i];
                bool pass = ratio >= verdict_needs[i];
                v.label = pass ? _("Pass") : _("Fail");
                if (pass) {
                    v.add_css_class ("colorpicker-pass");
                    v.remove_css_class ("colorpicker-fail");
                } else {
                    v.add_css_class ("colorpicker-fail");
                    v.remove_css_class ("colorpicker-pass");
                }
            }
            update_fix ();
            update_vision ();
        }

        private void update_fix () {
            if (result_row == null) return;
            bool aaa = settings.get_string ("contrast-level") == "aaa";
            bool large = settings.get_boolean ("contrast-large-text");
            suggestion_for_background = settings.get_string ("contrast-adjust") == "background";
            double target = ContrastFix.required (aaa, large);
            string level = "%s %s".printf (aaa ? "AAA" : "AA", large ? _("for large text") : _("for normal text"));
            var solid_bg = contrast_bg.over (new Color (1, 1, 1));
            if (suggestion_for_background) suggestion = ContrastFix.suggest (contrast_bg, current.over (solid_bg), target);
            else suggestion = ContrastFix.suggest (current, contrast_bg, target);
            var s = suggestion;
            bool show_fix = s.found && !s.already_passes;
            compare_row.visible = show_fix;
            result_swatch.visible = show_fix;
            copy_fix_button.visible = show_fix;
            apply_fix_button.visible = show_fix;
            if (s.already_passes) {
                result_row.title = _("Already Passes");
                result_row.subtitle = _("This pair reaches %s, and %s needs %s.").printf (Contrast.format_ratio (s.before), level, Contrast.format_ratio (target));
            } else if (!s.found) {
                result_row.title = _("No Color Found");
                result_row.subtitle = _("No lightness of this color reaches %s here. Change the other color or choose a lower level.").printf (Contrast.format_ratio (target));
            } else {
                var fg_before = suggestion_for_background ? current : s.original;
                var bg_before = suggestion_for_background ? s.original : contrast_bg;
                var fg_after = suggestion_for_background ? current : s.suggested;
                var bg_after = suggestion_for_background ? s.suggested : contrast_bg;
                before_preview.foreground = fg_before;
                before_preview.background = bg_before;
                after_preview.foreground = fg_after;
                after_preview.background = bg_after;
                before_label.label = "%s  %s".printf (Contrast.format_ratio (s.before), s.original.to_hex (false, upper_hex));
                after_label.label = "%s  %s".printf (Contrast.format_ratio (s.after), s.suggested.to_hex (false, upper_hex));
                result_swatch.color = s.suggested;
                result_row.title = _("Suggested %s: %s").printf (suggestion_for_background ? _("background") : _("text color"), s.suggested.to_hex (false, upper_hex));
                string from = Formatter.num (s.lightness_before * 100, 1), to = Formatter.num (s.lightness_after * 100, 1);
                result_row.subtitle = s.chroma_kept
                    ? _("Reaches %s. Lightness %s%% becomes %s%%, hue and chroma stay the same.").printf (level, from, to)
                    : _("Reaches %s. Lightness %s%% becomes %s%%, with less chroma so the color can be shown.").printf (level, from, to);
            }
            update_view_actions ();
        }

        private void apply_fix () {
            var s = suggestion;
            if (s == null || !s.found || s.already_passes) return;
            if (suggestion_for_background) {
                contrast_bg = s.suggested.copy ();
                update_contrast ();
                schedule_save ();
            } else {
                history.add (s.suggested);
                apply_color (s.suggested, true);
            }
            show_toast (_("Contrast fixed: %s").printf (Contrast.format_ratio (s.after)));
        }

        private void copy_fix () {
            var s = suggestion;
            if (s == null || !s.found || s.already_passes) return;
            copy_text (s.suggested.to_hex (false, upper_hex));
        }

        private void update_vision () {
            var palette = Palette.generate (current, harmony);
            var solid_bg = contrast_bg.over (new Color (1, 1, 1));
            var solid_fg = current.over (solid_bg);
            foreach (var row in vision_rows) {
                row.swatch.color = Vision.simulate (current, row.kind);
                Widget? child;
                while ((child = row.strip.get_first_child ()) != null) row.strip.remove (child);
                foreach (var c in palette) {
                    var sw = new Swatch (20, 20, 6);
                    sw.color = Vision.simulate (c, row.kind);
                    sw.tooltip_text = c.to_hex (false, upper_hex);
                    row.strip.append (sw);
                }
                double ratio = Contrast.ratio (Vision.simulate (solid_fg, row.kind), Vision.simulate (solid_bg, row.kind));
                row.ratio.label = Contrast.format_ratio (ratio);
                row.ratio.tooltip_text = _("Contrast with the background as seen with %s").printf (row.kind.label ());
            }
        }

        private void set_vision (Deficiency d) {
            vision = d;
            if (settings.get_string ("vision") != d.id ()) settings.set_string ("vision", d.id ());
            var a = lookup_action ("vision") as SimpleAction;
            if (a != null) a.set_state (new Variant.string (d.id ()));
            if (vision_row.current_value != d.label ()) vision_row.current_value = d.label ();
            update_image_view ();
        }

        private void update_image_view () {
            if (image == null) return;
            picture.paintable = image.texture (vision);
            fill_image_palette ();
        }

        private void fill_image_palette () {
            Widget? child;
            while ((child = image_palette_box.get_first_child ()) != null) image_palette_box.remove (child);
            if (image == null) return;
            var colors = image.palette ((int) size_row.value);
            foreach (var p in colors) {
                var cell = new Box (Orientation.VERTICAL, 4);
                var b = chip (p.color, 56, Vision.simulate (p.color, vision), true);
                b.halign = Align.CENTER;
                cell.append (b);
                var hex_label = new Label (p.color.to_hex (false, upper_hex));
                hex_label.add_css_class ("caption");
                hex_label.add_css_class ("colorpicker-mono");
                hex_label.selectable = true;
                cell.append (hex_label);
                var share = new Label ("%s%%".printf (Formatter.num (p.share * 100, 1)));
                share.add_css_class ("caption");
                share.add_css_class ("dim-label");
                cell.append (share);
                image_palette_box.append (cell);
            }
            for (var c = image_palette_box.get_first_child (); c != null; c = c.get_next_sibling ()) c.focusable = false;
            image_palette_group.description = ngettext ("%d color, largest share first. Click a color to copy it.",
                "%d colors, largest share first. Click a color to copy it.", colors.size).printf (colors.size);
            vision_note.visible = vision != Deficiency.NONE;
            vision_note.label = _("Swatches and image show how they look with %s. The hex codes are the real colors.").printf (vision.label ());
        }

        private void set_image (LoadedImage img) {
            image = img;
            image_group.title = img.title;
            image_group.description = _("%d by %d pixels").printf (img.source_width, img.source_height);
            update_image_view ();
            image_stack.visible_child_name = "loaded";
            show_view ("image");
            update_view_actions ();
        }

        private void close_image () {
            if (image == null) return;
            image = null;
            picture.paintable = null;
            fill_image_palette ();
            image_stack.visible_child_name = "empty";
            settings.set_string ("last-image", "");
            update_view_actions ();
        }

        private string pasted_path () {
            return Path.build_filename (Environment.get_user_cache_dir (), "singularity", "colorpicker", "pasted.png");
        }

        private bool restore_image () {
            string last = settings.get_string ("last-image");
            if (last == "" || !FileUtils.test (last, FileTest.IS_REGULAR)) {
                image_stack.visible_child_name = "empty";
                return false;
            }
            load_image_file (File.new_for_path (last), last == pasted_path () ? _("Pasted Image") : null, true);
            return true;
        }

        private void open_image () {
            var dlg = new FileDialog ();
            dlg.title = _("Open an Image");
            var filter = new FileFilter ();
            filter.name = _("Images");
            filter.add_pixbuf_formats ();
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (filter);
            dlg.filters = filters;
            dlg.default_filter = filter;
            dlg.open.begin (this, null, (o, res) => {
                try {
                    var file = dlg.open.end (res);
                    if (file != null) load_image_file (file, null, false);
                } catch (Error e) {
                    if (!(e is DialogError.DISMISSED) && !(e is DialogError.CANCELLED)) {
                        report_error (_("Could Not Open the Image"), e.message);
                    }
                }
            });
        }

        public void open_file (File file) {
            load_image_file (file, null, false);
        }

        private void load_image_file (File file, string? title, bool quiet) {
            uint serial = ++load_serial;
            LoadedImage.load_file.begin (file, title, null, (o, res) => {
                if (serial != load_serial) return;
                try {
                    var img = LoadedImage.load_file.end (res);
                    set_image (img);
                    if (img.path != null) settings.set_string ("last-image", img.path);
                } catch (Error e) {
                    if (quiet) {
                        settings.set_string ("last-image", "");
                        image_stack.visible_child_name = "empty";
                        return;
                    }
                    report_error (_("Could Not Open the Image"), _("%s could not be read as an image: %s").printf (file.get_basename (), e.message));
                }
            });
        }

        private void load_texture (Gdk.Texture texture) {
            load_serial++;
            try {
                var img = LoadedImage.from_texture (texture, _("Pasted Image"));
                try {
                    img.remember_as (pasted_path ());
                    settings.set_string ("last-image", pasted_path ());
                } catch (Error e) {
                    warning ("colorpicker: %s", e.message);
                    settings.set_string ("last-image", "");
                }
                set_image (img);
            } catch (Error e) {
                report_error (_("Could Not Use the Image"), e.message);
            }
        }

        private void paste_image () {
            var cb = get_clipboard ();
            cb.read_texture_async.begin (null, (o, res) => {
                Gdk.Texture? texture = null;
                try {
                    texture = cb.read_texture_async.end (res);
                } catch (Error e) {
                }
                if (texture != null) {
                    load_texture (texture);
                    return;
                }
                cb.read_value_async.begin (typeof (Gdk.FileList), Priority.DEFAULT, null, (o2, res2) => {
                    try {
                        unowned Value? v = cb.read_value_async.end (res2);
                        if (v != null) {
                            var files = ((Gdk.FileList) v.get_boxed ()).get_files ();
                            if (files.length () > 0) {
                                load_image_file (files.nth_data (0), null, false);
                                return;
                            }
                        }
                    } catch (Error e) {
                    }
                    show_toast (_("The clipboard does not hold an image"));
                });
            });
        }

        private void setup_drop () {
            var drop = new DropTarget (Type.INVALID, Gdk.DragAction.COPY);
            drop.set_gtypes ({ typeof (Gdk.FileList), typeof (Gdk.Texture) });
            drop.drop.connect ((value, x, y) => {
                if (value.holds (typeof (Gdk.FileList))) {
                    var files = ((Gdk.FileList) value.get_boxed ()).get_files ();
                    if (files.length () == 0) return false;
                    load_image_file (files.nth_data (0), null, false);
                    return true;
                }
                if (value.holds (typeof (Gdk.Texture))) {
                    load_texture ((Gdk.Texture) value.get_object ());
                    return true;
                }
                return false;
            });
            overlay.add_controller (drop);
        }

        private PaletteDocument? current_palette () {
            if (stack.visible_child_name != "main") return null;
            if (view_stack.visible_child_name == "image") {
                if (image == null) return null;
                string name = image.title;
                int dot = name.last_index_of (".");
                if (dot > 0) name = name.substring (0, dot);
                var doc = new PaletteDocument (name);
                foreach (var p in image.palette ((int) size_row.value)) doc.add (p.color, p.color.to_hex ());
                return doc;
            }
            string[] names = { _("Shades"), _("Tints"), _("Complementary"), _("Analogous"), _("Triadic") };
            var doc = new PaletteDocument ("%s %s".printf (names[(int) harmony], current.to_hex ()));
            foreach (var c in Palette.generate (current, harmony)) doc.add (c, c.to_hex ());
            return doc;
        }

        private void palette_to_history () {
            var doc = current_palette ();
            if (doc == null) return;
            for (int i = doc.colors.size - 1; i >= 0; i--) history.add (doc.colors[i]);
            show_toast (ngettext ("Saved %d color to history", "Saved %d colors to history", doc.colors.size).printf (doc.colors.size));
        }

        private void export_menu (Widget anchor) {
            var menu = new ContextMenu (anchor);
            foreach (var f in PaletteFormat.all ()) {
                var fmt = f;
                menu.add_item (_("%s (.%s)").printf (fmt.label (), fmt.extension ()), "document-save-as-symbolic", () => export_palette_as (fmt));
            }
            menu.add_separator ();
            menu.add_item (_("Copy as CSS"), "edit-copy-symbolic", () => {
                var doc = current_palette ();
                if (doc == null) return;
                get_clipboard ().set_text (PaletteFile.write_css (doc));
                show_toast (_("Copied the palette as CSS"));
            });
            menu.closed.connect (() => Idle.add (() => {
                menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }

        private void export_palette_as (PaletteFormat format) {
            var doc = current_palette ();
            if (doc == null) return;
            var dlg = new FileDialog ();
            dlg.title = _("Export Palette");
            dlg.initial_name = PaletteFile.slug (doc.name) + "." + format.extension ();
            var filters = new GLib.ListStore (typeof (FileFilter));
            foreach (var f in PaletteFormat.all ()) {
                var ff = new FileFilter ();
                ff.name = _("%s (.%s)").printf (f.label (), f.extension ());
                ff.add_suffix (f.extension ());
                filters.append (ff);
                if (f == format) dlg.default_filter = ff;
            }
            dlg.filters = filters;
            dlg.save.begin (this, null, (o, res) => {
                File file;
                try {
                    file = dlg.save.end (res);
                } catch (Error e) {
                    if (!(e is DialogError.DISMISSED) && !(e is DialogError.CANCELLED)) {
                        report_error (_("Could Not Export the Palette"), e.message);
                    }
                    return;
                }
                PaletteFormat chosen;
                if (!PaletteFormat.from_path (file.get_basename (), out chosen)) {
                    chosen = format;
                    var parent = file.get_parent ();
                    string named = file.get_basename () + "." + format.extension ();
                    file = parent != null ? parent.get_child (named) : File.new_for_path (named);
                }
                write_palette (doc, chosen, file);
            });
        }

        private void write_palette (PaletteDocument doc, PaletteFormat format, File file) {
            var bytes = PaletteFile.write (doc, format);
            file.replace_contents_bytes_async.begin (bytes, null, false, FileCreateFlags.REPLACE_DESTINATION, null, (o, res) => {
                try {
                    file.replace_contents_bytes_async.end (res, null);
                    settings.set_string ("export-format", format.id ());
                    show_toast (_("Exported %s").printf (file.get_basename ()));
                } catch (Error e) {
                    report_error (_("Could Not Export the Palette"), e.message);
                }
            });
        }

        private void report_error (string title, string message) {
            var dlg = new ConfirmDialog ((Gtk.Application) application, title, "dialog-error-symbolic",
                message, _("OK"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.present ();
        }

        private void fill_history () {
            Widget? child;
            while ((child = history_box.get_first_child ()) != null) history_box.remove (child);
            foreach (var c in history.items) history_box.append (chip (c, 40));
            bool empty = history.items.size == 0;
            history_box.visible = !empty;
            history_empty.visible = empty;
            clear_button.sensitive = !empty;
            var action = lookup_action ("clear-history") as SimpleAction;
            if (action != null) action.set_enabled (!empty);
        }

        private void swap_contrast () {
            var t = contrast_bg;
            contrast_bg = new Color (current.r, current.g, current.b, current.a);
            apply_color (t, true);
        }

        public void pick_color () {
            if (picking) return;
            picking = true;
            pick_bubble.sensitive = false;
            Portal.pick.begin ("", (o, res) => {
                picking = false;
                pick_bubble.sensitive = true;
                try {
                    var c = Portal.pick.end (res);
                    history.add (c);
                    apply_color (c, true);
                    show_page ("main");
                } catch (PickError e) {
                    report_pick_error (e);
                }
            });
        }

        public void show_color (Color c) {
            apply_color (c, true);
            show_page ("main");
        }

        private void pick_background () {
            if (picking) return;
            picking = true;
            Portal.pick.begin ("", (o, res) => {
                picking = false;
                try {
                    contrast_bg = Portal.pick.end (res);
                    update_contrast ();
                    schedule_save ();
                } catch (PickError e) {
                    report_pick_error (e);
                }
            });
        }

        private void report_pick_error (PickError e) {
            if (e is PickError.CANCELLED) return;
            var dlg = new ConfirmDialog ((Gtk.Application) application, _("Could Not Pick a Color"), "dialog-error-symbolic",
                e.message, _("OK"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.present ();
        }

        public void enter_color () {
            var dlg = new ConfirmDialog ((Gtk.Application) application, _("Enter a Color"), null,
                _("A hex code, a CSS color such as rgb(), hsl(), lab() or oklch(), or a color name."), _("Use Color"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.set_default_size (420, 0);
            var group = new PreferencesGroup ();
            var entry = new EntryRow (_("Color"));
            group.add_row (entry);
            dlg.custom_area.append (group);
            var preview_row = new Box (Orientation.HORIZONTAL, 10);
            preview_row.halign = Align.CENTER;
            var sw = new Swatch (28, 28, 8);
            var hint = new Label ("");
            hint.add_css_class ("dim-label");
            hint.wrap = true;
            hint.max_width_chars = 40;
            preview_row.append (sw);
            preview_row.append (hint);
            dlg.custom_area.append (preview_row);
            Callback validate = () => {
                var c = Parser.parse (entry.text);
                dlg.primary_sensitive = c != null;
                sw.visible = c != null;
                if (c != null) sw.color = c;
                if (entry.text.strip () == "") hint.label = _("For example #3584e4, rgb(53 132 228) or tomato");
                else if (c == null) hint.label = _("This is not a color this app understands.");
                else hint.label = Formatter.format (c, Format.RGB);
            };
            entry.entry_changed.connect (() => validate ());
            entry.entry_activated.connect (() => {
                if (Parser.parse (entry.text) == null) return;
                dlg.response (ConfirmDialog.Response.PRIMARY);
                dlg.close_dialog ();
            });
            validate ();
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                var c = Parser.parse (entry.text);
                if (c == null) return;
                history.add (c);
                apply_color (c, true);
                show_page ("main");
            });
            dlg.present ();
            entry.grab_focus ();
        }

        private void paste_color () {
            get_clipboard ().read_text_async.begin (null, (o, res) => {
                string? text = null;
                try {
                    text = get_clipboard ().read_text_async.end (res);
                } catch (Error e) {
                }
                var c = text != null ? Parser.parse (text) : null;
                if (c == null) {
                    show_toast (_("The clipboard does not hold a color"));
                    return;
                }
                history.add (c);
                apply_color (c, true);
                show_page ("main");
            });
        }

        private void copy_text (string text) {
            get_clipboard ().set_text (text);
            show_toast (_("Copied %s").printf (text));
        }

        private void copy_format (Format f) {
            if (stack.visible_child_name != "main" || view_stack.visible_child_name != "color") return;
            copy_text (Formatter.format (current, f, upper_hex));
        }

        private void copy_name () {
            copy_text (NamedColors.name_of (current));
        }

        private void confirm_clear () {
            if (history.items.size == 0) return;
            var dlg = new ConfirmDialog ((Gtk.Application) application, _("Clear History?"), "user-trash-symbolic",
                _("All %d saved colors are removed. This cannot be undone.").printf (history.items.size), _("Clear"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY) history.clear ();
            });
            dlg.present ();
        }

        private void show_toast (string text) {
            if (toast == null) {
                toast = new Label ("");
                toast.add_css_class ("colorpicker-toast");
                toast.halign = Align.CENTER;
                toast.valign = Align.END;
                toast.margin_bottom = 28;
                toast.can_target = false;
                toast.ellipsize = Pango.EllipsizeMode.MIDDLE;
                toast.max_width_chars = 48;
                overlay.add_overlay (toast);
            }
            toast.label = text;
            toast.visible = true;
            if (toast_id != 0) Source.remove (toast_id);
            toast_id = Timeout.add (2000, () => {
                toast_id = 0;
                toast.visible = false;
                return Source.REMOVE;
            });
        }

        private bool load_state () {
            try {
                state.load_from_file (state_path, KeyFileFlags.NONE);
            } catch (Error e) {
                return false;
            }
            try {
                var c = Color.from_hex (state.get_string ("State", "color"));
                if (c != null) current = c;
            } catch (Error e) {
            }
            try {
                var bg = Color.from_hex (state.get_string ("State", "background"));
                if (bg != null) contrast_bg = bg;
            } catch (Error e) {
            }
            try {
                harmony = Harmony.from_id (state.get_string ("State", "palette"));
            } catch (Error e) {
            }
            try {
                upper_hex = state.get_boolean ("State", "uppercase-hex");
            } catch (Error e) {
            }
            return true;
        }

        private void schedule_save () {
            if (save_id != 0) Source.remove (save_id);
            save_id = Timeout.add (800, () => {
                save_id = 0;
                save_state ();
                return Source.REMOVE;
            });
        }

        private void save_state () {
            if (stack == null || stack.visible_child_name != "main") return;
            state.set_string ("State", "color", current.to_hex (true));
            state.set_string ("State", "background", contrast_bg.to_hex (true));
            state.set_string ("State", "palette", harmony.id ());
            state.set_boolean ("State", "uppercase-hex", upper_hex);
            DirUtils.create_with_parents (Path.get_dirname (state_path), 0700);
            try {
                state.save_to_file (state_path);
            } catch (Error e) {
                warning ("colorpicker: %s", e.message);
            }
        }
    }
}
