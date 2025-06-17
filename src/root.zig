const std = @import("std");

/// # TrieNode
/// Represents a single node in a **Trie** or **Radix Tree** data structure.
///
/// A Trie (pronounced "try") — also known as a prefix tree — is a specialized
/// tree-based data structure used to store associative data where the keys are
/// usually strings.
///
/// Instead of storing keys in a single node (like in a hash map), a trie splits
/// keys into characters and distributes them across a series of connected nodes.
/// Each node represents a prefix of the key, and the complete key is formed by
/// walking from the root to a leaf.
///
/// ## Examples
/// ```zig
/// const allocator = std.heap.page_allocator;
/// var root = try TrieNode.init(allocator, "", null);
/// defer root.deinit(); // make sure memory freed
///
/// try root.insert_node(try TrieNode.init(allocator, "app", null));
/// try root.insert_node(try TrieNode.init(allocator, "apple", 100));
/// try root.insert_node(try TrieNode.init(allocator, "banana", 42));
/// try root.insert_node(try TrieNode.init(allocator, "band", 17));
/// try root.insert_node(try TrieNode.init(allocator, "bandana", 8));
/// ```
pub fn TrieNode(comptime T: type) type {
    return struct {
        const Self = @This();

        /// ## `allocator`
        /// Allocator used for auto memory management
        allocator: std.mem.Allocator,

        /// ## `key`
        /// Key or prefix is a portion of the key string associated with this node.
        key: []const u8,

        /// ## `data`
        /// Optional value of type `T`, stored if this node represents a complete key.
        data: ?T,

        /// ## `childs`
        /// A list of child nodes continuing the key path.
        childs: std.ArrayList(*TrieNode(T)),

        /// ## `init`
        /// Constructor method initialize a new `RadixNode` instance returning
        /// pointer to `RadixNode`
        pub fn init(
            allocator: std.mem.Allocator,
            key: []const u8,
            data: ?T,
        ) !*Self {
            const childs = std.ArrayList(*Self).init(allocator);
            const self = try allocator.create(Self);
            self.* = Self{
                .allocator = allocator,
                .childs = childs,
                .key = key,
                .data = data,
            };
            return self;
        }

        /// ## `deinit`
        /// Frees all memory owned by this trie node and its children.
        ///
        /// This function should **only be called on the root (head) node**.
        /// It will recursively deallocate all child nodes in the trie.
        ///
        /// ### Why only the root?
        /// Each node is responsible for deinitializing its own children.
        /// Therefore, calling `deinit` on the root node ensures the entire
        /// tree is cleaned up without needing to traverse or manually deinit
        /// each node individually.
        ///
        /// ⚠️ **Do not call `deinit` on inner or child nodes separately**, as that would
        /// result in double-free or dangling pointers if the root is also deinitialized.
        ///
        /// ### Example
        /// ```zig
        /// var root = try TrieNode(i32).init(allocator, "", null);
        /// defer root.deinit(); // safe: cleans up the entire trie
        /// ```
        pub fn deinit(self: *Self) void {
            for (self.childs.items) |child| {
                child.deinit();
            }
            self.childs.deinit();
            self.allocator.destroy(self);
        }

        /// ## `getPrefixLen`
        /// Computes the common prefix length between two nodes' keys.
        ///
        /// This helper function compares the `key` fields of two nodes
        /// and returns the number of bytes they share from the beginning
        /// (i.e., their common prefix length).
        ///
        /// This function is used internally during insertion and splitting
        /// to determine how much of the path is shared between two nodes.
        ///
        /// ### Parameters
        /// - `node1`: The first node to compare.
        /// - `node2`: The second node to compare.
        ///
        /// ### Returns
        /// The length of the common prefix between `node1.key` and `node2.key`.
        ///
        /// ### Note
        /// This function is **private** and not intended to be exposed
        /// as part of the public API.
        fn getPrefixLen(_: *Self, node1: *Self, node2: *Self) usize {
            var prefix_len: usize = 0;
            const min_len = @min(node1.key.len, node2.key.len);
            while (prefix_len < min_len and node1.key[prefix_len] == node2.key[prefix_len]) {
                prefix_len += 1;
            }
            return prefix_len;
        }

        /// ## `insert_node`
        /// Inserts a new node into the trie, handling recursive traversal, prefix matching, and structural reorganization.
        ///
        /// This is the main insertion function for the radix trie structure. It recursively finds
        /// the correct location to insert a new node based on key prefix similarity. It handles:
        /// - Traversal to matching child nodes.
        /// - Partial prefix matches, requiring node splitting.
        /// - Exact key collisions (errors).
        /// - Creating new intermediate parent nodes when necessary.
        ///
        /// ### Parameters
        /// - `node`: A pointer to the `TrieNode` to be inserted. The node must be pre-initialized
        ///   with a valid `key` (non-empty) and allocator.
        ///
        /// ### Behavior
        /// - If there are no children, the node is inserted directly.
        /// - If a child with matching prefix is found:
        ///   - If both keys are equal in length and content → error `NonUniqueChildren`.
        ///   - If `child.key` is fully matched → recurse into child with remaining `node.key`.
        ///   - If `node.key` is fully matched → node becomes parent of the child.
        ///   - If both keys are partially matched → create a new intermediate node (split).
        /// - If no child matches any prefix → node is appended to the children list.
        ///
        /// ### Errors
        /// - `ZeroKeyLength`: When the node to be inserted has an empty key.
        /// - `NonUniqueChildren`: When a node with the exact same key already exists.
        /// - Allocation errors if any dynamic array (children list) needs to grow.
        ///
        /// ### Notes
        /// - The `node.key` may be mutated (shortened) during insertion to reflect relative key positions.
        /// - Existing child keys may also be mutated if they are split and moved under a new parent node.
        /// - This function maintains trie validity and compression at each step.
        ///
        /// ### Example
        /// ```zig
        /// var new_node = try TrieNode(i32).init(allocator, "can", 123);
        /// try root.insert_node(new_node);
        /// ```
        ///
        /// ### Internal Invariants Maintained
        /// - No two children under the same node will share the same prefix.
        /// - All nodes correctly represent disjoint prefix spaces.
        /// - Tree structure stays compressed after every insertion.
        pub fn insert_node(self: *Self, node: *Self) !void {
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
                        try child.insert_node(node);
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
                        const new_parrent = try Self.init(self.allocator, node.key[0..prefix_len], null);
                        var temp_self_childs = self.childs.items[idx];
                        self.childs.items[idx] = new_parrent;
                        node.key = node.key[prefix_len..];
                        temp_self_childs.key = temp_self_childs.key[prefix_len..];
                        try self.childs.items[idx].insert_node(node);
                        try self.childs.items[idx].insert_node(temp_self_childs);
                    }
                }
            }
        }

        /// ## `lookup`
        /// Recursively searches for a value in the trie based on a given path.
        ///
        /// This function attempts to find the stored value of type `T` associated
        /// with a given `path` (usually a string or byte slice) by traversing the trie.
        /// It performs prefix-based matching at each node level and recurses down
        /// the matching child if applicable.
        ///
        /// ### Parameters
        /// - `path`: The input key to search for, represented as a `[]const u8`.
        ///
        /// ### Behavior
        /// - For each child of the current node:
        ///   - If the child's key is longer than the remaining path, it skips that child.
        ///   - If the path exactly equals the child’s key, it returns the associated data.
        ///   - If the child’s key is a prefix of the path, it recurses into that child
        ///     with the remaining part of the path.
        /// - If no matching child is found, it returns `null`.
        ///
        /// ### Return
        /// - Returns `?T`: the value associated with the path if found, otherwise `null`.
        ///
        /// ### Example
        /// ```zig
        /// const value = root.lookup("carrot");
        /// if (value) |v| {
        ///     std.debug.print("Found value: {}\n", .{v});
        /// } else {
        ///     std.debug.print("Not found\n", .{});
        /// }
        /// ```
        ///
        /// ### Notes
        /// - This function performs exact prefix matching, not substring or fuzzy search.
        /// - It does **not** match partial keys unless they completely cover the prefix
        ///   of a child node.
        /// - Ensure the trie has been populated correctly with `insert_node` before using `lookup`.
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

        /// # `debug_print`
        /// Recursively prints the structure of the trie for debugging purposes.
        ///
        /// This function is used to visualize the contents of the trie in a
        /// human-readable format. It prints each node's key and associated data
        /// with indentation to reflect the hierarchy of the trie.
        ///
        /// It should **only be used in development/debug mode**, as it performs
        /// allocations and outputs directly to the debug console.
        ///
        /// ### Parameters
        /// - `indent`: The number of spaces to indent the current node’s output.
        ///   This value increases recursively for child nodes.
        ///
        /// ### Output Format
        /// - Each line contains the node's key, its associated data (if any), and is indented
        ///   according to its depth in the trie.
        ///
        /// Example output:
        /// ```
        /// root: null
        ///     ap: null
        ///         ple: 10
        ///     ba: null
        ///         nana: 42
        /// ```
        ///
        /// ### Errors
        /// - Returns an error if memory allocation for the indentation string fails.
        ///
        /// ### Safety and Performance
        /// - This function allocates a temporary buffer for each indentation level,
        ///   which is immediately freed after printing.
        /// - Avoid using this in production builds due to unnecessary heap allocations
        ///   and debug output.
        ///
        /// ### Example (development only)
        /// ```zig
        /// try root.debug_print(0);
        /// ```
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
    var node = try TrieNode([]const u8).init(allocator, "node", "data");
    defer node.deinit();
}

test "insert node" {
    const allocator = std.testing.allocator;
    var head = try TrieNode([]const u8).init(allocator, "/", null);
    defer head.deinit();

    const user_router = try TrieNode([]const u8).init(allocator, "api/v1/users", "users handlers");
    const user_login_router = try TrieNode([]const u8).init(allocator, "api/v1/users/auth/login", "users login handlers");
    const user_router_v2 = try TrieNode([]const u8).init(allocator, "api/v2/users", "users handlers v2");
    const auth_router = try TrieNode([]const u8).init(allocator, "api/v1/auth", "auth handlers");

    try head.insert_node(user_router);
    try head.insert_node(user_router_v2);
    try head.insert_node(auth_router);
    try head.insert_node(user_login_router);
    try head.debug_print(0);

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
