namespace Singularity.Apps.ColorPicker {

    internal class ColorPickerIntents : Object {

        private static string text(Json.Object args, string key) {
            return args.has_member(key) ? args.get_string_member(key).strip() : "";
        }

        private static Color parse(Json.Object args, string key) throws Error {
            string value = text(args, key);
            if (value == "") throw new IOError.INVALID_ARGUMENT("give %s as hex, rgb(), hsl(), oklch() or a CSS color name", key);
            var c = Parser.parse(value);
            if (c == null) c = NamedColors.lookup(value);
            if (c == null) throw new IOError.INVALID_ARGUMENT("%s is not a color", value);
            return c;
        }

        private static string round2(double v) {
            return "%.2f".printf(Math.round(v * 100) / 100);
        }

        private static void describe(Json.Builder b, Color c) {
            b.begin_object();
            foreach (var f in Format.all()) b.set_member_name(f.id()).add_string_value(Formatter.format(c, f));
            double distance;
            string name = NamedColors.nearest(c, out distance);
            b.set_member_name("nearest_name").add_string_value(name);
            b.set_member_name("exact_name").add_boolean_value(distance < 0.5);
            b.set_member_name("on_white").add_string_value(round2(Contrast.ratio(c, new Color(1, 1, 1))));
            b.set_member_name("on_black").add_string_value(round2(Contrast.ratio(c, new Color(0, 0, 0))));
            b.end_object();
        }

        private static void history(Json.Builder b, ColorPickerApp app) {
            b.begin_array();
            foreach (var c in app.history.items) b.add_string_value(c.to_hex(c.a < 1));
            b.end_array();
        }

        private static bool saved(ColorPickerApp app, Color c) {
            var fresh = new History(app.history.path);
            foreach (var x in fresh.items) if (x.to_hex(true) == c.to_hex(true)) return true;
            return false;
        }

        internal static void install(ColorPickerApp app) {
            var agent = app.agent;
            agent.add_intent("colorpicker_describe", "A color in every notation (hex, rgb, hsl, hsv, cmyk, lab, lch, oklch), its nearest CSS name and its contrast on white and on black.",
                "{\"type\":\"object\",\"properties\":{\"color\":{\"type\":\"string\"}},\"required\":[\"color\"]}",
                Singularity.AppIntentRisk.READ, (args) => {
                    var b = new Json.Builder();
                    describe(b, parse(args, "color"));
                    return b.get_root();
                });
            agent.add_intent("colorpicker_contrast", "WCAG contrast between a text color and a background, whether it passes AA or AAA, and the closest text color that would pass.",
                "{\"type\":\"object\",\"properties\":{\"foreground\":{\"type\":\"string\"},\"background\":{\"type\":\"string\"},\"level\":{\"type\":\"string\",\"enum\":[\"AA\",\"AAA\"]},\"large_text\":{\"type\":\"boolean\"}},\"required\":[\"foreground\",\"background\"]}",
                Singularity.AppIntentRisk.READ, (args) => {
                    var fg = parse(args, "foreground");
                    var bg = parse(args, "background");
                    bool aaa = text(args, "level").up() == "AAA";
                    bool large = args.has_member("large_text") && args.get_boolean_member("large_text");
                    double target = ContrastFix.required(aaa, large);
                    var s = ContrastFix.suggest(fg, bg, target);
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("ratio").add_string_value(round2(s.before));
                    b.set_member_name("required").add_string_value(round2(target));
                    b.set_member_name("passes").add_boolean_value(s.already_passes);
                    b.set_member_name("checks").begin_object();
                    foreach (bool level_aaa in new bool[] { false, true }) {
                        foreach (bool level_large in new bool[] { false, true }) {
                            string key = (level_aaa ? "AAA" : "AA") + (level_large ? "_large" : "");
                            b.set_member_name(key).add_boolean_value(s.before >= ContrastFix.required(level_aaa, level_large));
                        }
                    }
                    b.end_object();
                    if (!s.already_passes) {
                        if (s.found) {
                            b.set_member_name("suggested_foreground").add_string_value(s.suggested.to_hex(false));
                            b.set_member_name("suggested_ratio").add_string_value(round2(s.after));
                        } else {
                            b.set_member_name("suggested_foreground").add_null_value();
                            b.set_member_name("hint").add_string_value("no text color of this hue reaches the target on this background; change the background");
                        }
                    }
                    b.end_object();
                    return b.get_root();
                });
            agent.add_intent("colorpicker_palette", "Generate shades, tints, complementary, analogous or triadic colors from a base color.",
                "{\"type\":\"object\",\"properties\":{\"color\":{\"type\":\"string\"},\"harmony\":{\"type\":\"string\",\"enum\":[\"shades\",\"tints\",\"complementary\",\"analogous\",\"triadic\"]},\"steps\":{\"type\":\"integer\"}},\"required\":[\"color\"]}",
                Singularity.AppIntentRisk.READ, (args) => {
                    var c = parse(args, "color");
                    string h = text(args, "harmony");
                    var kind = Harmony.from_id(h == "" ? "shades" : h);
                    if (h != "" && kind.id() != h) throw new IOError.INVALID_ARGUMENT("unknown harmony %s", h);
                    int steps = args.has_member("steps") ? (int) args.get_int_member("steps").clamp(2, 12) : 6;
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("harmony").add_string_value(kind.id());
                    b.set_member_name("colors").begin_array();
                    foreach (var x in Palette.generate(c, kind, steps)) b.add_string_value(x.to_hex(false));
                    b.end_array();
                    b.end_object();
                    return b.get_root();
                });
            agent.add_intent("colorpicker_color_blindness", "How a color, or a pair of colors, looks with protanopia, deuteranopia, tritanopia and achromatopsia, and whether a pair stays distinguishable.",
                "{\"type\":\"object\",\"properties\":{\"color\":{\"type\":\"string\"},\"other\":{\"type\":\"string\"}},\"required\":[\"color\"]}",
                Singularity.AppIntentRisk.READ, (args) => {
                    var c = parse(args, "color");
                    Color? o = text(args, "other") != "" ? parse(args, "other") : null;
                    var b = new Json.Builder();
                    b.begin_object();
                    foreach (var d in Deficiency.deficiencies()) {
                        b.set_member_name(d.id()).begin_object();
                        var sc = Vision.simulate(c, d);
                        b.set_member_name("color").add_string_value(sc.to_hex(false));
                        if (o != null) {
                            var so = Vision.simulate(o, d);
                            b.set_member_name("other").add_string_value(so.to_hex(false));
                            double de = sc.delta_e(so);
                            b.set_member_name("difference").add_string_value(round2(de));
                            b.set_member_name("distinguishable").add_boolean_value(de >= 10);
                        }
                        b.end_object();
                    }
                    b.end_object();
                    return b.get_root();
                });
            agent.add_intent("colorpicker_history", "The colors saved in Color Picker, newest first, as hex.",
                "{\"type\":\"object\",\"properties\":{}}", Singularity.AppIntentRisk.READ, (args) => {
                    app.history.reload();
                    var b = new Json.Builder();
                    history(b, app);
                    return b.get_root();
                });
            agent.add_intent("colorpicker_save", "Save a color at the top of the Color Picker history.",
                "{\"type\":\"object\",\"properties\":{\"color\":{\"type\":\"string\"}},\"required\":[\"color\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var c = parse(args, "color");
                    app.history.add(c);
                    if (!saved(app, c)) throw new IOError.FAILED("the color was not saved: %s", app.history.load_error ?? "write failed");
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("saved").add_string_value(c.to_hex(c.a < 1));
                    b.set_member_name("undo").add_string_value("colorpicker_remove with color " + c.to_hex(c.a < 1));
                    b.end_object();
                    return b.get_root();
                });
            agent.add_intent("colorpicker_remove", "Remove a color from the Color Picker history.",
                "{\"type\":\"object\",\"properties\":{\"color\":{\"type\":\"string\"}},\"required\":[\"color\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var c = parse(args, "color");
                    app.history.reload();
                    Color? present = null;
                    foreach (var x in app.history.items) if (x.to_hex(true) == c.to_hex(true)) present = x;
                    if (present == null) throw new IOError.NOT_FOUND("%s is not in the history", c.to_hex(false));
                    app.history.remove(present);
                    if (saved(app, c)) throw new IOError.FAILED("%s is still in the history", c.to_hex(false));
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("removed").add_string_value(c.to_hex(c.a < 1));
                    b.set_member_name("undo").add_string_value("colorpicker_save with color " + c.to_hex(c.a < 1));
                    b.end_object();
                    return b.get_root();
                });
            agent.add_intent("colorpicker_copy", "Copy a color to the clipboard in a chosen notation so the person can paste it.",
                "{\"type\":\"object\",\"properties\":{\"color\":{\"type\":\"string\"},\"format\":{\"type\":\"string\",\"enum\":[\"hex\",\"rgb\",\"hsl\",\"hsv\",\"cmyk\",\"lab\",\"lch\",\"oklch\"]}},\"required\":[\"color\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var c = parse(args, "color");
                    string value = Formatter.format(c, Format.from_id(text(args, "format") == "" ? "hex" : text(args, "format")));
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("copied").add_string_value(value);
                    b.set_member_name("private").begin_object();
                    b.set_member_name("clipboard").begin_object();
                    b.set_member_name("text").add_string_value(value);
                    b.set_member_name("sensitive").add_boolean_value(false);
                    b.set_member_name("clear_after").add_int_value(0);
                    b.end_object();
                    b.end_object();
                    b.end_object();
                    return b.get_root();
                });
        }
    }
}
