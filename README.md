# nclip2-lib

Cross-platform clipboard library for Zig supporting Wayland, X11, and macOS.

## Features

- **Cross-platform**: Native support for Wayland, X11, and macOS
- **Multiple formats**: Text, images (PNG/JPEG/AVIF/WebP/JXL/TIFF/GIF/BMP), HTML, and RTF
- **Automatic format detection**: Smart format priority with single-request optimization
- **Background persistence**: X11 clipboard data persists after process exit (like xclip)
- **Memory safe**: Proper memory management with allocator pattern
- **Zero dependencies**: Uses only system libraries
- **Clean API**: Simplified interface with cross-platform compatibility

## Supported Platforms

| Platform | Backend | Status | Notes |
|----------|---------|--------|-------|
| Linux (Wayland) | libwayland-client + wlr-data-control | Fully Supported | Event-based monitoring available |
| Linux (X11) | libX11 | Fully Supported | Background serving with fork |
| macOS | AppKit/Foundation + pbcopy/pbpaste | Fully Supported | Text and image clipboard support |
| Other | Fallback | Unsupported | Returns UnsupportedPlatform error |

## Quick Start

### Simple Reading and Writing
```zig
const std = @import("std");
const clipboard = @import("clipboard");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Write text to clipboard (cross-platform)
    try clipboard.writeClipboardText(allocator, "Hello from nclip2!");
    
    // Read clipboard data with automatic format detection
    var data = try clipboard.readClipboardData(allocator);
    defer data.deinit();
    
    switch (data.format) {
        .text => {
            const text = try data.asText();
            std.log.info("Text: {s}", .{text});
        },
        .image => {
            std.log.info("Image: {} bytes", .{data.data.len});
        },
        .html => {
            std.log.info("HTML: {} bytes", .{data.data.len});
        },
        .rtf => {
            std.log.info("RTF: {} bytes", .{data.data.len});
        },
    }
}
```

### Wayland Event-Based Monitoring
```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Wayland-only: true event-based monitoring
    var monitor = clipboard.startWaylandEventMonitoring(allocator) catch |err| {
        switch (err) {
            clipboard.ClipboardError.UnsupportedPlatform => {
                std.log.err("This only works on Wayland");
                return;
            },
            else => return err,
        }
    };
    defer monitor.deinit();
    
    // Block until clipboard changes
    while (true) {
        var data = try monitor.waitForClipboardChange();
        defer data.deinit();
        
        const text = data.asText() catch continue;
        std.log.info("Clipboard changed: {s}", .{text});
    }
}
```

### Manual Clipboard Control
```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var clip = try clipboard.Clipboard.init(allocator);
    defer clip.deinit();
    
    // Write data
    try clip.write("Custom clipboard content", .text);
    
    // Read specific format
    var data = try clip.read(.text);
    defer data.deinit();
    
    // Clear clipboard
    try clip.clear();
}
```

## Building and Examples

```bash
# Build library and examples
zig build

# Run tests
zig build test

# Platform-specific examples:

# X11 examples (works on X11 sessions)
zig build run-x11-read      # Read clipboard every second for 45s
zig build run-x11-write     # Write text to clipboard

# Wayland examples (works on Wayland sessions)
zig build run-wayland-read     # Read clipboard every second for 45s  
zig build run-wayland-write    # Write text to clipboard

# macOS examples (works on macOS)
zig build run-macos-read       # Read clipboard every second for 45s
zig build run-macos-write      # Write text to clipboard
```

## API Reference

### Core API (Cross-Platform)

```zig
// Simple cross-platform functions (recommended)
pub fn readClipboardData(allocator: std.mem.Allocator) !ClipboardData
pub fn writeClipboardText(allocator: std.mem.Allocator, text: []const u8) !void

// Wayland-specific event monitoring (fails on X11 with UnsupportedPlatform)
pub fn startWaylandEventMonitoring(allocator: std.mem.Allocator) !WaylandEventMonitor
```

### Manual Control API

```zig
pub const Clipboard = struct {
    pub fn init(allocator: std.mem.Allocator) !Clipboard
    pub fn deinit(self: *Clipboard) void
    pub fn read(self: *Clipboard, format: ClipboardFormat) !ClipboardData
    pub fn write(self: *Clipboard, data: []const u8, format: ClipboardFormat) !void
    pub fn clear(self: *Clipboard) !void
    pub fn processEvents(self: *Clipboard) void  // Wayland only
}
```

### Types

```zig
pub const ClipboardFormat = enum {
    text,    // Plain text (UTF-8)
    image,   // Images (PNG/JPEG/AVIF/WebP/JXL/TIFF/GIF/BMP)
    html,    // HTML markup
    rtf,     // Rich Text Format
}

pub const ClipboardData = struct {
    data: []u8,
    format: ClipboardFormat,
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *ClipboardData) void
    pub fn asText(self: *const ClipboardData) ![]const u8
    pub fn asImage(self: *const ClipboardData) ![]const u8
}

pub const ClipboardError = error{
    InitializationFailed,
    ReadFailed,
    WriteFailed,
    UnsupportedPlatform,
    OutOfMemory,
    InvalidData,
    Timeout,
    NoData,
}
```

### Wayland Event Monitor

```zig
pub const WaylandEventMonitor = struct {
    pub fn init(allocator: std.mem.Allocator) !WaylandEventMonitor
    pub fn deinit(self: *WaylandEventMonitor) void
    pub fn waitForClipboardChange(self: *WaylandEventMonitor) !ClipboardData  // Blocks
}
```

## Dependencies

### Linux
- **libwayland-client**: For Wayland clipboard protocol
- **libX11**: For X11 clipboard protocol

### macOS
- **AppKit framework**: For NSPasteboard access and NSImage validation
- **Foundation framework**: For Objective-C runtime
- **pbcopy/pbpaste**: Command-line utilities for text operations

### Build Dependencies
- **Zig 0.13+**: Minimum supported version

## Implementation Details

### Format Detection
- **X11**: Single TARGETS request with priority-based selection (AVIF→WebP→JPEG→PNG for images, UTF8_STRING→text/plain→STRING for text)
- **Wayland**: Automatic format detection based on available MIME types
- **macOS**: NSPasteboard enumeration with NSImage validation for comprehensive format support
- **Priority Order**: Text → Image → HTML → RTF (configurable per platform)

### Clipboard Persistence
- **X11**: Background fork() process serves clipboard requests until selection lost (xclip-style)
- **Wayland**: Data persists according to compositor implementation  
- **macOS**: Uses system pasteboard persistence

### Memory Management
- All clipboard data uses provided allocator
- Automatic cleanup with defer patterns
- No memory leaks in normal operation

### Platform Detection
- Automatic detection using `XDG_SESSION_TYPE` environment variable on Linux
- Compile-time detection for macOS vs other platforms
- Graceful fallback with clear error messages

## Architecture

```
src/clipboard.zig (Public API)
├── Cross-platform functions (readClipboardData, writeClipboardText)
├── Platform-specific functions (startWaylandEventMonitoring)  
└── Manual control API (Clipboard struct)

src/backends/
├── linux.zig (Platform detection and dispatcher)
│   ├── wayland.zig (Wayland wlr-data-control protocol)
│   └── x11.zig (X11 selection protocol with fork persistence)
├── macos.zig (NSPasteboard implementation)
└── fallback.zig (Unsupported platform stub)
```

## Code Statistics
- **~3000 LOC** total (including examples and build config)
- **4 Platform backends**: Linux (Wayland + X11), macOS, Fallback
- **6 Examples**: Platform-specific read/write for X11, Wayland, and macOS
- **Thread-free**: No internal threading, uses process forking (X11) and event loops (Wayland)

## License

MIT License