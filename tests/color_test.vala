using Singularity.Apps.ColorPicker;

void near (double got, double want, double tol) {
    if (Math.fabs (got - want) > tol) {
        error ("expected %.6f, got %.6f (tolerance %g)", want, got, tol);
    }
}

void same_rgb (Color a, Color b, double tol) {
    near (a.r, b.r, tol);
    near (a.g, b.g, tol);
    near (a.b, b.b, tol);
    near (a.a, b.a, tol);
}

Color hex (string s) {
    var c = Color.from_hex (s);
    assert (c != null);
    return c;
}

Color[] grid () {
    Color[] all = {};
    for (int r = 0; r <= 255; r += 17) {
        for (int g = 0; g <= 255; g += 17) {
            for (int b = 0; b <= 255; b += 17) all += new Color.rgb8 (r, g, b);
        }
    }
    all += new Color.rgb8 (1, 2, 3);
    all += new Color.rgb8 (254, 253, 1);
    return all;
}

void test_hex () {
    assert (hex ("#abc").to_hex () == "#aabbcc");
    assert (hex ("abc").to_hex () == "#aabbcc");
    assert (hex ("#FF8000").to_hex () == "#ff8000");
    assert (hex ("#ff8000").to_hex (false, true) == "#FF8000");
    var translucent = hex ("#11223380");
    near (translucent.a, 128 / 255.0, 1e-9);
    assert (translucent.to_hex () == "#11223380");
    assert (hex ("#1234").to_hex () == "#11223344");
    assert (hex ("#000000").to_hex (true) == "#000000ff");
    assert (Color.from_hex ("#12345") == null);
    assert (Color.from_hex ("#ggg") == null);
    assert (Color.from_hex ("") == null);
    assert (Color.from_hex ("#") == null);
    assert (Color.from_hex ("#1234567890") == null);
    foreach (var c in grid ()) assert (hex (c.to_hex ()).to_hex () == c.to_hex ());
}

void test_linear () {
    near (Color.to_linear (0), 0, 1e-12);
    near (Color.to_linear (1), 1, 1e-12);
    near (Color.to_linear (0.5), 0.214041, 1e-6);
    near (Color.to_linear (0.04), 0.04 / 12.92, 1e-12);
    for (double v = 0; v <= 1.0; v += 0.01) near (Color.from_linear (Color.to_linear (v)), v, 1e-9);
}

void test_hsl () {
    double h, s, l;
    hex ("#3366cc").to_hsl (out h, out s, out l);
    near (h, 220, 1e-9);
    near (s, 0.6, 1e-9);
    near (l, 0.5, 1e-9);
    hex ("#808080").to_hsl (out h, out s, out l);
    near (h, 0, 1e-9);
    near (s, 0, 1e-9);
    near (l, 128 / 255.0, 1e-9);
    assert (Color.from_hsl (120, 1, 0.25).to_hex () == "#008000");
    assert (Color.from_hsl (-120, 1, 0.5).to_hex () == "#0000ff");
    assert (Color.from_hsl (480, 1, 0.5).to_hex () == "#00ff00");
    foreach (var c in grid ()) {
        c.to_hsl (out h, out s, out l);
        same_rgb (Color.from_hsl (h, s, l), c, 1e-9);
    }
}

void test_hsv () {
    double h, s, v;
    hex ("#3366cc").to_hsv (out h, out s, out v);
    near (h, 220, 1e-9);
    near (s, 0.75, 1e-9);
    near (v, 0.8, 1e-9);
    hex ("#ffff00").to_hsv (out h, out s, out v);
    near (h, 60, 1e-9);
    near (s, 1, 1e-9);
    near (v, 1, 1e-9);
    assert (Color.from_hsv (300, 1, 1).to_hex () == "#ff00ff");
    foreach (var c in grid ()) {
        c.to_hsv (out h, out s, out v);
        same_rgb (Color.from_hsv (h, s, v), c, 1e-9);
    }
}

void test_cmyk () {
    double c, m, y, k;
    hex ("#3366cc").to_cmyk (out c, out m, out y, out k);
    near (c, 0.75, 1e-9);
    near (m, 0.5, 1e-9);
    near (y, 0, 1e-9);
    near (k, 0.2, 1e-9);
    hex ("#000000").to_cmyk (out c, out m, out y, out k);
    near (k, 1, 1e-9);
    near (c + m + y, 0, 1e-9);
    assert (Color.from_cmyk (0, 1, 1, 0).to_hex () == "#ff0000");
    foreach (var col in grid ()) {
        col.to_cmyk (out c, out m, out y, out k);
        same_rgb (Color.from_cmyk (c, m, y, k), col, 1e-9);
    }
}

void test_xyz () {
    double x, y, z;
    hex ("#ffffff").to_xyz (out x, out y, out z);
    near (x, 0.95047, 1e-4);
    near (y, 1.0, 1e-4);
    near (z, 1.08883, 1e-4);
    hex ("#ff0000").to_xyz (out x, out y, out z);
    near (x, 0.412456, 1e-5);
    near (y, 0.212673, 1e-5);
    near (z, 0.019334, 1e-5);
    foreach (var c in grid ()) {
        c.to_xyz (out x, out y, out z);
        same_rgb (Color.from_xyz (x, y, z), c, 2e-5);
    }
}

void test_lab () {
    double l, a, b;
    hex ("#ff0000").to_lab (out l, out a, out b);
    near (l, 53.2408, 0.01);
    near (a, 80.0925, 0.01);
    near (b, 67.2032, 0.01);
    hex ("#ffffff").to_lab (out l, out a, out b);
    near (l, 100, 0.01);
    near (a, 0, 0.01);
    near (b, 0, 0.01);
    hex ("#000000").to_lab (out l, out a, out b);
    near (l, 0, 1e-9);
    hex ("#808080").to_lab (out l, out a, out b);
    near (l, 53.59, 0.02);
    hex ("#0000ff").to_lab (out l, out a, out b);
    near (l, 32.30, 0.02);
    near (a, 79.19, 0.02);
    near (b, -107.86, 0.02);
    foreach (var c in grid ()) {
        c.to_lab (out l, out a, out b);
        same_rgb (Color.from_lab (l, a, b), c, 2e-5);
    }
}

void test_lch () {
    double l, c, h;
    hex ("#ff0000").to_lch (out l, out c, out h);
    near (l, 53.2408, 0.01);
    near (c, 104.5518, 0.01);
    near (h, 39.999, 0.01);
    hex ("#808080").to_lch (out l, out c, out h);
    near (c, 0, 0.01);
    foreach (var col in grid ()) {
        col.to_lch (out l, out c, out h);
        same_rgb (Color.from_lch (l, c, h), col, 2e-5);
    }
}

void test_oklab () {
    double l, a, b;
    hex ("#ffffff").to_oklab (out l, out a, out b);
    near (l, 1.0, 1e-4);
    near (a, 0, 1e-4);
    near (b, 0, 1e-4);
    hex ("#0000ff").to_oklab (out l, out a, out b);
    near (l, 0.4520, 1e-3);
    near (a, -0.0325, 1e-3);
    near (b, -0.3115, 1e-3);
    foreach (var c in grid ()) {
        c.to_oklab (out l, out a, out b);
        same_rgb (Color.from_oklab (l, a, b), c, 2e-5);
    }
}

void test_oklch () {
    double l, c, h;
    hex ("#ff0000").to_oklch (out l, out c, out h);
    near (l, 0.62796, 1e-4);
    near (c, 0.25768, 1e-4);
    near (h, 29.23, 0.01);
    hex ("#00ff00").to_oklch (out l, out c, out h);
    near (l, 0.86644, 1e-4);
    near (c, 0.29483, 1e-4);
    near (h, 142.50, 0.01);
    hex ("#777777").to_oklch (out l, out c, out h);
    near (c, 0, 1e-4);
    near (h, 0, 1e-9);
    foreach (var col in grid ()) {
        col.to_oklch (out l, out c, out h);
        same_rgb (Color.from_oklch (l, c, h), col, 2e-5);
    }
}

void test_format () {
    var red = hex ("#ff0000");
    assert (Formatter.format (red, Format.HEX) == "#ff0000");
    assert (Formatter.format (red, Format.HEX, true) == "#FF0000");
    assert (Formatter.format (red, Format.RGB) == "rgb(255, 0, 0)");
    assert (Formatter.format (red, Format.HSL) == "hsl(0, 100%, 50%)");
    assert (Formatter.format (red, Format.HSV) == "hsv(0, 100%, 100%)");
    assert (Formatter.format (red, Format.CMYK) == "cmyk(0%, 100%, 100%, 0%)");
    assert (Formatter.format (red, Format.LAB) == "lab(53.24% 80.09 67.2)");
    assert (Formatter.format (red, Format.LCH) == "lch(53.24% 104.55 40)");
    assert (Formatter.format (red, Format.OKLCH) == "oklch(62.8% 0.2577 29.23)");
    var half = new Color (1, 0, 0, 0.5);
    assert (Formatter.format (half, Format.RGB) == "rgba(255, 0, 0, 0.5)");
    assert (Formatter.format (half, Format.OKLCH) == "oklch(62.8% 0.2577 29.23 / 0.5)");
    assert (Formatter.num (-0.0001, 2) == "0");
    assert (Formatter.num (1.5, 0) == "2");
    assert (Formatter.num (0.125, 3) == "0.125");
    Intl.setlocale (LocaleCategory.NUMERIC, "de_DE.UTF-8");
    assert (Formatter.num (0.5, 2) == "0.5");
    Intl.setlocale (LocaleCategory.NUMERIC, "C");
    foreach (var c in grid ()) {
        foreach (var f in Format.all ()) {
            var back = Parser.parse (Formatter.format (c, f));
            assert (back != null);
            same_rgb (back, c, 1.0 / 255);
        }
    }
}

void test_parse () {
    assert (Parser.parse ("rgb(255 0 0 / 50%)").to_hex () == "#ff000080");
    assert (Parser.parse ("rgba(0, 128, 255, 1)").to_hex () == "#0080ff");
    assert (Parser.parse ("rgb(100%, 0%, 50%)").to_hex () == "#ff0080");
    assert (Parser.parse ("hsl(120deg 100% 25%)").to_hex () == "#008000");
    assert (Parser.parse ("HSV(60, 100%, 100%)").to_hex () == "#ffff00");
    assert (Parser.parse ("cmyk(0, 1, 1, 0)").to_hex () == "#ff0000");
    assert (Parser.parse ("cmyk(75%, 50%, 0%, 20%)").to_hex () == "#3366cc");
    assert (Parser.parse ("lab(53.24 80.09 67.2)").to_hex () == "#ff0000");
    assert (Parser.parse ("oklab(0.62796 0.22486 0.12585)").to_hex () == "#ff0000");
    assert (Parser.parse ("oklch(0.628 0.2577 29.23)").to_hex () == "#ff0000");
    assert (Parser.parse ("  RebeccaPurple ").to_hex () == "#663399");
    assert (Parser.parse ("#0f0").to_hex () == "#00ff00");
    assert (Parser.parse ("") == null);
    assert (Parser.parse ("banana") == null);
    assert (Parser.parse ("rgb(1, 2)") == null);
    assert (Parser.parse ("rgb(a, b, c)") == null);
    assert (Parser.parse ("foo(1, 2, 3)") == null);
    assert (Parser.parse ("rgb(1, 2, 3") == null);
}

void test_named () {
    assert (NamedColors.count () == 148);
    assert (NamedColors.lookup ("tomato").to_hex () == "#ff6347");
    assert (NamedColors.lookup ("nope") == null);
    double d;
    assert (NamedColors.nearest (hex ("#663399"), out d) == "rebeccapurple");
    near (d, 0, 1e-9);
    assert (NamedColors.nearest (hex ("#ff0001"), out d) == "red");
    assert (d > 0 && d < 0.5);
    assert (NamedColors.nearest (hex ("#fe6448"), out d) == "tomato");
    assert (NamedColors.nearest (hex ("#010101"), out d) == "black");
    assert (NamedColors.nearest (hex ("#00ffff"), out d) == "aqua");
    assert (NamedColors.nearest (new Color (1, 1, 1, 0.1), out d) == "white");
    assert (NamedColors.nearest (hex ("#171717"), out d) == "black");
    assert (NamedColors.nearest (hex ("#ff0000"), out d) == "red");
    near (d, 0, 1e-9);
    string grey = NamedColors.nearest (hex ("#808080"), out d);
    assert (grey == "gray" || grey == "grey");
    near (d, 0, 1e-9);
    assert (NamedColors.nearest (hex ("#1c1c1c"), out d) == "black");
    assert (NamedColors.nearest (hex ("#1a1a6e"), out d) == "midnightblue");
}

void test_delta_e () {
    near (Color.from_lab (50, 0, 0).delta_e (Color.from_lab (50, -1, 2)), 2.3669, 1e-3);
    near (Color.from_lab (50, 2.5, 0).delta_e (Color.from_lab (73, 25, -18)), 27.1492, 1e-3);
    near (Color.from_lab (60.2574, -34.0099, 36.2677).delta_e (Color.from_lab (60.4626, -34.1751, 39.4387)), 1.2644, 1e-3);
    var c = hex ("#336699");
    near (c.delta_e (c), 0, 1e-9);
}

void test_contrast () {
    var black = hex ("#000000"), white = hex ("#ffffff");
    near (Contrast.ratio (black, white), 21, 1e-9);
    near (Contrast.ratio (white, black), 21, 1e-9);
    near (Contrast.ratio (white, white), 1, 1e-9);
    near (Contrast.ratio (hex ("#777777"), white), 4.48, 0.01);
    near (Contrast.ratio (hex ("#767676"), white), 4.54, 0.01);
    assert (Contrast.ratio (hex ("#767676"), white) >= Contrast.AA);
    assert (Contrast.ratio (hex ("#777777"), white) < Contrast.AA);
    assert (Contrast.ratio (hex ("#777777"), white) >= Contrast.AA_LARGE);
    near (Contrast.ratio (hex ("#0000ff"), white), 8.59, 0.01);
    near (hex ("#ff0000").luminance (), 0.2126, 1e-9);
    near (hex ("#808080").luminance (), 0.21586, 1e-4);
    near (Contrast.ratio (new Color (0, 0, 0, 0.5), white), Contrast.ratio (hex ("#808080"), white), 0.05);
    assert (Contrast.format_ratio (21) == "21:1");
    assert (Contrast.format_ratio (4.478) == "4.47:1");
}

void test_palette () {
    var red = hex ("#ff0000");
    var shades = Palette.generate (red, Harmony.SHADES);
    assert (shades.length == 6);
    assert (shades[0].equals (red));
    for (int i = 1; i < shades.length; i++) assert (shades[i].luminance () < shades[i - 1].luminance ());
    var tints = Palette.generate (red, Harmony.TINTS);
    assert (tints.length == 6);
    for (int i = 1; i < tints.length; i++) assert (tints[i].luminance () > tints[i - 1].luminance ());
    var comp = Palette.generate (red, Harmony.COMPLEMENTARY);
    assert (comp.length == 2 && comp[1].to_hex () == "#00ffff");
    var tri = Palette.generate (red, Harmony.TRIADIC);
    assert (tri.length == 3 && tri[1].to_hex () == "#00ff00" && tri[2].to_hex () == "#0000ff");
    var ana = Palette.generate (red, Harmony.ANALOGOUS);
    assert (ana.length == 3 && ana[0].to_hex () == "#ff0080" && ana[1].equals (red) && ana[2].to_hex () == "#ff8000");
    var gray = Palette.generate (hex ("#808080"), Harmony.COMPLEMENTARY);
    assert (gray[1].to_hex () == "#808080");
    assert (Harmony.from_id ("triadic") == Harmony.TRIADIC);
    assert (Harmony.from_id ("bogus") == Harmony.SHADES);
}

void test_history () {
    try {
        run_history ();
    } catch (Error e) {
        error ("%s", e.message);
    }
}

void run_history () throws Error {
    string dir = DirUtils.make_tmp ("colorpicker-XXXXXX");
    string path = Path.build_filename (dir, "sub", "history.json");
    var h = new History (path);
    assert (h.items.size == 0);
    int changes = 0;
    h.changed.connect (() => changes++);
    h.add (hex ("#ff0000"));
    h.add (hex ("#00ff00"));
    h.add (new Color (0, 0, 1, 0.5));
    h.add (hex ("#ff0000"));
    assert (changes == 4);
    var again = new History (path);
    assert (again.items.size == 3);
    assert (again.items[0].to_hex () == "#ff0000");
    assert (again.items[1].to_hex () == "#0000ff80");
    assert (again.items[2].to_hex () == "#00ff00");
    for (int i = 0; i < 60; i++) again.add (new Color.rgb8 (i, i, i));
    assert (again.items.size == History.LIMIT);
    assert (new History (path).items.size == History.LIMIT);
    assert (again.items[0].to_hex () == "#3b3b3b");
    again.remove (new Color.rgb8 (59, 59, 59));
    assert (new History (path).items[0].to_hex () == "#3a3a3a");
    again.clear ();
    assert (new History (path).items.size == 0);
    FileUtils.set_contents (path, "{ not json");
    var broken = new History (path);
    assert (broken.items.size == 0 && broken.load_error != null);
    FileUtils.set_contents (path, "[\"#123456\", 5, \"zz\", \"#abcdef\"]");
    var mixed = new History (path);
    assert (mixed.items.size == 2 && mixed.items[1].to_hex () == "#abcdef");
    FileUtils.remove (path);
    DirUtils.remove (Path.build_filename (dir, "sub"));
    DirUtils.remove (dir);
}

void test_portal () {
    var b = new VariantBuilder (new VariantType ("a{sv}"));
    b.add ("{sv}", "color", new Variant ("(ddd)", 0.5, 0.25, 1.0));
    try {
        var c = Portal.parse_response (0, b.end ());
        near (c.r, 0.5, 1e-12);
        near (c.g, 0.25, 1e-12);
        near (c.b, 1.0, 1e-12);
        near (c.a, 1.0, 1e-12);
    } catch (Error e) {
        assert_not_reached ();
    }
    var empty = new Variant.array (new VariantType ("{sv}"), {});
    try {
        Portal.parse_response (1, empty);
        assert_not_reached ();
    } catch (PickError e) {
        assert (e is PickError.CANCELLED);
    }
    try {
        Portal.parse_response (2, empty);
        assert_not_reached ();
    } catch (PickError e) {
        assert (e is PickError.UNSUPPORTED);
    }
    try {
        Portal.parse_response (0, empty);
        assert_not_reached ();
    } catch (PickError e) {
        assert (e is PickError.FAILED);
    }
    var wrong = new VariantBuilder (new VariantType ("a{sv}"));
    wrong.add ("{sv}", "color", new Variant.string ("red"));
    try {
        Portal.parse_response (0, wrong.end ());
        assert_not_reached ();
    } catch (PickError e) {
        assert (e is PickError.FAILED);
    }
    assert (Portal.request_path (":1.42", "tok") == "/org/freedesktop/portal/desktop/request/1_42/tok");
    assert (Portal.map_dbus_error (new DBusError.SERVICE_UNKNOWN ("x")) is PickError.UNSUPPORTED);
    assert (Portal.map_dbus_error (new DBusError.UNKNOWN_METHOD ("x")) is PickError.UNSUPPORTED);
    assert (Portal.map_dbus_error (new DBusError.UNKNOWN_INTERFACE ("x")) is PickError.UNSUPPORTED);
    assert (Portal.map_dbus_error (new DBusError.ACCESS_DENIED ("x")) is PickError.FAILED);
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C");
    Test.init (ref args);
    Test.add_func ("/color/hex", test_hex);
    Test.add_func ("/color/linear", test_linear);
    Test.add_func ("/color/hsl", test_hsl);
    Test.add_func ("/color/hsv", test_hsv);
    Test.add_func ("/color/cmyk", test_cmyk);
    Test.add_func ("/color/xyz", test_xyz);
    Test.add_func ("/color/lab", test_lab);
    Test.add_func ("/color/lch", test_lch);
    Test.add_func ("/color/oklab", test_oklab);
    Test.add_func ("/color/oklch", test_oklch);
    Test.add_func ("/color/format", test_format);
    Test.add_func ("/color/parse", test_parse);
    Test.add_func ("/color/named", test_named);
    Test.add_func ("/color/delta-e", test_delta_e);
    Test.add_func ("/color/contrast", test_contrast);
    Test.add_func ("/color/palette", test_palette);
    Test.add_func ("/color/history", test_history);
    Test.add_func ("/color/portal", test_portal);
    return Test.run ();
}
