const std = @import("std");
const clipboard = @import("../clipboard.zig");

extern fn objc_getClass(name: [*:0]const u8) ?*anyopaque;
extern fn sel_registerName(str: [*:0]const u8) *anyopaque;
extern fn objc_msgSend(receiver: ?*anyopaque, sel: *anyopaque, ...) ?*anyopaque;

const SELECTORS = struct {
    const GENERAL_PASTEBOARD = "generalPasteboard";
    const TYPES = "types";
    const COUNT = "count";
    const OBJECT_AT_INDEX = "objectAtIndex:";
    const DATA_FOR_TYPE = "dataForType:";
    const LENGTH = "length";
    const BYTES = "bytes";
    const UTF8_STRING = "UTF8String";
    const ALLOC = "alloc";
    const INIT_WITH_DATA = "initWithData:";
    const RELEASE = "release";
    const STRING_WITH_UTF8_STRING = "stringWithUTF8String:";
};

fn objc_msgSend_usize(receiver: ?*anyopaque, sel: *anyopaque) usize {
    const result = objc_msgSend(receiver, sel);
    return @as(usize, @intFromPtr(result));
}

const ObjectAtIndexFn = *const fn (receiver: ?*anyopaque, sel: *anyopaque, index: usize) callconv(.C) ?*anyopaque;

fn objc_msgSend_objectAtIndex(receiver: ?*anyopaque, sel: *anyopaque, index: usize) ?*anyopaque {
    const msgSend = @as(ObjectAtIndexFn, @ptrCast(&objc_msgSend));
    return msgSend(receiver, sel, index);
}

pub const PlatformType = enum {
    macos,
};

pub fn detectPlatform() PlatformType {
    return .macos;
}

fn getGeneralPasteboard() ?*anyopaque {
    const NSPasteboard = objc_getClass("NSPasteboard") orelse return null;
    return objc_msgSend(NSPasteboard, sel_registerName(SELECTORS.GENERAL_PASTEBOARD));
}

fn getPasteboardTypes(pasteboard: ?*anyopaque) ?*anyopaque {
    if (pasteboard == null) return null;
    return objc_msgSend(pasteboard, sel_registerName(SELECTORS.TYPES));
}

fn getArrayCount(array: ?*anyopaque) usize {
    if (array == null) return 0;
    return objc_msgSend_usize(array, sel_registerName(SELECTORS.COUNT));
}

fn getArrayObjectAtIndex(array: ?*anyopaque, index: usize) ?*anyopaque {
    if (array == null) return null;
    return objc_msgSend_objectAtIndex(array, sel_registerName(SELECTORS.OBJECT_AT_INDEX), index);
}

fn getDataForType(pasteboard: ?*anyopaque, type_string: ?*anyopaque) ?*anyopaque {
    if (pasteboard == null or type_string == null) return null;
    
    const DataForTypeFn = *const fn (receiver: ?*anyopaque, sel: *anyopaque, type: ?*anyopaque) callconv(.C) ?*anyopaque;
    const dataForType = @as(DataForTypeFn, @ptrCast(&objc_msgSend));
    
    return dataForType(pasteboard, sel_registerName(SELECTORS.DATA_FOR_TYPE), type_string);
}

fn getDataLength(data: ?*anyopaque) usize {
    if (data == null) return 0;
    return objc_msgSend_usize(data, sel_registerName(SELECTORS.LENGTH));
}

fn getDataBytes(data: ?*anyopaque) ?*anyopaque {
    if (data == null) return null;
    return objc_msgSend(data, sel_registerName(SELECTORS.BYTES));
}

fn canCreateImageFromData(data: ?*anyopaque) bool {
    if (data == null) return false;
    
    const NSImage = objc_getClass("NSImage") orelse return false;
    const image = objc_msgSend(NSImage, sel_registerName(SELECTORS.ALLOC));
    if (image == null) return false;
    
    const InitWithDataFn = *const fn (receiver: ?*anyopaque, sel: *anyopaque, data: ?*anyopaque) callconv(.C) ?*anyopaque;
    const initWithData = @as(InitWithDataFn, @ptrCast(&objc_msgSend));
    
    const initialized = initWithData(image, sel_registerName(SELECTORS.INIT_WITH_DATA), data);
    const is_valid = initialized != null;
    
    _ = objc_msgSend(image, sel_registerName(SELECTORS.RELEASE));
    
    return is_valid;
}

fn detectAndReadImageData(pasteboard: ?*anyopaque, allocator: std.mem.Allocator) !?clipboard.ClipboardData {
    const common_image_types = [_][]const u8{
        "public.png",
        "public.jpeg", 
        "public.tiff",
        "public.heic",
        "public.gif",
        "public.bmp",
        "com.compuserve.gif",
        "com.microsoft.bmp",
    };
    
    for (common_image_types) |type_name| {
        if (tryReadImageType(pasteboard, type_name, allocator)) |data| {
            return data;
        } else |_| {}
    }
    
    const types_array = getPasteboardTypes(pasteboard) orelse {
        std.log.debug("No pasteboard types array", .{});
        return null;
    };
    
    const count = getArrayCount(types_array);
    std.log.debug("Found {} pasteboard types", .{count});
    
    if (count == 0 or count > 100) { 
        std.log.debug("Invalid count: {}", .{count});
        return null;
    }
    
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const type_obj = getArrayObjectAtIndex(types_array, i) orelse continue;
        
        const type_cstring = objc_msgSend(type_obj, sel_registerName(SELECTORS.UTF8_STRING));
        if (type_cstring == null) continue;
        
        const type_str = std.mem.span(@as([*:0]const u8, @ptrCast(type_cstring)));
        std.log.debug("Checking type: {s}", .{type_str});
        
        if (!std.mem.startsWith(u8, type_str, "public.") and 
            !std.mem.startsWith(u8, type_str, "com.") and
            !std.mem.containsAtLeast(u8, type_str, 1, "image")) {
            continue;
        }
        
        if (tryReadImageTypeByObj(pasteboard, type_obj, allocator)) |data| {
            return data;
        } else |_| {}
    }
    
    std.log.debug("No valid image data found", .{});
    return null;
}

fn tryReadImageType(pasteboard: ?*anyopaque, type_name: []const u8, allocator: std.mem.Allocator) !clipboard.ClipboardData {
    const type_name_z = try allocator.dupeZ(u8, type_name);
    defer allocator.free(type_name_z);
    
    const NSString = objc_getClass("NSString") orelse return clipboard.ClipboardError.NoData;
    
    const StringWithUTF8Fn = *const fn (receiver: ?*anyopaque, sel: *anyopaque, str: [*:0]const u8) callconv(.C) ?*anyopaque;
    const stringWithUTF8 = @as(StringWithUTF8Fn, @ptrCast(&objc_msgSend));
    
    const type_string = stringWithUTF8(NSString, sel_registerName(SELECTORS.STRING_WITH_UTF8_STRING), type_name_z.ptr);
    if (type_string == null) return clipboard.ClipboardError.NoData;
    
    return tryReadImageTypeByObj(pasteboard, type_string, allocator);
}

fn tryReadImageTypeByObj(pasteboard: ?*anyopaque, type_obj: ?*anyopaque, allocator: std.mem.Allocator) !clipboard.ClipboardData {
    const data = getDataForType(pasteboard, type_obj) orelse return clipboard.ClipboardError.NoData;
    
    const length = getDataLength(data);
    if (length == 0) return clipboard.ClipboardError.NoData;
    
    if (canCreateImageFromData(data)) {
        const bytes_ptr = getDataBytes(data) orelse return clipboard.ClipboardError.NoData;
        const bytes = @as([*]const u8, @ptrCast(bytes_ptr))[0..length];
        const clipboard_data = try allocator.dupe(u8, bytes);
        
        return clipboard.ClipboardData{
            .data = clipboard_data,
            .format = .image,
            .allocator = allocator,
        };
    }
    
    return clipboard.ClipboardError.NoData;
}

fn runPasteCommand(allocator: std.mem.Allocator, args: []const []const u8, format: clipboard.ClipboardFormat) !clipboard.ClipboardData {
    var child = std.process.Child.init(args, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    
    try child.spawn();
    
    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    const stderr = try child.stderr.?.readToEndAlloc(allocator, 1024);
    defer allocator.free(stderr);
    
    const result = try child.wait();
    
    if (result != .Exited or result.Exited != 0) {
        allocator.free(stdout);
        return clipboard.ClipboardError.ReadFailed;
    }
    
    if (stdout.len == 0) {
        allocator.free(stdout);
        return clipboard.ClipboardError.NoData;
    }
    
    return clipboard.ClipboardData{
        .data = stdout,
        .format = format,
        .allocator = allocator,
    };
}

pub const ClipboardBackend = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !ClipboardBackend {        
        return ClipboardBackend{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ClipboardBackend) void {
        _ = self;
    }
    
    pub fn read(self: *ClipboardBackend, format: clipboard.ClipboardFormat) !clipboard.ClipboardData {
        switch (format) {
            .text => return self.readText(),
            .image => return self.readImage(),
            .html => return self.readHtml(),
            .rtf => return self.readRtf(),
        }
    }
    
    fn readText(self: *ClipboardBackend) !clipboard.ClipboardData {
        return runPasteCommand(self.allocator, &[_][]const u8{"pbpaste"}, .text);
    }
    
    fn readImage(self: *ClipboardBackend) !clipboard.ClipboardData {
        const pasteboard = getGeneralPasteboard() orelse {
            return clipboard.ClipboardError.NoData;
        };
        
        if (try detectAndReadImageData(pasteboard, self.allocator)) |image_data| {
            return image_data;
        }
        
        return clipboard.ClipboardError.NoData;
    }
    
    fn readHtml(self: *ClipboardBackend) !clipboard.ClipboardData {
        _ = self;
        return clipboard.ClipboardError.NoData;
    }
    
    fn readRtf(self: *ClipboardBackend) !clipboard.ClipboardData {
        return runPasteCommand(self.allocator, &[_][]const u8{"pbpaste", "-Prefer", "rtf"}, .rtf);
    }
    
    pub fn write(self: *ClipboardBackend, data: []const u8, format: clipboard.ClipboardFormat) !void {
        switch (format) {
            .text => return self.writeText(data),
            .image, .html, .rtf => return clipboard.ClipboardError.UnsupportedPlatform,
        }
    }
    
    fn writeText(self: *ClipboardBackend, data: []const u8) !void {
        var child = std.process.Child.init(&[_][]const u8{"pbcopy"}, self.allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        
        try child.spawn();
        
        const stdin = child.stdin.?;
        try stdin.writeAll(data);
        stdin.close();
        child.stdin = null;
        
        const result = try child.wait();
        
        if (result != .Exited or result.Exited != 0) {
            return clipboard.ClipboardError.WriteFailed;
        }
    }
    
    pub fn clear(self: *ClipboardBackend) !void {
        return self.writeText("");
    }
    
    pub fn processEvents(self: *ClipboardBackend) void {
        _ = self;
    }
    
};

pub fn getClipboardDataAuto(allocator: std.mem.Allocator) !clipboard.ClipboardData {
    var backend = try ClipboardBackend.init(allocator);
    defer backend.deinit();
    
    const formats = [_]clipboard.ClipboardFormat{ .text, .image, .html, .rtf };
    
    for (formats) |format| {
        if (backend.read(format)) |data| {
            return data;
        } else |_| {}
    }
    
    return clipboard.ClipboardError.NoData;
}

pub fn getAvailableClipboardFormats(allocator: std.mem.Allocator) ![]clipboard.ClipboardFormat {
    var backend = try ClipboardBackend.init(allocator);
    defer backend.deinit();
    
    var available = std.ArrayList(clipboard.ClipboardFormat).init(allocator);
    
    const formats = [_]clipboard.ClipboardFormat{ .text, .image, .html, .rtf };
    
    for (formats) |format| {
        if (backend.read(format)) |data| {
            data.deinit();
            try available.append(format);
        } else |_| {}
    }
    
    return available.toOwnedSlice();
}


