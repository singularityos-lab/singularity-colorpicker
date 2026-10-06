namespace Singularity.Apps.ColorPicker {

    public errordomain PaletteError {
        INVALID
    }

    public enum PaletteFormat {
        GPL,
        ASE,
        CSS,
        JSON;

        public string id () {
            switch (this) {
                case ASE: return "ase";
                case CSS: return "css";
                case JSON: return "json";
                default: return "gpl";
            }
        }

        public string extension () {
            return id ();
        }

        public string label () {
            switch (this) {
                case ASE: return _("Adobe Swatch Exchange");
                case CSS: return _("CSS Custom Properties");
                case JSON: return _("JSON");
                default: return _("GIMP Palette");
            }
        }

        public string mime_type () {
            switch (this) {
                case ASE: return "application/x-adobe-ase";
                case CSS: return "text/css";
                case JSON: return "application/json";
                default: return "application/x-gimp-palette";
            }
        }

        public static PaletteFormat from_id (string id) {
            foreach (var f in all ()) if (f.id () == id) return f;
            return GPL;
        }

        public static bool from_path (string path, out PaletteFormat format) {
            format = GPL;
            string lower = path.down ();
            foreach (var f in all ()) {
                if (lower.has_suffix ("." + f.extension ())) {
                    format = f;
                    return true;
                }
            }
            return false;
        }

        public static PaletteFormat[] all () {
            return { GPL, ASE, CSS, JSON };
        }
    }

    public class PaletteDocument : Object {
        public string name;
        public Gee.ArrayList<Color> colors = new Gee.ArrayList<Color> ();
        public Gee.ArrayList<string> names = new Gee.ArrayList<string> ();

        public PaletteDocument (string name) {
            this.name = name;
        }

        public void add (Color c, string? label = null) {
            colors.add (new Color (c.r, c.g, c.b));
            names.add (label ?? c.to_hex ());
        }
    }

    namespace PaletteFile {
        public string slug (string text) {
            var sb = new StringBuilder ();
            bool dash = false;
            unichar ch;
            int i = 0;
            while (text.down ().get_next_char (ref i, out ch)) {
                if ((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9')) {
                    if (dash && sb.len > 0) sb.append_c ('-');
                    sb.append_unichar (ch);
                    dash = false;
                } else {
                    dash = true;
                }
            }
            if (sb.len == 0) return "palette";
            if (sb.str[0].isdigit ()) return "palette-" + sb.str;
            return sb.str;
        }

        public Bytes write (PaletteDocument doc, PaletteFormat format) {
            switch (format) {
                case PaletteFormat.ASE: return write_ase (doc);
                case PaletteFormat.CSS: return new Bytes (write_css (doc).data);
                case PaletteFormat.JSON: return new Bytes (write_json (doc).data);
                default: return new Bytes (write_gpl (doc).data);
            }
        }

        public PaletteDocument read (Bytes data, PaletteFormat format) throws PaletteError {
            switch (format) {
                case PaletteFormat.ASE: return read_ase (data);
                case PaletteFormat.CSS: return read_css (text_of (data));
                case PaletteFormat.JSON: return read_json (text_of (data));
                default: return read_gpl (text_of (data));
            }
        }

        private string text_of (Bytes data) throws PaletteError {
            var sb = new StringBuilder.sized (data.get_size () + 1);
            sb.append_len ((string) data.get_data (), (ssize_t) data.get_size ());
            if (!sb.str.validate ()) throw new PaletteError.INVALID (_("The file is not valid text."));
            return sb.str;
        }

        private string clean_name (string name) {
            return name.replace ("\n", " ").replace ("\r", " ").replace ("\t", " ").strip ();
        }

        public string write_gpl (PaletteDocument doc) {
            var sb = new StringBuilder ("GIMP Palette\n");
            sb.append ("Name: %s\n".printf (clean_name (doc.name)));
            sb.append ("Columns: %d\n".printf (int.min (int.max (doc.colors.size, 1), 16)));
            sb.append ("#\n");
            for (int i = 0; i < doc.colors.size; i++) {
                var c = doc.colors[i];
                sb.append ("%3d %3d %3d\t%s\n".printf (c.red8, c.green8, c.blue8, clean_name (doc.names[i])));
            }
            return sb.str;
        }

        public PaletteDocument read_gpl (string text) throws PaletteError {
            string[] lines = text.replace ("\r\n", "\n").replace ("\r", "\n").split ("\n");
            if (lines.length == 0 || lines[0].strip () != "GIMP Palette") {
                throw new PaletteError.INVALID (_("This is not a GIMP palette."));
            }
            var doc = new PaletteDocument ("");
            for (int i = 1; i < lines.length; i++) {
                string line = lines[i].strip ();
                if (line == "" || line.has_prefix ("#")) continue;
                if (line.has_prefix ("Name:")) {
                    doc.name = line.substring (5).strip ();
                    continue;
                }
                if (line.has_prefix ("Columns:")) continue;
                int[] rgb = {};
                int pos = 0;
                while (rgb.length < 3) {
                    while (pos < line.length && (line[pos] == ' ' || line[pos] == '\t')) pos++;
                    int start = pos;
                    while (pos < line.length && line[pos].isdigit ()) pos++;
                    if (pos == start) throw new PaletteError.INVALID (_("Line %d of the palette is not a color.").printf (i + 1));
                    int v = int.parse (line.substring (start, pos - start));
                    if (v > 255) throw new PaletteError.INVALID (_("Line %d of the palette is out of range.").printf (i + 1));
                    rgb += v;
                }
                string label = line.substring (pos).strip ();
                var c = new Color.rgb8 (rgb[0], rgb[1], rgb[2]);
                doc.add (c, label != "" ? label : c.to_hex ());
            }
            return doc;
        }

        public string write_css (PaletteDocument doc) {
            string prefix = slug (doc.name);
            var sb = new StringBuilder (":root {\n");
            for (int i = 0; i < doc.colors.size; i++) {
                sb.append ("  --%s-%d: %s;\n".printf (prefix, i + 1, doc.colors[i].to_hex ()));
            }
            sb.append ("}\n");
            return sb.str;
        }

        public PaletteDocument read_css (string text) throws PaletteError {
            var doc = new PaletteDocument ("");
            MatchInfo info;
            try {
                var re = new Regex ("--([A-Za-z0-9_-]+)\\s*:\\s*([^;}]+)");
                if (re.match (text, 0, out info)) {
                    do {
                        var c = Parser.parse (info.fetch (2).strip ());
                        if (c == null) continue;
                        doc.add (c, info.fetch (1));
                    } while (info.next ());
                }
            } catch (RegexError e) {
                throw new PaletteError.INVALID (e.message);
            }
            if (doc.colors.size == 0) throw new PaletteError.INVALID (_("No color custom properties were found."));
            return doc;
        }

        public string write_json (PaletteDocument doc) {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("name");
            b.add_string_value (doc.name);
            b.set_member_name ("colors");
            b.begin_array ();
            for (int i = 0; i < doc.colors.size; i++) {
                var c = doc.colors[i];
                b.begin_object ();
                b.set_member_name ("name");
                b.add_string_value (doc.names[i]);
                b.set_member_name ("hex");
                b.add_string_value (c.to_hex ());
                b.set_member_name ("rgb");
                b.begin_array ();
                b.add_int_value (c.red8);
                b.add_int_value (c.green8);
                b.add_int_value (c.blue8);
                b.end_array ();
                b.set_member_name ("oklch");
                b.add_string_value (Formatter.format (c, Format.OKLCH));
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
            var gen = new Json.Generator ();
            gen.pretty = true;
            gen.set_root (b.get_root ());
            return gen.to_data (null) + "\n";
        }

        public PaletteDocument read_json (string text) throws PaletteError {
            var parser = new Json.Parser ();
            try {
                parser.load_from_data (text);
            } catch (Error e) {
                throw new PaletteError.INVALID (e.message);
            }
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                throw new PaletteError.INVALID (_("The JSON file does not hold a palette."));
            }
            var obj = root.get_object ();
            var doc = new PaletteDocument (obj.has_member ("name") ? (obj.get_string_member_with_default ("name", "")) : "");
            if (!obj.has_member ("colors") || obj.get_member ("colors").get_node_type () != Json.NodeType.ARRAY) {
                throw new PaletteError.INVALID (_("The JSON file does not hold a palette."));
            }
            foreach (var node in obj.get_array_member ("colors").get_elements ()) {
                Color? c = null;
                string? label = null;
                if (node.get_node_type () == Json.NodeType.OBJECT) {
                    var item = node.get_object ();
                    c = Color.from_hex (item.get_string_member_with_default ("hex", ""));
                    label = item.get_string_member_with_default ("name", "");
                } else if (node.get_value_type () == typeof (string)) {
                    c = Parser.parse (node.get_string ());
                }
                if (c == null) throw new PaletteError.INVALID (_("The JSON palette holds a value that is not a color."));
                doc.add (c, label != null && label != "" ? label : c.to_hex ());
            }
            return doc;
        }

        private const uint16 ASE_COLOR = 0x0001;
        private const uint16 ASE_GROUP_START = 0xC001;
        private const uint16 ASE_GROUP_END = 0xC002;

        private uint16[] utf16_units (string text) {
            uint16[] units = {};
            unichar ch;
            int i = 0;
            while (text.get_next_char (ref i, out ch)) {
                if (ch > 0xFFFF) {
                    uint v = ch - 0x10000;
                    units += (uint16) (0xD800 + (v >> 10));
                    units += (uint16) (0xDC00 + (v & 0x3FF));
                } else {
                    units += (uint16) ch;
                }
            }
            units += 0;
            return units;
        }

        private void put_u16 (ByteArray out_b, uint16 v) {
            uint8[] b = { (uint8) (v >> 8), (uint8) (v & 0xFF) };
            out_b.append (b);
        }

        private void put_u32 (ByteArray out_b, uint32 v) {
            uint8[] b = { (uint8) (v >> 24), (uint8) ((v >> 16) & 0xFF), (uint8) ((v >> 8) & 0xFF), (uint8) (v & 0xFF) };
            out_b.append (b);
        }

        private void put_f32 (ByteArray out_b, float f) {
            uint32 bits = 0;
            Memory.copy (&bits, &f, sizeof (uint32));
            put_u32 (out_b, bits);
        }

        private void put_name (ByteArray out_b, string name) {
            var units = utf16_units (name);
            put_u16 (out_b, (uint16) units.length);
            foreach (var u in units) put_u16 (out_b, u);
        }

        private void put_block (ByteArray out_b, uint16 type, ByteArray body) {
            put_u16 (out_b, type);
            put_u32 (out_b, body.len);
            out_b.append (body.data);
        }

        public Bytes write_ase (PaletteDocument doc) {
            var out_b = new ByteArray ();
            out_b.append ("ASEF".data);
            put_u16 (out_b, 1);
            put_u16 (out_b, 0);
            put_u32 (out_b, doc.colors.size + 2);
            var group = new ByteArray ();
            put_name (group, doc.name);
            put_block (out_b, ASE_GROUP_START, group);
            for (int i = 0; i < doc.colors.size; i++) {
                var c = doc.colors[i];
                var body = new ByteArray ();
                put_name (body, doc.names[i]);
                body.append ("RGB ".data);
                put_f32 (body, (float) (c.red8 / 255.0));
                put_f32 (body, (float) (c.green8 / 255.0));
                put_f32 (body, (float) (c.blue8 / 255.0));
                put_u16 (body, 2);
                put_block (out_b, ASE_COLOR, body);
            }
            put_block (out_b, ASE_GROUP_END, new ByteArray ());
            return ByteArray.free_to_bytes ((owned) out_b);
        }

        private class Reader {
            private unowned uint8[] data;
            public size_t pos;
            public size_t end;

            public Reader (uint8[] data) {
                this.data = data;
                pos = 0;
                end = data.length;
            }

            public void need (size_t n) throws PaletteError {
                if (pos + n > end) throw new PaletteError.INVALID (_("The swatch file is cut short."));
            }

            public uint16 u16 () throws PaletteError {
                need (2);
                uint16 v = (uint16) ((data[pos] << 8) | data[pos + 1]);
                pos += 2;
                return v;
            }

            public uint32 u32 () throws PaletteError {
                need (4);
                uint32 v = ((uint32) data[pos] << 24) | ((uint32) data[pos + 1] << 16) | ((uint32) data[pos + 2] << 8) | data[pos + 3];
                pos += 4;
                return v;
            }

            public float f32 () throws PaletteError {
                uint32 bits = u32 ();
                float f = 0;
                Memory.copy (&f, &bits, sizeof (float));
                return f;
            }

            public string tag () throws PaletteError {
                need (4);
                var sb = new StringBuilder ();
                for (int i = 0; i < 4; i++) sb.append_c ((char) data[pos + i]);
                pos += 4;
                return sb.str;
            }

            public string name () throws PaletteError {
                uint16 count = u16 ();
                var sb = new StringBuilder ();
                for (int i = 0; i < count; i++) {
                    uint16 u = u16 ();
                    if (u == 0) continue;
                    if (u >= 0xD800 && u < 0xDC00 && i + 1 < count) {
                        uint16 low = u16 ();
                        i++;
                        sb.append_unichar ((unichar) (0x10000 + ((u - 0xD800) << 10) + (low - 0xDC00)));
                    } else {
                        sb.append_unichar ((unichar) u);
                    }
                }
                return sb.str;
            }
        }

        public PaletteDocument read_ase (Bytes bytes) throws PaletteError {
            unowned uint8[] data = bytes.get_data ();
            var r = new Reader (data);
            if (data.length < 12 || r.tag () != "ASEF") throw new PaletteError.INVALID (_("This is not an Adobe swatch file."));
            r.u16 ();
            r.u16 ();
            uint32 blocks = r.u32 ();
            var doc = new PaletteDocument ("");
            for (uint32 i = 0; i < blocks; i++) {
                uint16 type = r.u16 ();
                uint32 length = r.u32 ();
                r.need (length);
                size_t block_end = r.pos + length;
                if (type == ASE_GROUP_START) {
                    string group = r.name ();
                    if (doc.name == "") doc.name = group;
                } else if (type == ASE_COLOR) {
                    string label = r.name ();
                    string model = r.tag ();
                    Color c;
                    switch (model) {
                        case "RGB ":
                            float cr = r.f32 (), cg = r.f32 (), cb = r.f32 ();
                            c = new Color (cr, cg, cb);
                            break;
                        case "CMYK":
                            float cc = r.f32 (), cm = r.f32 (), cy = r.f32 (), ck = r.f32 ();
                            c = Color.from_cmyk (cc, cm, cy, ck);
                            break;
                        case "Gray":
                            float gray = r.f32 ();
                            c = new Color (gray, gray, gray);
                            break;
                        case "LAB ":
                            float ll = r.f32 (), la = r.f32 (), lb = r.f32 ();
                            c = Color.from_lab (ll * 100, la, lb);
                            break;
                        default:
                            throw new PaletteError.INVALID (_("The swatch file uses an unknown color model."));
                    }
                    doc.add (c, label != "" ? label : c.to_hex ());
                }
                if (r.pos > block_end) throw new PaletteError.INVALID (_("The swatch file has a damaged block."));
                r.pos = block_end;
            }
            if (doc.colors.size == 0) throw new PaletteError.INVALID (_("The swatch file holds no colors."));
            return doc;
        }
    }
}
