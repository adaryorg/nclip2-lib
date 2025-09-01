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
    const STRING_FOR_TYPE = "stringForType:";
    const SET_STRING_FOR_TYPE = "setString:forType:";
    const SET_DATA_FOR_TYPE = "setData:forType:";
    const CLEAR_CONTENTS = "clearContents";
};

const NSPasteboardTypes = struct {
    const STRING = "public.utf8-plain-text";
    const HTML = "public.html";
    const RTF = "public.rtf";
};

fn objc_msgSend_usize(receiver: ?*anyopaque, sel: *anyopaque) usize {
    const result = objc_msgSend(receiver, sel);
    return @as(usize, @intFromPtr(result));
}

const ObjectAtIndexFn = *const fn (receiver: ?*anyopaque, sel: *anyopaque, index: usize) callconv(.c) ?*anyopaque;

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

fn createNSStringFromType(type_name: []const u8, allocator: std.mem.Allocator) !?*anyopaque {
    const type_name_z = try allocator.dupeZ(u8, type_name);
    defer allocator.free(type_name_z);
    
    const NSString = objc_getClass("NSString") orelse return null;
    const StringWithUTF8Fn = *const fn (receiver: ?*anyopaque, sel: *anyopaque, str: [*:0]const u8) callconv(.c) ?*anyopaque;
    const stringWithUTF8 = @as(StringWithUTF8Fn, @ptrCast(&objc_msgSend));
    
    return stringWithUTF8(NSString, sel_registerName(SELECTORS.STRING_WITH_UTF8_STRING), type_name_z.ptr);
}

fn createNSString(text: []const u8, allocator: std.mem.Allocator) !?*anyopaque {
    const text_z = try allocator.dupeZ(u8, text);
    defer allocator.free(text_z);
    
    const NSString = objc_getClass("NSString") orelse return null;
    const StringWithUTF8Fn = *const fn (receiver: ?*anyopaque, sel: *anyopaque, str: [*:0]const u8) callconv(.c) ?*anyopaque;
    const stringWithUTF8 = @as(StringWithUTF8Fn, @ptrCast(&objc_msgSend));
    
    return stringWithUTF8(NSString, sel_registerName(SELECTORS.STRING_WITH_UTF8_STRING), text_z.ptr);
}

fn pasteboardStringForType(pasteboard: ?*anyopaque, type_string: ?*anyopaque) ?*anyopaque {
    if (pasteboard == null or type_string == null) return null;
    
    const StringForTypeFn = *const fn (receiver: ?*anyopaque, sel: *anyopaque, type: ?*anyopaque) callconv(.c) ?*anyopaque;
    const stringForType = @as(StringForTypeFn, @ptrCast(&objc_msgSend));
    
    return stringForType(pasteboard, sel_registerName(SELECTORS.STRING_FOR_TYPE), type_string);
}

fn pasteboardSetStringForType(pasteboard: ?*anyopaque, string: ?*anyopaque, type_string: ?*anyopaque) void {
    if (pasteboard == null or string == null or type_string == null) return;
    
    const SetStringForTypeFn = *const fn (receiver: ?*anyopaque, sel: *anyopaque, string: ?*anyopaque, type: ?*anyopaque) callconv(.c) void;
    const setStringForType = @as(SetStringForTypeFn, @ptrCast(&objc_msgSend));
    
    setStringForType(pasteboard, sel_registerName(SELECTORS.SET_STRING_FOR_TYPE), string, type_string);
}

fn pasteboardSetDataForType(pasteboard: ?*anyopaque, data: ?*anyopaque, type_string: ?*anyopaque) void {
    if (pasteboard == null or data == null or type_string == null) return;
    
    const SetDataForTypeFn = *const fn (receiver: ?*anyopaque, sel: *anyopaque, data: ?*anyopaque, type: ?*anyopaque) callconv(.c) void;
    const setDataForType = @as(SetDataForTypeFn, @ptrCast(&objc_msgSend));
    
    setDataForType(pasteboard, sel_registerName(SELECTORS.SET_DATA_FOR_TYPE), data, type_string);
}

fn pasteboardClearContents(pasteboard: ?*anyopaque) void {
    if (pasteboard == null) return;
    _ = objc_msgSend(pasteboard, sel_registerName(SELECTORS.CLEAR_CONTENTS));
}

fn getDataForType(pasteboard: ?*anyopaque, type_string: ?*anyopaque) ?*anyopaque {
    if (pasteboard == null or type_string == null) return null;
    
    const DataForTypeFn = *const fn (receiver: ?*anyopaque, sel: *anyopaque, type: ?*anyopaque) callconv(.c) ?*anyopaque;
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
    
    const InitWithDataFn = *const fn (receiver: ?*anyopaque, sel: *anyopaque, data: ?*anyopaque) callconv(.c) ?*anyopaque;
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
        
        const is_likely_image = std.mem.containsAtLeast(u8, type_str, 1, "image") or
            std.mem.containsAtLeast(u8, type_str, 1, "png") or
            std.mem.containsAtLeast(u8, type_str, 1, "jpeg") or
            std.mem.containsAtLeast(u8, type_str, 1, "tiff") or
            std.mem.containsAtLeast(u8, type_str, 1, "gif") or
            std.mem.containsAtLeast(u8, type_str, 1, "bmp") or
            std.mem.containsAtLeast(u8, type_str, 1, "heic");
        
        if (!is_likely_image) {
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
    
    const StringWithUTF8Fn = *const fn (receiver: ?*anyopaque, sel: *anyopaque, str: [*:0]const u8) callconv(.c) ?*anyopaque;
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
        const pasteboard = getGeneralPasteboard() orelse {
            return clipboard.ClipboardError.NoData;
        };
        
        const type_string = try createNSStringFromType(NSPasteboardTypes.STRING, self.allocator) orelse {
            return clipboard.ClipboardError.NoData;
        };
        
        const result_string = pasteboardStringForType(pasteboard, type_string) orelse {
            return clipboard.ClipboardError.NoData;
        };
        
        const cstring = objc_msgSend(result_string, sel_registerName(SELECTORS.UTF8_STRING));
        if (cstring == null) {
            return clipboard.ClipboardError.NoData;
        }
        
        const text = std.mem.span(@as([*:0]const u8, @ptrCast(cstring)));
        const clipboard_data = try self.allocator.dupe(u8, text);
        
        return clipboard.ClipboardData{
            .data = clipboard_data,
            .format = .text,
            .allocator = self.allocator,
        };
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
        const pasteboard = getGeneralPasteboard() orelse {
            return clipboard.ClipboardError.NoData;
        };
        
        const type_string = try createNSStringFromType(NSPasteboardTypes.HTML, self.allocator) orelse {
            return clipboard.ClipboardError.NoData;
        };
        
        const data = getDataForType(pasteboard, type_string) orelse {
            return clipboard.ClipboardError.NoData;
        };
        
        const length = getDataLength(data);
        if (length == 0) {
            return clipboard.ClipboardError.NoData;
        }
        
        const bytes_ptr = getDataBytes(data) orelse {
            return clipboard.ClipboardError.NoData;
        };
        
        const bytes = @as([*]const u8, @ptrCast(bytes_ptr))[0..length];
        const clipboard_data = try self.allocator.dupe(u8, bytes);
        
        return clipboard.ClipboardData{
            .data = clipboard_data,
            .format = .html,
            .allocator = self.allocator,
        };
    }
    
    fn readRtf(self: *ClipboardBackend) !clipboard.ClipboardData {
        const pasteboard = getGeneralPasteboard() orelse {
            return clipboard.ClipboardError.NoData;
        };
        
        const type_string = try createNSStringFromType(NSPasteboardTypes.RTF, self.allocator) orelse {
            return clipboard.ClipboardError.NoData;
        };
        
        const data = getDataForType(pasteboard, type_string) orelse {
            return clipboard.ClipboardError.NoData;
        };
        
        const length = getDataLength(data);
        if (length == 0) {
            return clipboard.ClipboardError.NoData;
        }
        
        const bytes_ptr = getDataBytes(data) orelse {
            return clipboard.ClipboardError.NoData;
        };
        
        const bytes = @as([*]const u8, @ptrCast(bytes_ptr))[0..length];
        const clipboard_data = try self.allocator.dupe(u8, bytes);
        
        return clipboard.ClipboardData{
            .data = clipboard_data,
            .format = .rtf,
            .allocator = self.allocator,
        };
    }
    
    pub fn write(self: *ClipboardBackend, data: []const u8, format: clipboard.ClipboardFormat) !void {
        switch (format) {
            .text => return self.writeText(data),
            .html => return self.writeHtml(data),
            .rtf => return self.writeRtf(data),
            .image => return clipboard.ClipboardError.UnsupportedPlatform, 
        }
    }
    
    fn writeHtml(self: *ClipboardBackend, data: []const u8) !void {
        const pasteboard = getGeneralPasteboard() orelse {
            return clipboard.ClipboardError.WriteFailed;
        };
        
        pasteboardClearContents(pasteboard);
        
        const NSData = objc_getClass("NSData") orelse {
            return clipboard.ClipboardError.WriteFailed;
        };
        
        const DataWithBytesFn = *const fn (receiver: ?*anyopaque, sel: *anyopaque, bytes: [*]const u8, length: usize) callconv(.c) ?*anyopaque;
        const dataWithBytes = @as(DataWithBytesFn, @ptrCast(&objc_msgSend));
        const data_obj = dataWithBytes(NSData, sel_registerName("dataWithBytes:length:"), data.ptr, data.len) orelse {
            return clipboard.ClipboardError.WriteFailed;
        };
        
        const type_string = try createNSStringFromType(NSPasteboardTypes.HTML, self.allocator) orelse {
            return clipboard.ClipboardError.WriteFailed;
        };
        
        pasteboardSetDataForType(pasteboard, data_obj, type_string);
    }
    
    fn writeRtf(self: *ClipboardBackend, data: []const u8) !void {
        const pasteboard = getGeneralPasteboard() orelse {
            return clipboard.ClipboardError.WriteFailed;
        };
        
        pasteboardClearContents(pasteboard);
        
        const NSData = objc_getClass("NSData") orelse {
            return clipboard.ClipboardError.WriteFailed;
        };
        
        const DataWithBytesFn = *const fn (receiver: ?*anyopaque, sel: *anyopaque, bytes: [*]const u8, length: usize) callconv(.c) ?*anyopaque;
        const dataWithBytes = @as(DataWithBytesFn, @ptrCast(&objc_msgSend));
        const data_obj = dataWithBytes(NSData, sel_registerName("dataWithBytes:length:"), data.ptr, data.len) orelse {
            return clipboard.ClipboardError.WriteFailed;
        };
        
        const type_string = try createNSStringFromType(NSPasteboardTypes.RTF, self.allocator) orelse {
            return clipboard.ClipboardError.WriteFailed;
        };
        
        pasteboardSetDataForType(pasteboard, data_obj, type_string);
    }
    
    fn writeText(self: *ClipboardBackend, data: []const u8) !void {
        const pasteboard = getGeneralPasteboard() orelse {
            return clipboard.ClipboardError.WriteFailed;
        };
        
        pasteboardClearContents(pasteboard);
        
        const string_obj = try createNSString(data, self.allocator) orelse {
            return clipboard.ClipboardError.WriteFailed;
        };
        
        const type_string = try createNSStringFromType(NSPasteboardTypes.STRING, self.allocator) orelse {
            return clipboard.ClipboardError.WriteFailed;
        };
        
        pasteboardSetStringForType(pasteboard, string_obj, type_string);
    }
    
    pub fn clear(self: *ClipboardBackend) !void {
        _ = self;
        const pasteboard = getGeneralPasteboard() orelse {
            return clipboard.ClipboardError.WriteFailed;
        };
        
        pasteboardClearContents(pasteboard);
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
    
    var available = std.ArrayList(clipboard.ClipboardFormat){};
    
    const formats = [_]clipboard.ClipboardFormat{ .text, .image, .html, .rtf };
    
    for (formats) |format| {
        if (backend.read(format)) |data| {
            data.deinit();
            try available.append(allocator, format);
        } else |_| {}
    }
    
    return available.toOwnedSlice(allocator);
}


