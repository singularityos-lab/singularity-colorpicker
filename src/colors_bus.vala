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
}
