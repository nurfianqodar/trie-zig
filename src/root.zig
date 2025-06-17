const std = @import("std");
pub fn TrieNode(comptime T: type) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        key: []const u8,
        data: ?T,
        childs: std.ArrayList(*TrieNode(T)),
        terminator: bool,

        pub fn init(
            allocator: std.mem.Allocator,
            key: []const u8,
            data: ?T,
            terminator: bool,
        ) !*Self {
            const childs = std.ArrayList(*Self).init(allocator);
            const self = try allocator.create(Self);
            self.* = Self{
                .allocator = allocator,
                .childs = childs,
                .key = key,
                .data = data,
                .terminator = terminator,
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            for (self.childs.items) |child| {
                child.deinit();
            }
            self.childs.deinit();
            self.allocator.destroy(self);
        }

        pub fn getPrefixLen(_: *Self, node1: *Self, node2: *Self) usize {
            var prefix_len: usize = 0;

            const min_len = @min(node1.key.len, node2.key.len);

            while (prefix_len < min_len and node1.key[prefix_len] == node2.key[prefix_len]) {
                prefix_len += 1;
            }

            return prefix_len;
        }

        pub fn insert(self: *Self, node: *Self) !void {
            if (self.childs.items.len == 0) {
                try self.childs.append(node);
                return;
            }

            for (self.childs.items, 0..) |child, idx| {
                // Error jika key merupakan string literal kosong
                if (node.key.len == 0) {
                    return error.ZeroKeyLength;
                }

                // Mendapatkan panjang prefix
                const prefix_len = self.getPrefixLen(child, node);

                if (prefix_len == 0) {

                    // Jika panjang prefix 0
                    if (idx == self.childs.items.len - 1) {
                        // Jika semua child telah diperiksa
                        try self.childs.append(node);
                    } else {

                        // Lanjut saat prefix 0 dan belum semua child diperiksa
                        continue;
                    }
                } else {
                    // Jika prefix ditemukan

                    if ((child.key.len == prefix_len) and (node.key.len == prefix_len)) {
                        // error jika key tidak unik
                        node.deinit();
                        return error.NonUniqueChildren;
                    } else if (child.key.len == prefix_len) {
                        // saat prefix sama dengan child pada parent
                        node.key = node.key[prefix_len..];
                        try child.insert(node);
                        return;
                    } else if (node.key.len == prefix_len) {
                        // saat prefix sama dengan node yang dimasukkan
                        var temp_self_childs = self.childs.items[idx];
                        temp_self_childs.key = temp_self_childs.key[prefix_len..];
                        try node.childs.append(temp_self_childs);
                        self.childs.items[idx] = node;
                    } else {
                        // buat parent baru untuk child pada parent dan node
                        // key keduanya lebih panjang dari prefix
                        const new_parrent = try Self.init(self.allocator, node.key[0..prefix_len], null, false);
                        var temp_self_childs = self.childs.items[idx];
                        self.childs.items[idx] = new_parrent;
                        node.key = node.key[prefix_len..];
                        temp_self_childs.key = temp_self_childs.key[prefix_len..];
                        try self.childs.items[idx].insert(node);
                        try self.childs.items[idx].insert(temp_self_childs);
                    }
                }
            }
        }

        pub fn lookup(self: *const Self, path: []const u8) ?T {
            for (self.childs.items) |child| {
                if (path.len < child.key.len) {
                    continue;
                }

                if (std.mem.eql(u8, child.key, path)) {
                    return child.data;
                }

                if (std.mem.eql(u8, child.key, path[0..child.key.len])) {
                    return child.lookup(path[child.key.len..]);
                }
            }
            return null;
        }

        pub fn debug_print(self: *Self, indent: usize) !void {
            const indent_str = try self.allocator.alloc(u8, indent);
            defer self.allocator.free(indent_str);
            @memset(indent_str[0..], ' ');
            std.debug.print("{s}{s}: {?s}\n", .{ indent_str, self.key, self.data });
            for (self.childs.items) |child| {
                try child.debug_print(indent + 4);
            }
        }
    };
}

test "init data" {
    const allocator = std.testing.allocator;
    var node = try TrieNode([]const u8).init(allocator, "node", "data", false);
    defer node.deinit();
}

test "insert node" {
    const allocator = std.testing.allocator;
    var head = try TrieNode([]const u8).init(allocator, "/", null, true);
    defer head.deinit();

    const user_router = try TrieNode([]const u8).init(allocator, "api/v1/users", "users handlers", true);
    const user_router_v2 = try TrieNode([]const u8).init(allocator, "api/v2/users", "users handlers v2", true);
    const auth_router = try TrieNode([]const u8).init(allocator, "api/v1/auth", "auth handlers", true);

    try head.insert(user_router);
    try head.insert(user_router_v2);
    try head.insert(auth_router);

    if (head.lookup("api/v1/auth")) |data| {
        try std.testing.expectEqual("auth handlers", data);
    } else {
        try std.testing.expect(false);
    }

    if (head.lookup("api/v1/users")) |data| {
        try std.testing.expectEqual("users handlers", data);
    } else {
        try std.testing.expect(false);
    }

    if (head.lookup("api/v2/users")) |data| {
        try std.testing.expectEqual("users handlers v2", data);
    } else {
        try std.testing.expect(false);
    }
}
