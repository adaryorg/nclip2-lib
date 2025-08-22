# nclip2-lib

Cross-platform clipboard library for Zig supporting Wayland, X11, and macOS.

## Features

- **Cross-platform**: Native support for Wayland, X11, and macOS
- **Multiple formats**: Text, images, HTML, and RTF
- **Real-time monitoring**: Clipboard change detection with callbacks
- **Memory safe**: Proper memory management with allocator pattern
- **Zero dependencies**: Uses only system libraries

## Supported Platforms

| Platform | Backend | Status |
|----------|---------|--------|
| Linux (Wayland) | libwayland-client | Supported |
| Linux (X11) | libX11, libXmu | Supported |
| macOS | AppKit/Foundation | Supported |

## Usage

### Main Functions

#### 1. One-shot Reading (Recommended)
```zig
const data = try clipboard.readClipboardData(allocator);
defer data.deinit();
const text = try data.asText();
```

#### 2. Writing to Clipboard
```zig
var clip = try clipboard.Clipboard.init(allocator);
defer clip.deinit();
try clip.write("Hello clipboard!", .text);
```

#### 3. Reading Specific Format
```zig
var clip = try clipboard.Clipboard.init(allocator);
defer clip.deinit();
const data = try clip.read(.text);
defer data.deinit();
```

### Basic Example

```zig
const std = @import("std");
const clipboard = @import("clipboard");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize clipboard
    var clip = try clipboard.Clipboard.init(allocator);
    defer clip.deinit();
    
    // Write text
    try clip.write("Hello, clipboard!", .text);
    
    // Read text
    var data = try clip.read(.text);
    defer data.deinit();
    
    const text = try data.asText();
    std.log.info("Clipboard content: {s}", .{text});
}
```

### Monitoring Clipboard Changes

```zig
fn clipboardChanged(data: clipboard.ClipboardData) void {
    const text = data.asText() catch return;
    std.log.info("Clipboard changed: {s}", .{text});
}

// Start monitoring
try clip.startMonitoring(clipboardChanged);

// Stop monitoring
clip.stopMonitoring();
```

## Building

```bash
# Build library
zig build

# Run tests
zig build test

# Run example
zig build run-example
```

## Dependencies

### Linux (Wayland)
- libwayland-client

### Linux (X11)
- libX11
- libXmu

### macOS
- AppKit framework
- Foundation framework

## Architecture

The library uses a backend system with automatic platform detection:

```
clipboard.zig (public API)
├── backends/linux.zig (platform selector)
│   ├── wayland.zig (Wayland implementation)
│   └── x11.zig (X11 implementation)
├── backends/macos.zig (macOS implementation)
└── backends/fallback.zig (unsupported platforms)
```

## API Reference

### Types

- `ClipboardFormat`: `.text`, `.image`, `.html`, `.rtf`
- `ClipboardData`: Contains clipboard data with format information
- `ClipboardError`: Error types for clipboard operations
- `ClipboardChangeCallback`: Function type for monitoring callbacks

### Functions

- `Clipboard.init(allocator)`: Initialize clipboard instance
- `clipboard.read(format)`: Read clipboard data in specified format
- `clipboard.write(data, format)`: Write data to clipboard
- `clipboard.startMonitoring(callback)`: Start monitoring clipboard changes
- `clipboard.stopMonitoring()`: Stop monitoring
- `clipboard.isAvailable(format)`: Check if format is available
- `clipboard.getAvailableFormats(allocator)`: Get all available formats
- `clipboard.clear()`: Clear clipboard contents

## License

MIT License