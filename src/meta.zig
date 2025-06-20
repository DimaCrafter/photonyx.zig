/// Returns comptime type name without namespace and number. Generics are not supported.
pub fn getSimpleTypeName(comptime T: type) []const u8 {
    comptime {
        const full: []const u8 = @typeName(T);

        var start = 0;
        for (0..full.len) |i| {
            if (full[i] == '.') {
                start = i + 1;
            }
        }

        var end = full.len;
        for (start + 1..full.len) |i| {
            if (full[i - 1] == '_' and full[i] == '_') {
                end = i - 1;
            }
        }

        // "" makes new comptime string
        return full[start..end] ++ "";
    }
}
