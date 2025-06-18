# 🌲 TrieNode — A Compressed Trie (Radix Tree) Implementation in Zig

`TrieNode` is a lightweight, allocator-aware radix tree (compressed trie) implementation written in [Zig](https://ziglang.org/). It supports insertion, lookup, and debug printing of hierarchical key/value structures, optimized for fast prefix-based operations.

---

## 📦 Features

* ✅ Compressed trie using shared key prefixes
* ✅ Generic data support via `comptime T`
* ✅ Recursive insertion with automatic node splitting
* ✅ Prefix-based lookup
* ✅ Debug printing with indentation
* ❌ No deletion (yet)
* ❌ Not thread-safe (single-threaded use only)

---

## 🔧 Installation

Just copy `trie.zig` into your project and import it:

```zig
const TrieNode = @import("trie.zig").TrieNode(i32); // or any type you need
```

---

## 🚀 Usage Example

```zig
const std = @import("std");
const TrieNode = @import("trie.zig").TrieNode(i32);

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var root = try TrieNode.init(allocator, "", null);
    defer root.deinit();

    try root.insert_node(try TrieNode.init(allocator, "apple", 10));
    try root.insert_node(try TrieNode.init(allocator, "app", null));
    try root.insert_node(try TrieNode.init(allocator, "banana", 42));

    // Lookup
    if (root.lookup("apple")) |value| {
        std.debug.print("Found: {}\n", .{value});
    }

    // Debug print (for development only)
    try root.debug_print(0);
}
```

---

## 📘 API Overview

### `init(allocator, key, data)`

Creates a new node with the given key and optional value.

### `insert_node(node)`

Inserts another node into the trie, automatically managing prefix collisions.

### `lookup(path)`

Looks up a value by its full path (e.g., `"apple"`). Returns `?T`.

### `deinit()`

Frees all memory allocated by the node and its children. Only call this on the **root** node.

### `debug_print(indent)`

Prints the trie structure to `stdout`. For development/debugging only.

---

## ⚠️ Limitations

* `key` must not be empty for any inserted node (except the root).
* Keys must be unique — inserting the same key twice returns an error.
* This is not a concurrent data structure; use it in single-threaded contexts only.

---

## 🧪 Testing

Use Zig’s native test runner:

```sh
zig test trie.zig
```

Or integrate tests directly into your app using `std.testing`.

---

## 📄 License

MIT — free to use, modify, and share.
