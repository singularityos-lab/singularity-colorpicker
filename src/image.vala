namespace Singularity.Apps.ColorPicker {

    public class LoadedImage : Object {
        public const int MAX_SIDE = 1600;

        public string title { get; private set; }
        public string? path { get; private set; }
        public int source_width { get; private set; }
        public int source_height { get; private set; }
        public Gdk.Pixbuf pixbuf { get; private set; }

        private Gee.HashMap<string, Gdk.Texture> textures = new Gee.HashMap<string, Gdk.Texture> ();
        private Gee.HashMap<int, Gee.ArrayList<PaletteColor>> palettes = new Gee.HashMap<int, Gee.ArrayList<PaletteColor>> ();

        private LoadedImage (Gdk.Pixbuf source, string title, string? path, int width, int height) {
            var rgba = source.has_alpha ? source : source.add_alpha (false, 0, 0, 0);
            if (rgba.width > MAX_SIDE || rgba.height > MAX_SIDE) {
                double scale = (double) MAX_SIDE / int.max (rgba.width, rgba.height);
                rgba = rgba.scale_simple (int.max (1, (int) (rgba.width * scale)), int.max (1, (int) (rgba.height * scale)), Gdk.InterpType.BILINEAR);
            }
            pixbuf = rgba;
            this.title = title;
            this.path = path;
            source_width = width;
            source_height = height;
        }

        public static async LoadedImage load_file (File file, string? title = null, Cancellable? cancel = null) throws Error {
            string? local = file.get_path ();
            int w = 0, h = 0;
            bool known = local != null && Gdk.Pixbuf.get_file_info (local, out w, out h) != null;
            var stream = yield file.read_async (Priority.DEFAULT, cancel);
            Gdk.Pixbuf? pb;
            if (known && (w > MAX_SIDE || h > MAX_SIDE)) {
                pb = yield new Gdk.Pixbuf.from_stream_at_scale_async (stream, MAX_SIDE, MAX_SIDE, true, cancel);
            } else {
                pb = yield new Gdk.Pixbuf.from_stream_async (stream, cancel);
            }
            if (pb == null) throw new IOError.INVALID_DATA (_("The file is not an image."));
            var oriented = pb.apply_embedded_orientation () ?? pb;
            if (!known) {
                w = oriented.width;
                h = oriented.height;
            } else {
                bool wide = oriented.width > oriented.height;
                bool wide_source = w > h;
                if (wide != wide_source) {
                    int t = w;
                    w = h;
                    h = t;
                }
            }
            string name = title ?? file.get_basename () ?? _("Image");
            return new LoadedImage (oriented, name, local, w, h);
        }

        public static LoadedImage from_texture (Gdk.Texture texture, string title) throws Error {
            var downloader = new Gdk.TextureDownloader (texture);
            downloader.set_format (Gdk.MemoryFormat.R8G8B8A8);
            size_t stride;
            var bytes = downloader.download_bytes (out stride);
            if (texture.width <= 0 || texture.height <= 0) throw new IOError.INVALID_DATA (_("The image is empty."));
            var pb = new Gdk.Pixbuf.from_bytes (bytes, Gdk.Colorspace.RGB, true, 8, texture.width, texture.height, (int) stride);
            return new LoadedImage (pb, title, null, texture.width, texture.height);
        }

        public void remember_as (string file_path) throws Error {
            DirUtils.create_with_parents (Path.get_dirname (file_path), 0700);
            pixbuf.savev (file_path, "png", {}, {});
            path = file_path;
        }

        private uint8[] pixels_copy () {
            unowned uint8[] src = pixbuf.get_pixels_with_length ();
            uint8[] copy = new uint8[src.length];
            Memory.copy (copy, src, src.length);
            return copy;
        }

        public Gdk.Texture texture (Deficiency d) {
            var cached = textures[d.id ()];
            if (cached != null) return cached;
            uint8[] data = pixels_copy ();
            Vision.simulate_pixels (data, pixbuf.width, pixbuf.height, pixbuf.rowstride, d);
            var t = new Gdk.MemoryTexture (pixbuf.width, pixbuf.height, Gdk.MemoryFormat.R8G8B8A8, new Bytes (data), pixbuf.rowstride);
            textures[d.id ()] = t;
            return t;
        }

        public Gee.ArrayList<PaletteColor> palette (int count) {
            var cached = palettes[count];
            if (cached != null) return cached;
            unowned uint8[] data = pixbuf.get_pixels_with_length ();
            var list = new Gee.ArrayList<PaletteColor> ();
            foreach (var p in Extract.from_pixels (data, pixbuf.width, pixbuf.height, pixbuf.rowstride, count)) list.add (p);
            palettes[count] = list;
            return list;
        }
    }
}
