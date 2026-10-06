using Singularity.Apps.ColorPicker;

void near (double got, double want, double tol) {
    if (Math.fabs (got - want) > tol) {
        error ("expected %.6f, got %.6f (tolerance %g)", want, got, tol);
    }
}

Color hex (string s) {
    var c = Color.from_hex (s);
    assert (c != null);
    return c;
}

void check_hex (Color got, string want) {
    if (got.to_hex () != want) error ("expected %s, got %s", want, got.to_hex ());
}

void test_vision_reference () {
    string[,] table = {
        { "#ff0000", "#6d5f00", "#a39000", "#ff000f", "#7f7f7f" },
        { "#00ff00", "#ffe500", "#efd63a", "#00f7d9", "#dcdcdc" },
        { "#0000ff", "#0059ff", "#003dfb", "#006b96", "#4c4c4c" },
        { "#3584e4", "#548ce8", "#347ce2", "#009ba9", "#838383" },
        { "#e66100", "#887700", "#a89500", "#fd3f53", "#8a8a8a" },
        { "#2ec27e", "#c0b37a", "#afa682", "#00c1b0", "#ababab" }
    };
    var kinds = Deficiency.deficiencies ();
    for (int i = 0; i < table.length[0]; i++) {
        var c = hex (table[i, 0]);
        for (int k = 0; k < kinds.length; k++) check_hex (Vision.simulate (c, kinds[k]), table[i, k + 1]);
    }
}

void test_vision_matrices () {
    foreach (var d in Deficiency.all ()) {
        var m = Vision.matrix (d);
        assert (m.length == 9);
        for (int row = 0; row < 3; row++) near (m[row * 3] + m[row * 3 + 1] + m[row * 3 + 2], 1, 2e-6);
    }
    var p = Vision.matrix (Deficiency.PROTANOPIA);
    near (p[0], 0.152286, 1e-9);
    near (p[1], 1.052583, 1e-9);
    near (p[8], 1.051998, 1e-9);
    var dm = Vision.matrix (Deficiency.DEUTERANOPIA);
    near (dm[0], 0.367322, 1e-9);
    near (dm[4], 0.672501, 1e-9);
    var t = Vision.matrix (Deficiency.TRITANOPIA);
    near (t[0], 1.255528, 1e-9);
    near (t[7], 0.691367, 1e-9);
}

void test_vision_properties () {
    for (int v = 0; v <= 255; v += 15) {
        var gray = new Color.rgb8 (v, v, v);
        foreach (var d in Deficiency.all ()) {
            var s = Vision.simulate (gray, d);
            near (s.red8, v, 1);
            near (s.green8, v, 1);
            near (s.blue8, v, 1);
        }
    }
    var tomato = new Color.rgb8 (255, 99, 71, 0.5);
    near (Vision.simulate (tomato, Deficiency.PROTANOPIA).a, 0.5, 1e-9);
    check_hex (Vision.simulate (tomato, Deficiency.NONE), tomato.to_hex ());
    for (int r = 0; r <= 255; r += 51) {
        for (int g = 0; g <= 255; g += 51) {
            for (int b = 0; b <= 255; b += 51) {
                var c = new Color.rgb8 (r, g, b);
                var mono = Vision.simulate (c, Deficiency.ACHROMATOPSIA);
                assert (mono.red8 == mono.green8 && mono.green8 == mono.blue8);
                near (mono.luminance (), c.luminance (), 0.01);
            }
        }
    }
    var red = hex ("#d62828");
    var green = hex ("#3a8a3a");
    double normal = red.delta_e (green);
    foreach (var d in new Deficiency[] { Deficiency.PROTANOPIA, Deficiency.DEUTERANOPIA }) {
        assert (Vision.simulate (red, d).delta_e (Vision.simulate (green, d)) < normal / 2);
    }
}

void test_vision_pixels () {
    uint8[] data = {};
    string[] colors = { "#ff0000", "#00ff00", "#0000ff", "#3584e4", "#e66100", "#2ec27e" };
    foreach (var h in colors) {
        var c = hex (h);
        data += (uint8) c.red8;
        data += (uint8) c.green8;
        data += (uint8) c.blue8;
        data += 200;
    }
    foreach (var d in Deficiency.all ()) {
        uint8[] copy = data;
        Vision.simulate_pixels (copy, 3, 2, 12, d);
        for (int i = 0; i < colors.length; i++) {
            var want = Vision.simulate (hex (colors[i]), d);
            near (copy[i * 4], want.red8, 1);
            near (copy[i * 4 + 1], want.green8, 1);
            near (copy[i * 4 + 2], want.blue8, 1);
            assert (copy[i * 4 + 3] == 200);
        }
    }
    foreach (var d in Deficiency.all ()) assert (Deficiency.from_id (d.id ()) == d);
    assert (Deficiency.from_id ("bogus") == Deficiency.NONE);
}

uint8[] image_of (string[] hexes, int[] counts, int width, out int height) {
    uint8[] data = {};
    int total = 0;
    for (int i = 0; i < hexes.length; i++) {
        var c = hex (hexes[i]);
        for (int n = 0; n < counts[i]; n++) {
            data += (uint8) c.red8;
            data += (uint8) c.green8;
            data += (uint8) c.blue8;
            data += 255;
            total++;
        }
    }
    height = total / width;
    assert (height * width == total);
    return data;
}

void test_extract_blocks () {
    int h;
    var data = image_of ({ "#d62828", "#1d3557", "#f1faee" }, { 500, 300, 200 }, 10, out h);
    var result = Extract.from_pixels (data, 10, h, 40, 8);
    assert (result.length == 3);
    check_hex (result[0].color, "#d62828");
    check_hex (result[1].color, "#1d3557");
    check_hex (result[2].color, "#f1faee");
    near (result[0].share, 0.5, 1e-9);
    near (result[1].share, 0.3, 1e-9);
    near (result[2].share, 0.2, 1e-9);
}

void test_extract_gradient () {
    int w = 256, h = 16;
    uint8[] data = new uint8[w * h * 4];
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            var c = Color.from_oklch (0.3 + 0.6 * x / (w - 1.0), 0.12, 360.0 * y / h);
            int i = (y * w + x) * 4;
            data[i] = (uint8) c.red8;
            data[i + 1] = (uint8) c.green8;
            data[i + 2] = (uint8) c.blue8;
            data[i + 3] = 255;
        }
    }
    for (int k = Extract.MIN_COLORS; k <= Extract.MAX_COLORS; k++) {
        var a = Extract.from_pixels (data, w, h, w * 4, k);
        var b = Extract.from_pixels (data, w, h, w * 4, k);
        assert (a.length == k);
        double sum = 0;
        for (int i = 0; i < a.length; i++) {
            assert (a[i].color.to_hex () == b[i].color.to_hex ());
            if (i > 0) assert (a[i - 1].share >= a[i].share);
            sum += a[i].share;
            for (int j = 0; j < i; j++) {
                double l1, a1, b1, l2, a2, b2;
                a[i].color.to_oklab (out l1, out a1, out b1);
                a[j].color.to_oklab (out l2, out a2, out b2);
                assert (Math.sqrt ((l1 - l2) * (l1 - l2) + (a1 - a2) * (a1 - a2) + (b1 - b2) * (b1 - b2)) > 0.015);
            }
        }
        near (sum, 1, 1e-9);
    }
    assert (Extract.from_pixels (data, w, h, w * 4, 40).length == Extract.MAX_COLORS);
    assert (Extract.from_pixels (data, w, h, w * 4, 1).length == Extract.MIN_COLORS);
}

void test_extract_edges () {
    uint8[] clear = new uint8[64 * 4];
    assert (Extract.from_pixels (clear, 8, 8, 32, 6).length == 0);
    int h;
    var data = image_of ({ "#ff8800", "#000000" }, { 60, 4 }, 8, out h);
    for (int i = 0; i < 4; i++) data[(60 + i) * 4 + 3] = 0;
    var r = Extract.from_pixels (data, 8, h, 32, 6);
    assert (r.length == 1);
    check_hex (r[0].color, "#ff8800");
    near (r[0].share, 1, 1e-9);
}

int utf16_count (string text) {
    int n = 1;
    unichar ch;
    int i = 0;
    while (text.get_next_char (ref i, out ch)) n += ch > 0xFFFF ? 2 : 1;
    return n;
}

PaletteDocument sample_doc () {
    var doc = new PaletteDocument ("Sunset Beach è 𝄞");
    doc.add (hex ("#d62828"), "Red");
    doc.add (hex ("#1d3557"), "Navy à");
    doc.add (hex ("#f1faee"), "Mint");
    doc.add (hex ("#000000"), "Black");
    doc.add (hex ("#fffffe"), "Almost White");
    return doc;
}

void same_colors (PaletteDocument a, PaletteDocument b, bool names) {
    assert (a.colors.size == b.colors.size);
    for (int i = 0; i < a.colors.size; i++) {
        assert (a.colors[i].to_hex () == b.colors[i].to_hex ());
        if (names && a.names[i] != b.names[i]) error ("name %s != %s", a.names[i], b.names[i]);
    }
}

void test_export_gpl () {
    try {
        var doc = sample_doc ();
        string text = PaletteFile.write_gpl (doc);
        assert (text.has_prefix ("GIMP Palette\nName: Sunset Beach"));
        assert ("214  40  40\tRed\n" in text);
        var back = PaletteFile.read (new Bytes (text.data), PaletteFormat.GPL);
        assert (back.name == doc.name);
        same_colors (doc, back, true);
        var gimp = PaletteFile.read_gpl ("GIMP Palette\r\nName: Test\r\nColumns: 4\r\n# a comment\r\n  0 128 255 Ocean Blue\r\n10 20 30\r\n");
        assert (gimp.name == "Test");
        assert (gimp.colors.size == 2);
        assert (gimp.names[0] == "Ocean Blue");
        check_hex (gimp.colors[1], "#0a141e");
        string[] bad = { "", "Not a palette\n", "GIMP Palette\n300 0 0 x\n", "GIMP Palette\n12 x 3\n" };
        foreach (var b in bad) {
            try {
                PaletteFile.read_gpl (b);
                assert_not_reached ();
            } catch (PaletteError e) {
            }
        }
    } catch (PaletteError e) {
        error ("%s", e.message);
    }
}

void test_export_ase () {
    try {
        var doc = sample_doc ();
        var bytes = PaletteFile.write_ase (doc);
        unowned uint8[] d = bytes.get_data ();
        assert (d[0] == 'A' && d[1] == 'S' && d[2] == 'E' && d[3] == 'F');
        assert (d[4] == 0 && d[5] == 1 && d[6] == 0 && d[7] == 0);
        assert (d[8] == 0 && d[9] == 0 && d[10] == 0 && d[11] == 7);
        assert (d[12] == 0xC0 && d[13] == 0x01);
        int expected = 12 + 6 + 2 + 2 * utf16_count (doc.name) + 6;
        for (int i = 0; i < doc.colors.size; i++) expected += 6 + 2 + 2 * utf16_count (doc.names[i]) + 4 + 12 + 2;
        assert (d.length == expected);
        var back = PaletteFile.read (bytes, PaletteFormat.ASE);
        assert (back.name == doc.name);
        same_colors (doc, back, true);
        uint8[] handmade = {
            'A', 'S', 'E', 'F', 0, 1, 0, 0, 0, 0, 0, 2,
            0, 1, 0, 0, 0, 26, 0, 3, 0, 'R', 0, 'd', 0, 0, 'R', 'G', 'B', ' ',
            0x3F, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2,
            0, 1, 0, 0, 0, 14, 0, 1, 0, 0, 'G', 'r', 'a', 'y', 0x3F, 0, 0, 0, 0, 2
        };
        var hand = PaletteFile.read_ase (new Bytes (handmade));
        assert (hand.colors.size == 2);
        assert (hand.names[0] == "Rd");
        check_hex (hand.colors[0], "#ff0000");
        check_hex (hand.colors[1], "#808080");
        uint8[] cut = d[0:d.length - 9];
        try {
            PaletteFile.read_ase (new Bytes (cut));
            assert_not_reached ();
        } catch (PaletteError e) {
        }
        try {
            PaletteFile.read_ase (new Bytes ("GIMP".data));
            assert_not_reached ();
        } catch (PaletteError e) {
        }
    } catch (PaletteError e) {
        error ("%s", e.message);
    }
}

void test_export_css () {
    try {
        var doc = sample_doc ();
        string css = PaletteFile.write_css (doc);
        assert (css.has_prefix (":root {\n  --sunset-beach-1: #d62828;\n"));
        assert (css.has_suffix ("}\n"));
        var back = PaletteFile.read (new Bytes (css.data), PaletteFormat.CSS);
        same_colors (doc, back, false);
        assert (back.names[0] == "sunset-beach-1");
        var other = PaletteFile.read_css (".x { --brand: rgb(10 20 30); --size: 12px; --accent:#fff }");
        assert (other.colors.size == 2);
        check_hex (other.colors[0], "#0a141e");
        check_hex (other.colors[1], "#ffffff");
        assert (PaletteFile.slug ("Sunset Beach!") == "sunset-beach");
        assert (PaletteFile.slug ("2024 photo") == "palette-2024-photo");
        assert (PaletteFile.slug ("èè") == "palette");
        try {
            PaletteFile.read_css ("body { color: red; }");
            assert_not_reached ();
        } catch (PaletteError e) {
        }
    } catch (PaletteError e) {
        error ("%s", e.message);
    }
}

void test_export_json () {
    try {
        var doc = sample_doc ();
        string json = PaletteFile.write_json (doc);
        var parser = new Json.Parser ();
        try {
            parser.load_from_data (json);
        } catch (Error e) {
            error ("%s", e.message);
        }
        var root = parser.get_root ().get_object ();
        assert (root.get_string_member ("name") == doc.name);
        var first = root.get_array_member ("colors").get_object_element (0);
        assert (first.get_string_member ("hex") == "#d62828");
        assert (first.get_array_member ("rgb").get_int_element (0) == 214);
        assert (first.get_string_member ("oklch").has_prefix ("oklch("));
        var back = PaletteFile.read (new Bytes (json.data), PaletteFormat.JSON);
        assert (back.name == doc.name);
        same_colors (doc, back, true);
        var plain = PaletteFile.read_json ("{\"colors\": [\"#123456\", \"tomato\"]}");
        check_hex (plain.colors[1], "#ff6347");
        string[] bad = { "[]", "{\"colors\": 3}", "{\"colors\": [\"nope\"]}", "{" };
        foreach (var b in bad) {
            try {
                PaletteFile.read_json (b);
                assert_not_reached ();
            } catch (PaletteError e) {
            }
        }
    } catch (PaletteError e) {
        error ("%s", e.message);
    }
}

void test_export_formats () {
    try {
        foreach (var f in PaletteFormat.all ()) {
            assert (PaletteFormat.from_id (f.id ()) == f);
            PaletteFormat got;
            assert (PaletteFormat.from_path ("/tmp/My Palette." + f.extension ().up (), out got));
            assert (got == f);
            var bytes = PaletteFile.write (sample_doc (), f);
            same_colors (sample_doc (), PaletteFile.read (bytes, f), f != PaletteFormat.CSS);
        }
        PaletteFormat none;
        assert (!PaletteFormat.from_path ("palette.txt", out none));
    } catch (PaletteError e) {
        error ("%s", e.message);
    }
}

void check_suggestion (Color fg, Color bg, double target) {
    var s = ContrastFix.suggest (fg, bg, target);
    near (s.before, Contrast.ratio (fg.over (bg), bg), 1e-9);
    if (s.already_passes) {
        assert (s.before >= target);
        assert (s.suggested.to_hex () == s.original.to_hex ());
        return;
    }
    assert (s.before < target);
    if (!s.found) {
        double l, c, h;
        s.original.to_oklch (out l, out c, out h);
        double black = Contrast.ratio (new Color (0, 0, 0), s.other);
        double white = Contrast.ratio (new Color (1, 1, 1), s.other);
        assert (double.max (black, white) < target + 0.2);
        return;
    }
    double ratio = Contrast.ratio (s.suggested, s.other);
    near (s.after, ratio, 1e-9);
    if (ratio < target) error ("%s on %s: %f < %f", s.suggested.to_hex (), s.other.to_hex (), ratio, target);
    double l0, c0, h0, l1, c1, h1;
    s.original.to_oklch (out l0, out c0, out h0);
    Color.from_oklch (s.lightness_after, c0, h0).to_oklch (out l1, out c1, out h1);
    if (s.chroma_kept) {
        s.suggested.to_oklch (out l1, out c1, out h1);
        near (c1, c0, 0.012);
        if (c0 > 0.05) {
            double dh = Math.fabs (h1 - h0);
            if (dh > 180) dh = 360 - dh;
            if (dh > 3) error ("hue drift %s to %s: %f", s.original.to_hex (), s.suggested.to_hex (), dh);
        }
        double dir = s.lightness_after > l0 ? 1 : -1;
        double back = s.lightness_after - dir * 0.01;
        if ((back - l0) * dir > 0 && ContrastFix.oklch_in_gamut (back, c0, h0)) {
            assert (Contrast.ratio (Color.from_oklch (back, c0, h0), s.other) < target);
        }
        double other_side = l0 - (s.lightness_after - l0);
        if (other_side > 0.01 && other_side < 0.99 && ContrastFix.oklch_in_gamut (other_side, c0, h0)) {
            double between_ok = 0;
            for (double t = l0; Math.fabs (t - l0) < Math.fabs (s.lightness_after - l0) - 0.01; t -= dir * 0.002) {
                if (!ContrastFix.oklch_in_gamut (t, c0, h0)) break;
                if (Contrast.ratio (Color.from_oklch (t, c0, h0), s.other) >= target) between_ok++;
            }
            assert (between_ok == 0);
        }
    }
}

void test_fix_known () {
    var s = ContrastFix.suggest (hex ("#777777"), hex ("#ffffff"), Contrast.AA);
    assert (!s.already_passes && s.found && s.chroma_kept);
    check_hex (s.suggested, "#767676");
    assert (Contrast.ratio (s.suggested, hex ("#ffffff")) >= 4.5);
    assert (Contrast.ratio (hex ("#777777"), hex ("#ffffff")) < 4.5);
    assert (s.lightness_after < s.lightness_before);

    var pass = ContrastFix.suggest (hex ("#000000"), hex ("#ffffff"), Contrast.AAA);
    assert (pass.already_passes && pass.found);

    var light = ContrastFix.suggest (hex ("#505050"), hex ("#202020"), Contrast.AA);
    assert (light.found && light.lightness_after > light.lightness_before);
    assert (Contrast.ratio (light.suggested, hex ("#202020")) >= 4.5);

    var gray_bg = ContrastFix.suggest (hex ("#3584e4"), hex ("#777777"), Contrast.AAA);
    assert (!gray_bg.found);

    var blue = ContrastFix.suggest (hex ("#3584e4"), hex ("#ffffff"), Contrast.AA);
    assert (blue.found && blue.chroma_kept);
    check_suggestion (hex ("#3584e4"), hex ("#ffffff"), Contrast.AA);

    var orange = ContrastFix.suggest (hex ("#e66100"), hex ("#ffffff"), Contrast.AA);
    assert (orange.found && !orange.chroma_kept);
    assert (Contrast.ratio (orange.suggested, hex ("#ffffff")) >= 4.5);
    double ol, oc, oh, sl, sc, sh;
    hex ("#e66100").to_oklch (out ol, out oc, out oh);
    orange.suggested.to_oklch (out sl, out sc, out sh);
    near (sh, oh, 3);
    assert (sc < oc && sc > oc * 0.85);

    near (ContrastFix.required (false, false), 4.5, 0);
    near (ContrastFix.required (true, false), 7, 0);
    near (ContrastFix.required (false, true), 3, 0);
    near (ContrastFix.required (true, true), 4.5, 0);
}

void test_fix_grid () {
    string[] fgs = { "#ff0000", "#00ff00", "#0000ff", "#ffff00", "#3584e4", "#e66100", "#2ec27e", "#9141ac", "#888888", "#c0bfbc", "#613583", "#f5c211" };
    string[] bgs = { "#ffffff", "#000000", "#241f31", "#f6f5f4", "#3584e4", "#ffa348", "#808080" };
    double[] targets = { Contrast.AA_LARGE, Contrast.AA, Contrast.AAA };
    int found = 0;
    foreach (var f in fgs) {
        foreach (var b in bgs) {
            foreach (var t in targets) {
                check_suggestion (hex (f), hex (b), t);
                var s = ContrastFix.suggest (hex (f), hex (b), t);
                if (s.found && !s.already_passes) found++;
            }
        }
    }
    assert (found > 100);
    check_suggestion (new Color.rgb8 (53, 132, 228, 0.6), hex ("#ffffff"), Contrast.AA);
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C");
    Test.init (ref args);
    Test.add_func ("/vision/reference", test_vision_reference);
    Test.add_func ("/vision/matrices", test_vision_matrices);
    Test.add_func ("/vision/properties", test_vision_properties);
    Test.add_func ("/vision/pixels", test_vision_pixels);
    Test.add_func ("/extract/blocks", test_extract_blocks);
    Test.add_func ("/extract/gradient", test_extract_gradient);
    Test.add_func ("/extract/edges", test_extract_edges);
    Test.add_func ("/export/gpl", test_export_gpl);
    Test.add_func ("/export/ase", test_export_ase);
    Test.add_func ("/export/css", test_export_css);
    Test.add_func ("/export/json", test_export_json);
    Test.add_func ("/export/formats", test_export_formats);
    Test.add_func ("/fix/known", test_fix_known);
    Test.add_func ("/fix/grid", test_fix_grid);
    return Test.run ();
}
