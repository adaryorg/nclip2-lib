const std = @import("std");
const clipboard = @import("../clipboard.zig");
const c = @cImport({
    @cInclude("objc/objc.h");
    @cInclude("objc/runtime.h");
    @cInclude("objc/message.h");
    @cInclude("CoreFoundation/CoreFoundation.h");
});

pub const PlatformType = enum {
    macos,
};

pub fn detectPlatform() PlatformType {
    return .macos;
}

pub const ClipboardBackend = struct {
    allocator: std.mem.Allocator,
    monitoring: bool,
    monitor_callback: ?clipboard.ClipboardChangeCallback,
    last_change_count: i64,
    
    pub fn init(allocator: std.mem.Allocator) !ClipboardBackend {
        // Initialize Objective-C runtime
        const NSApp = objc_getClass("NSApplication");
        if (NSApp == null) {
            return clipboard.ClipboardError.InitializationFailed;
        }
        
        return ClipboardBackend{
            .allocator = allocator,
            .monitoring = false,
            .monitor_callback = null,
            .last_change_count = -1,
        };
    }
    
    pub fn deinit(self: *ClipboardBackend) void {
        _ = self;
    }
    
    pub fn read(self: *ClipboardBackend, format: clipboard.ClipboardFormat) !clipboard.ClipboardData {
        const NSPasteboard = objc_getClass("NSPasteboard");
        const generalPasteboard = objc_msgSend(NSPasteboard, sel_registerName("generalPasteboard"));
        
        switch (format) {
            .text => {
                const NSPasteboardTypeString = objc_msgSend(objc_getClass("NSPasteboardTypeString"), sel_registerName("string"));
                const string = objc_msgSend(generalPasteboard, sel_registerName("stringForType:"), NSPasteboardTypeString);
                
                if (string == null) {
                    return clipboard.ClipboardError.NoData;
                }
                
                const utf8String = objc_msgSend(string, sel_registerName("UTF8String"));
                if (utf8String == null) {
                    return clipboard.ClipboardError.ReadFailed;
                }
                
                const c_str: [*:0]const u8 = @ptrCast(utf8String);
                const str_len = std.mem.len(c_str);
                const clipboard_data = try self.allocator.dupe(u8, c_str[0..str_len]);
                
                return clipboard.ClipboardData{
                    .data = clipboard_data,
                    .format = format,
                    .allocator = self.allocator,
                };
            },
            .image => {
                const NSPasteboardTypePNG = objc_msgSend(objc_getClass("NSPasteboardTypePNG"), sel_registerName("string"));
                const data = objc_msgSend(generalPasteboard, sel_registerName("dataForType:"), NSPasteboardTypePNG);
                
                if (data == null) {
                    return clipboard.ClipboardError.NoData;
                }
                
                const bytes = objc_msgSend(data, sel_registerName("bytes"));
                const length = objc_msgSend(data, sel_registerName("length"));
                
                if (bytes == null or length == 0) {
                    return clipboard.ClipboardError.NoData;
                }
                
                const data_len: usize = @intCast(@as(c_long, @intCast(length)));
                const bytes_ptr: [*]const u8 = @ptrCast(bytes);
                const clipboard_data = try self.allocator.dupe(u8, bytes_ptr[0..data_len]);
                
                return clipboard.ClipboardData{
                    .data = clipboard_data,
                    .format = format,
                    .allocator = self.allocator,
                };
            },
            .html => {
                const NSPasteboardTypeHTML = objc_msgSend(objc_getClass("NSPasteboardTypeHTML"), sel_registerName("string"));
                const string = objc_msgSend(generalPasteboard, sel_registerName("stringForType:"), NSPasteboardTypeHTML);
                
                if (string == null) {
                    return clipboard.ClipboardError.NoData;
                }
                
                const utf8String = objc_msgSend(string, sel_registerName("UTF8String"));
                if (utf8String == null) {
                    return clipboard.ClipboardError.ReadFailed;
                }
                
                const c_str: [*:0]const u8 = @ptrCast(utf8String);
                const str_len = std.mem.len(c_str);
                const clipboard_data = try self.allocator.dupe(u8, c_str[0..str_len]);
                
                return clipboard.ClipboardData{
                    .data = clipboard_data,
                    .format = format,
                    .allocator = self.allocator,
                };
            },
            .rtf => {
                const NSPasteboardTypeRTF = objc_msgSend(objc_getClass("NSPasteboardTypeRTF"), sel_registerName("string"));
                const data = objc_msgSend(generalPasteboard, sel_registerName("dataForType:"), NSPasteboardTypeRTF);
                
                if (data == null) {
                    return clipboard.ClipboardError.NoData;
                }
                
                const bytes = objc_msgSend(data, sel_registerName("bytes"));
                const length = objc_msgSend(data, sel_registerName("length"));
                
                if (bytes == null or length == 0) {
                    return clipboard.ClipboardError.NoData;
                }
                
                const data_len: usize = @intCast(@as(c_long, @intCast(length)));
                const bytes_ptr: [*]const u8 = @ptrCast(bytes);
                const clipboard_data = try self.allocator.dupe(u8, bytes_ptr[0..data_len]);
                
                return clipboard.ClipboardData{
                    .data = clipboard_data,
                    .format = format,
                    .allocator = self.allocator,
                };
            },
        }
    }
    
    pub fn write(self: *ClipboardBackend, data: []const u8, format: clipboard.ClipboardFormat) !void {
        _ = self;
        
        const NSPasteboard = objc_getClass("NSPasteboard");
        const generalPasteboard = objc_msgSend(NSPasteboard, sel_registerName("generalPasteboard"));
        
        // Clear the pasteboard
        _ = objc_msgSend(generalPasteboard, sel_registerName("clearContents"));
        
        switch (format) {
            .text => {
                const NSString = objc_getClass("NSString");
                const string = objc_msgSend(NSString, sel_registerName("alloc"));
                const initWithBytes = objc_msgSend(
                    string,
                    sel_registerName("initWithBytes:length:encoding:"),
                    data.ptr,
                    data.len,
                    @as(c_ulong, 4) // NSUTF8StringEncoding
                );
                
                const NSPasteboardTypeString = objc_msgSend(objc_getClass("NSPasteboardTypeString"), sel_registerName("string"));
                const success = objc_msgSend(generalPasteboard, sel_registerName("setString:forType:"), initWithBytes, NSPasteboardTypeString);
                
                _ = objc_msgSend(string, sel_registerName("release"));
                
                if (@as(c_int, @intCast(success)) == 0) {
                    return clipboard.ClipboardError.WriteFailed;
                }
            },
            .image => {
                const NSData = objc_getClass("NSData");
                const nsdata = objc_msgSend(NSData, sel_registerName("alloc"));
                const initWithBytes = objc_msgSend(
                    nsdata,
                    sel_registerName("initWithBytes:length:"),
                    data.ptr,
                    data.len
                );
                
                const NSPasteboardTypePNG = objc_msgSend(objc_getClass("NSPasteboardTypePNG"), sel_registerName("string"));
                const success = objc_msgSend(generalPasteboard, sel_registerName("setData:forType:"), initWithBytes, NSPasteboardTypePNG);
                
                _ = objc_msgSend(nsdata, sel_registerName("release"));
                
                if (@as(c_int, @intCast(success)) == 0) {
                    return clipboard.ClipboardError.WriteFailed;
                }
            },
            .html => {
                const NSString = objc_getClass("NSString");
                const string = objc_msgSend(NSString, sel_registerName("alloc"));
                const initWithBytes = objc_msgSend(
                    string,
                    sel_registerName("initWithBytes:length:encoding:"),
                    data.ptr,
                    data.len,
                    @as(c_ulong, 4) // NSUTF8StringEncoding
                );
                
                const NSPasteboardTypeHTML = objc_msgSend(objc_getClass("NSPasteboardTypeHTML"), sel_registerName("string"));
                const success = objc_msgSend(generalPasteboard, sel_registerName("setString:forType:"), initWithBytes, NSPasteboardTypeHTML);
                
                _ = objc_msgSend(string, sel_registerName("release"));
                
                if (@as(c_int, @intCast(success)) == 0) {
                    return clipboard.ClipboardError.WriteFailed;
                }
            },
            .rtf => {
                const NSData = objc_getClass("NSData");
                const nsdata = objc_msgSend(NSData, sel_registerName("alloc"));
                const initWithBytes = objc_msgSend(
                    nsdata,
                    sel_registerName("initWithBytes:length:"),
                    data.ptr,
                    data.len
                );
                
                const NSPasteboardTypeRTF = objc_msgSend(objc_getClass("NSPasteboardTypeRTF"), sel_registerName("string"));
                const success = objc_msgSend(generalPasteboard, sel_registerName("setData:forType:"), initWithBytes, NSPasteboardTypeRTF);
                
                _ = objc_msgSend(nsdata, sel_registerName("release"));
                
                if (@as(c_int, @intCast(success)) == 0) {
                    return clipboard.ClipboardError.WriteFailed;
                }
            },
        }
    }
    
    pub fn startMonitoring(self: *ClipboardBackend, callback: clipboard.ClipboardChangeCallback) !void {
        self.monitor_callback = callback;
        self.monitoring = true;
        
        // Get initial change count
        const NSPasteboard = objc_getClass("NSPasteboard");
        const generalPasteboard = objc_msgSend(NSPasteboard, sel_registerName("generalPasteboard"));
        self.last_change_count = @intCast(objc_msgSend(generalPasteboard, sel_registerName("changeCount")));
        
        // Start monitoring thread
        const thread = try std.Thread.spawn(.{}, monitorThread, .{self});
        thread.detach();
    }
    
    pub fn stopMonitoring(self: *ClipboardBackend) void {
        self.monitoring = false;
        self.monitor_callback = null;
    }
    
    pub fn isAvailable(self: *ClipboardBackend, format: clipboard.ClipboardFormat) bool {
        _ = self;
        
        const NSPasteboard = objc_getClass("NSPasteboard");
        const generalPasteboard = objc_msgSend(NSPasteboard, sel_registerName("generalPasteboard"));
        
        const type_string = switch (format) {
            .text => objc_msgSend(objc_getClass("NSPasteboardTypeString"), sel_registerName("string")),
            .image => objc_msgSend(objc_getClass("NSPasteboardTypePNG"), sel_registerName("string")),
            .html => objc_msgSend(objc_getClass("NSPasteboardTypeHTML"), sel_registerName("string")),
            .rtf => objc_msgSend(objc_getClass("NSPasteboardTypeRTF"), sel_registerName("string")),
        };
        
        const available_type = objc_msgSend(generalPasteboard, sel_registerName("availableTypeFromArray:"), 
                                          objc_msgSend(objc_getClass("NSArray"), sel_registerName("arrayWithObject:"), type_string));
        
        return available_type != null;
    }
    
    pub fn getAvailableFormats(self: *ClipboardBackend, allocator: std.mem.Allocator) ![]clipboard.ClipboardFormat {
        var formats = std.ArrayList(clipboard.ClipboardFormat).init(allocator);
        defer formats.deinit();
        
        if (self.isAvailable(.text)) {
            try formats.append(.text);
        }
        if (self.isAvailable(.image)) {
            try formats.append(.image);
        }
        if (self.isAvailable(.html)) {
            try formats.append(.html);
        }
        if (self.isAvailable(.rtf)) {
            try formats.append(.rtf);
        }
        
        return try allocator.dupe(clipboard.ClipboardFormat, formats.items);
    }
    
    pub fn clear(self: *ClipboardBackend) !void {
        _ = self;
        
        const NSPasteboard = objc_getClass("NSPasteboard");
        const generalPasteboard = objc_msgSend(NSPasteboard, sel_registerName("generalPasteboard"));
        
        _ = objc_msgSend(generalPasteboard, sel_registerName("clearContents"));
    }
    
    pub fn processEvents(self: *ClipboardBackend) void {
        // macOS uses polling, so no event processing needed
        _ = self;
    }
    
    fn monitorThread(self: *ClipboardBackend) void {
        const NSPasteboard = objc_getClass("NSPasteboard");
        const generalPasteboard = objc_msgSend(NSPasteboard, sel_registerName("generalPasteboard"));
        
        while (self.monitoring) {
            const current_change_count: i64 = @intCast(objc_msgSend(generalPasteboard, sel_registerName("changeCount")));
            
            if (current_change_count != self.last_change_count) {
                self.last_change_count = current_change_count;
                
                if (self.monitor_callback != null) {
                    // Try to read the clipboard data and trigger callback
                    var clipboard_data = self.read(.text) catch continue;
                    
                    if (self.monitor_callback) |callback| {
                        callback(clipboard_data);
                    } else {
                        clipboard_data.deinit();
                    }
                }
            }
            
            std.time.sleep(100 * std.time.ns_per_ms); // Check every 100ms
        }
    }
};

// Objective-C runtime functions
extern fn objc_getClass(name: [*:0]const u8) ?*anyopaque;
extern fn sel_registerName(str: [*:0]const u8) *anyopaque;
extern fn objc_msgSend(receiver: ?*anyopaque, sel: *anyopaque, ...) ?*anyopaque;