const std = @import("std");
const clipboard = @import("../clipboard.zig");
const c = @cImport({
    @cInclude("wayland-client-core.h");
    @cInclude("wayland-client-protocol.h");
    @cInclude("wlr_protocol.h");
    @cInclude("unistd.h");
    @cInclude("string.h");
    @cInclude("fcntl.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
});

const DeviceType = enum {
    wl_data_device,
    zwlr_data_control_device,
};

const MIME_TYPES = struct {
    const TEXT_PLAIN = "text/plain";
    const TEXT_PLAIN_UTF8 = "text/plain;charset=utf-8";
    const TEXT_CAPS = "TEXT";
    const STRING_CAPS = "STRING";
    const UTF8_STRING = "UTF8_STRING";
    const TEXT_HTML = "text/html";
    const APPLICATION_RTF = "application/rtf";
};


fn mimeTypeToFormat(mime_str: []const u8) ?clipboard.ClipboardFormat {
    if (std.mem.eql(u8, mime_str, MIME_TYPES.TEXT_PLAIN) or 
        std.mem.eql(u8, mime_str, MIME_TYPES.TEXT_PLAIN_UTF8) or
        std.mem.eql(u8, mime_str, MIME_TYPES.TEXT_CAPS) or
        std.mem.eql(u8, mime_str, MIME_TYPES.STRING_CAPS) or
        std.mem.eql(u8, mime_str, MIME_TYPES.UTF8_STRING)) {
        return .text;
    } else if (std.mem.startsWith(u8, mime_str, "image/")) {
        return .image;
    } else if (std.mem.eql(u8, mime_str, MIME_TYPES.TEXT_HTML)) {
        return .html;
    } else if (std.mem.eql(u8, mime_str, MIME_TYPES.APPLICATION_RTF)) {
        return .rtf;
    }
    return null;
}

pub const WaylandClipboard = struct {
    display: ?*c.wl_display,
    registry: ?*c.wl_registry,
    
    data_device_manager: ?*c.wl_data_device_manager,
    data_device: ?*c.wl_data_device,
    
    wlr_data_control_manager: ?*c.zwlr_data_control_manager_v1,
    wlr_data_control_device: ?*c.zwlr_data_control_device_v1,
    
    seat: ?*c.wl_seat,
    allocator: std.mem.Allocator,
    
    device_type: DeviceType,
    
    current_offer_standard: ?*c.wl_data_offer,
    current_offer_wlr: ?*c.zwlr_data_control_offer_v1,
    available_formats: std.ArrayList(clipboard.ClipboardFormat),
    
    selection_received: bool,
    offer_mime_types_received: bool,
    
    own_clipboard_data: ?[]u8,
    own_clipboard_format: ?clipboard.ClipboardFormat,
    we_own_selection: bool,
    
    data_result: ?clipboard.ClipboardData,
    data_error: ?clipboard.ClipboardError,
    offer_received: bool,
    
    active_write_contexts: std.ArrayList(*WriteContext),
    
    
    
    pub fn init(self: *WaylandClipboard, allocator: std.mem.Allocator) !void {
        const display = c.wl_display_connect(null);
        if (display == null) {
            return clipboard.ClipboardError.InitializationFailed;
        }
        
        self.* = WaylandClipboard{
            .display = display,
            .registry = null,
            .data_device_manager = null,
            .data_device = null,
            .wlr_data_control_manager = null,
            .wlr_data_control_device = null,
            .seat = null,
            .allocator = allocator,
            .device_type = .wl_data_device, 
            .current_offer_standard = null,
            .current_offer_wlr = null,
            .available_formats = std.ArrayList(clipboard.ClipboardFormat){},
            .selection_received = false,
            .offer_mime_types_received = false,
            .own_clipboard_data = null,
            .own_clipboard_format = null,
            .we_own_selection = false,
            .data_result = null,
            .data_error = null,
            .offer_received = false,
            .active_write_contexts = std.ArrayList(*WriteContext){},
        };
        
        const registry = c.wl_display_get_registry(display);
        if (registry == null) {
            c.wl_display_disconnect(display);
            return clipboard.ClipboardError.InitializationFailed;
        }
        
        self.registry = registry;
        
        const registry_listener = c.wl_registry_listener{
            .global = registryGlobal,
            .global_remove = registryGlobalRemove,
        };
        
        _ = c.wl_registry_add_listener(registry, &registry_listener, self);
        _ = c.wl_display_roundtrip(display);
        
        if (self.wlr_data_control_manager != null and self.seat != null) {
            self.device_type = .zwlr_data_control_device;
            
            self.wlr_data_control_device = c.zwlr_data_control_manager_v1_get_data_device(
                self.wlr_data_control_manager,
                self.seat
            );
            
            if (self.wlr_data_control_device == null) {
                self.deinitPartial();
                return clipboard.ClipboardError.InitializationFailed;
            }
            
            const wlr_device_listener = c.zwlr_data_control_device_v1_listener{
                .data_offer = wlrDataDeviceDataOffer,
                .selection = wlrDataDeviceSelection,
                .finished = wlrDataDeviceFinished,
                .primary_selection = wlrDataDevicePrimarySelection,
            };
            
            _ = c.zwlr_data_control_device_v1_add_listener(self.wlr_data_control_device, &wlr_device_listener, self);
            
        } else if (self.data_device_manager != null and self.seat != null) {
            self.device_type = .wl_data_device;
            
            self.data_device = c.wl_data_device_manager_get_data_device(
                self.data_device_manager,
                self.seat
            );
            
            if (self.data_device == null) {
                self.deinitPartial();
                return clipboard.ClipboardError.InitializationFailed;
            }
            
            const data_device_listener = c.wl_data_device_listener{
                .data_offer = dataDeviceDataOffer,
                .enter = dataDeviceEnter,
                .leave = dataDeviceLeave,
                .motion = dataDeviceMotion,
                .drop = dataDeviceDrop,
                .selection = dataDeviceSelection,
            };
            
            _ = c.wl_data_device_add_listener(self.data_device, &data_device_listener, self);
            
        } else {
            self.deinitPartial();
            return clipboard.ClipboardError.InitializationFailed;
        }
        
        _ = c.wl_display_roundtrip(self.display);
    }
    
    pub fn deinit(self: *WaylandClipboard) void {
        self.deinitPartial();
    }
    
    pub fn deinitWithoutDataCleanup(self: *WaylandClipboard) void {
        for (self.active_write_contexts.items) |context| {
            context.deinit();
        }
        self.active_write_contexts.deinit(self.allocator);
        
        if (self.own_clipboard_data) |data| {
            self.allocator.free(data);
        }
        
        self.available_formats.deinit(self.allocator);
        
        if (self.data_device) |device| {
            c.wl_data_device_destroy(device);
        }
        if (self.wlr_data_control_device) |device| {
            c.zwlr_data_control_device_v1_destroy(device);
        }
        if (self.seat) |seat| {
            c.wl_seat_destroy(seat);
        }
        if (self.data_device_manager) |manager| {
            c.wl_data_device_manager_destroy(manager);
        }
        if (self.wlr_data_control_manager) |manager| {
            c.zwlr_data_control_manager_v1_destroy(manager);
        }
        if (self.registry) |registry| {
            c.wl_registry_destroy(registry);
        }
        if (self.display) |display| {
            c.wl_display_disconnect(display);
        }
    }
    
    fn deinitPartial(self: *WaylandClipboard) void {
        for (self.active_write_contexts.items) |context| {
            context.deinit();
        }
        self.active_write_contexts.deinit(self.allocator);
        
        if (self.own_clipboard_data) |data| {
            self.allocator.free(data);
        }
        
        if (self.data_result) |*data| {
            data.deinit();
        }
        
        self.available_formats.deinit(self.allocator);
        
        if (self.data_device) |device| {
            c.wl_data_device_destroy(device);
        }
        if (self.wlr_data_control_device) |device| {
            c.zwlr_data_control_device_v1_destroy(device);
        }
        if (self.seat) |seat| {
            c.wl_seat_destroy(seat);
        }
        if (self.data_device_manager) |manager| {
            c.wl_data_device_manager_destroy(manager);
        }
        if (self.wlr_data_control_manager) |manager| {
            c.zwlr_data_control_manager_v1_destroy(manager);
        }
        if (self.registry) |registry| {
            c.wl_registry_destroy(registry);
        }
        if (self.display) |display| {
            c.wl_display_disconnect(display);
        }
    }
    
    pub fn read(self: *WaylandClipboard, format: clipboard.ClipboardFormat) !clipboard.ClipboardData {
        var temp_clipboard: WaylandClipboard = undefined;
        try temp_clipboard.init(self.allocator);
        defer temp_clipboard.deinit();
        
        // Multiple roundtrips to ensure we get all clipboard offer events
        //TODO: this looks ugly. see if it can be optimized
        _ = c.wl_display_roundtrip(temp_clipboard.display);
        _ = c.wl_display_roundtrip(temp_clipboard.display);
        _ = c.wl_display_roundtrip(temp_clipboard.display);
        
        return temp_clipboard.readFromCurrentOffer(format);
    }
    
    fn readFromCurrentOffer(self: *WaylandClipboard, format: clipboard.ClipboardFormat) !clipboard.ClipboardData {
        
        if (self.we_own_selection and self.own_clipboard_data != null) {
            if (self.own_clipboard_format == format) {
                const clipboard_data = try self.allocator.dupe(u8, self.own_clipboard_data.?);
                return clipboard.ClipboardData{
                    .data = clipboard_data,
                    .format = format,
                    .allocator = self.allocator,
                };
            } else {
                return clipboard.ClipboardError.InvalidData;
            }
        }
        
        const has_offer = switch (self.device_type) {
            .wl_data_device => self.current_offer_standard != null,
            .zwlr_data_control_device => self.current_offer_wlr != null,
        };
        
        
        if (!has_offer) {
            return clipboard.ClipboardError.NoData;
        }
        
        if (!self.isAvailable(format)) {
            return clipboard.ClipboardError.InvalidData;
        }
        
        var pipe_fds: [2]c_int = undefined;
        if (c.pipe(&pipe_fds) != 0) {
            return clipboard.ClipboardError.ReadFailed;
        }
        
        const mime_type = format.mimeType();
        const mime_cstr = try self.allocator.dupeZ(u8, mime_type);
        defer self.allocator.free(mime_cstr);
        
        switch (self.device_type) {
            .wl_data_device => {
                c.wl_data_offer_receive(self.current_offer_standard, mime_cstr.ptr, pipe_fds[1]);
            },
            .zwlr_data_control_device => {
                c.zwlr_data_control_offer_v1_receive(self.current_offer_wlr, mime_cstr.ptr, pipe_fds[1]);
            },
        }
        _ = c.close(pipe_fds[1]);
        
        _ = c.wl_display_roundtrip(self.display);
        
        const final_data = try readFromPipe(self.allocator, pipe_fds[0]);
        _ = c.close(pipe_fds[0]);
        
        return clipboard.ClipboardData{
            .data = final_data,
            .format = format,
            .allocator = self.allocator,
        };
    }
    
    pub fn write(self: *WaylandClipboard, data: []const u8, format: clipboard.ClipboardFormat) !void {
        if (self.own_clipboard_data) |old_data| {
            self.allocator.free(old_data);
        }
        
        self.own_clipboard_data = try self.allocator.dupe(u8, data);
        self.own_clipboard_format = format;
        
        switch (self.device_type) {
            .wl_data_device => {
                const source = c.wl_data_device_manager_create_data_source(self.data_device_manager);
                
                if (source == null) {
                    return clipboard.ClipboardError.WriteFailed;
                }
                
                if (format == .text) {
                    const text_plain = try self.allocator.dupeZ(u8, "text/plain");
                    defer self.allocator.free(text_plain);
                    const text_plain_utf8 = try self.allocator.dupeZ(u8, "text/plain;charset=utf-8");
                    defer self.allocator.free(text_plain_utf8);
                    const text_caps = try self.allocator.dupeZ(u8, "TEXT");
                    defer self.allocator.free(text_caps);
                    const string_caps = try self.allocator.dupeZ(u8, "STRING");
                    defer self.allocator.free(string_caps);
                    const utf8_string = try self.allocator.dupeZ(u8, "UTF8_STRING");
                    defer self.allocator.free(utf8_string);
                    
                    c.wl_data_source_offer(source, text_plain.ptr);
                    c.wl_data_source_offer(source, text_plain_utf8.ptr);
                    c.wl_data_source_offer(source, text_caps.ptr);
                    c.wl_data_source_offer(source, string_caps.ptr);
                    c.wl_data_source_offer(source, utf8_string.ptr);
                } else {
                    const mime_type = format.mimeType();
                    const mime_cstr = try self.allocator.dupeZ(u8, mime_type);
                    defer self.allocator.free(mime_cstr);
                    c.wl_data_source_offer(source, mime_cstr.ptr);
                }
                
                const source_listener = c.wl_data_source_listener{
                    .target = dataSourceTarget,
                    .send = dataSourceSend,
                    .cancelled = dataSourceCancelled,
                    .dnd_drop_performed = dataSourceDndDropPerformed,
                    .dnd_finished = dataSourceDndFinished,
                    .action = dataSourceAction,
                };
                
                const context = try self.allocator.create(WriteContext);
                context.* = WriteContext{
                    .data = try self.allocator.dupe(u8, data),
                    .allocator = self.allocator,
                    .parent = self,
                };
                
                try self.active_write_contexts.append(self.allocator, context);
                
                _ = c.wl_data_source_add_listener(source, &source_listener, context);
                c.wl_data_device_set_selection(self.data_device, source, 0);
            },
            .zwlr_data_control_device => {
                const source = c.zwlr_data_control_manager_v1_create_data_source(self.wlr_data_control_manager);
                
                if (source == null) {
                    return clipboard.ClipboardError.WriteFailed;
                }
                
                if (format == .text) {
                    const text_plain = try self.allocator.dupeZ(u8, "text/plain");
                    defer self.allocator.free(text_plain);
                    const text_plain_utf8 = try self.allocator.dupeZ(u8, "text/plain;charset=utf-8");
                    defer self.allocator.free(text_plain_utf8);
                    const text_caps = try self.allocator.dupeZ(u8, "TEXT");
                    defer self.allocator.free(text_caps);
                    const string_caps = try self.allocator.dupeZ(u8, "STRING");
                    defer self.allocator.free(string_caps);
                    const utf8_string = try self.allocator.dupeZ(u8, "UTF8_STRING");
                    defer self.allocator.free(utf8_string);
                    
                    c.zwlr_data_control_source_v1_offer(source, text_plain.ptr);
                    c.zwlr_data_control_source_v1_offer(source, text_plain_utf8.ptr);
                    c.zwlr_data_control_source_v1_offer(source, text_caps.ptr);
                    c.zwlr_data_control_source_v1_offer(source, string_caps.ptr);
                    c.zwlr_data_control_source_v1_offer(source, utf8_string.ptr);
                } else {
                    const mime_type = format.mimeType();
                    const mime_cstr = try self.allocator.dupeZ(u8, mime_type);
                    defer self.allocator.free(mime_cstr);
                    c.zwlr_data_control_source_v1_offer(source, mime_cstr.ptr);
                }
                
                const wlr_source_listener = c.zwlr_data_control_source_v1_listener{
                    .send = wlrDataSourceSend,
                    .cancelled = wlrDataSourceCancelled,
                };
                
                const context = try self.allocator.create(WriteContext);
                context.* = WriteContext{
                    .data = try self.allocator.dupe(u8, data),
                    .allocator = self.allocator,
                    .parent = self,
                };
                
                try self.active_write_contexts.append(self.allocator, context);
                
                _ = c.zwlr_data_control_source_v1_add_listener(source, &wlr_source_listener, context);
                c.zwlr_data_control_device_v1_set_selection(self.wlr_data_control_device, source);
            },
        }
        
        self.we_own_selection = true;
        
        _ = c.wl_display_roundtrip(self.display);
        
        try self.forkToBackground();
    }
    
    pub fn clear(self: *WaylandClipboard) !void {
        if (self.own_clipboard_data) |data| {
            self.allocator.free(data);
            self.own_clipboard_data = null;
        }
        self.own_clipboard_format = null;
        self.we_own_selection = false;
        
        switch (self.device_type) {
            .wl_data_device => {
                c.wl_data_device_set_selection(self.data_device, null, 0);
            },
            .zwlr_data_control_device => {
                c.zwlr_data_control_device_v1_set_selection(self.wlr_data_control_device, null);
            },
        }
        _ = c.wl_display_roundtrip(self.display);
    }
    
    
    pub fn isAvailable(self: *WaylandClipboard, format: clipboard.ClipboardFormat) bool {
        if (self.we_own_selection and self.own_clipboard_data != null) {
            return self.own_clipboard_format == format;
        }
        
        for (self.available_formats.items) |available_format| {
            if (available_format == format) {
                return true;
            }
        }
        return false;
    }
    
    pub fn getAvailableFormats(self: *WaylandClipboard, allocator: std.mem.Allocator) ![]clipboard.ClipboardFormat {
        if (self.we_own_selection and self.own_clipboard_data != null) {
            var formats = try allocator.alloc(clipboard.ClipboardFormat, 1);
            formats[0] = self.own_clipboard_format.?;
            return formats;
        }
        
        return try allocator.dupe(clipboard.ClipboardFormat, self.available_formats.items);
    }
    
    pub fn processEvents(self: *WaylandClipboard) void {
        _ = c.wl_display_dispatch(self.display);
    }
    
    fn readFromPipe(allocator: std.mem.Allocator, pipe_fd: c_int) ![]u8 {
        var data_list = std.ArrayList(u8){};
        defer data_list.deinit(allocator);
        
        var buffer: [4096]u8 = undefined;
        var total_read: usize = 0;
        
        while (true) {
            const bytes_read = c.read(pipe_fd, &buffer, buffer.len);
            if (bytes_read < 0) {
                return clipboard.ClipboardError.ReadFailed;
            }
            if (bytes_read == 0) break;
            
            try data_list.appendSlice(allocator, buffer[0..@intCast(bytes_read)]);
            total_read += @intCast(bytes_read);
        }
        
        if (total_read == 0) {
            return clipboard.ClipboardError.NoData;
        }
        
        return try allocator.dupe(u8, data_list.items);
    }
    
    fn forkToBackground(self: *WaylandClipboard) !void {
        const pid = std.posix.fork() catch |err| switch (err) {
            error.SystemResources => return,
            else => return,
        };
        
        if (pid > 0) {
            return;
        }
        
        const dev_null = std.fs.openFileAbsolute("/dev/null", .{}) catch {
            std.posix.close(0);
            std.posix.close(1);
            self.backgroundEventLoop();
        };
        defer dev_null.close();
        
        _ = std.posix.dup2(dev_null.handle, 0) catch {};
        _ = std.posix.dup2(dev_null.handle, 1) catch {};
        
        _ = std.posix.chdir("/") catch {};
        
        self.backgroundEventLoop();
    }
    
    fn backgroundEventLoop(self: *WaylandClipboard) noreturn {
        while (true) {
            const result = c.wl_display_dispatch(self.display);
            if (result < 0) {
                c.exit(1);
            }
        }
    }
    
    
    
    fn readWithSpecificMimeType(self: *WaylandClipboard, mime_type: []const u8, format: clipboard.ClipboardFormat) !clipboard.ClipboardData {
        
        const has_offer = switch (self.device_type) {
            .wl_data_device => self.current_offer_standard != null,
            .zwlr_data_control_device => self.current_offer_wlr != null,
        };
        
        
        if (!has_offer) {
            return clipboard.ClipboardError.NoData;
        }
        
        var pipe_fds: [2]c_int = undefined;
        if (c.pipe(&pipe_fds) != 0) {
            return clipboard.ClipboardError.ReadFailed;
        }
        
        const mime_cstr = try self.allocator.dupeZ(u8, mime_type);
        defer self.allocator.free(mime_cstr);
        
        
        switch (self.device_type) {
            .wl_data_device => {
                c.wl_data_offer_receive(self.current_offer_standard, mime_cstr.ptr, pipe_fds[1]);
            },
            .zwlr_data_control_device => {
                c.zwlr_data_control_offer_v1_receive(self.current_offer_wlr, mime_cstr.ptr, pipe_fds[1]);
            },
        }
        _ = c.close(pipe_fds[1]);
        
        _ = c.wl_display_roundtrip(self.display);
        
        const final_data = try readFromPipe(self.allocator, pipe_fds[0]);
        _ = c.close(pipe_fds[0]);
        
        return clipboard.ClipboardData{
            .data = final_data,
            .format = format,
            .allocator = self.allocator,
        };
    }
    
    fn processOfferImmediately(self: *WaylandClipboard) !void {
        var chosen_mime_type: ?[]const u8 = null;
        var chosen_format: clipboard.ClipboardFormat = .text;
        
        for (self.available_formats.items) |format| {
            switch (format) {
                .text => {
                    chosen_mime_type = "text/plain;charset=utf-8"; 
                    chosen_format = .text;
                    break;
                },
                .image => {
                    chosen_mime_type = "image/png";
                    chosen_format = .image;
                    if (chosen_mime_type == null) break; 
                },
                .html => {
                    chosen_mime_type = "text/html";
                    chosen_format = .html;
                    if (chosen_mime_type == null) break;
                },
                .rtf => {
                    chosen_mime_type = "application/rtf";
                    chosen_format = .rtf;
                    if (chosen_mime_type == null) break;
                },
            }
        }
        
        
        if (chosen_mime_type) |mime_type| {
            self.data_result = self.readWithSpecificMimeType(mime_type, chosen_format) catch |err| {
                self.data_error = err;
                return;
            };
        } else {
            self.data_error = clipboard.ClipboardError.NoData;
        }
    }
};

const WriteContext = struct {
    data: []u8,
    allocator: std.mem.Allocator,
    parent: *WaylandClipboard,
    
    fn deinit(self: *WriteContext) void {
        if (self.data.len > 0) {
            self.allocator.free(self.data);
        }
        
        if (self.parent.active_write_contexts.items.len > 0) {
            for (self.parent.active_write_contexts.items, 0..) |context, i| {
                if (context == self) {
                    _ = self.parent.active_write_contexts.swapRemove(i);
                    break;
                }
            }
        }
        
        self.allocator.destroy(self);
    }
};

fn registryGlobal(data: ?*anyopaque, registry: ?*c.wl_registry, name: u32, interface: [*c]const u8, version: u32) callconv(.c) void {
    _ = version;
    const self: *WaylandClipboard = @ptrCast(@alignCast(data));
    
    if (c.strcmp(interface, c.zwlr_data_control_manager_v1_interface.name) == 0) {
        self.wlr_data_control_manager = @ptrCast(c.wl_registry_bind(registry, name, &c.zwlr_data_control_manager_v1_interface, 2));
    } else if (c.strcmp(interface, c.wl_data_device_manager_interface.name) == 0) {
        self.data_device_manager = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_data_device_manager_interface, 3));
    } else if (c.strcmp(interface, c.wl_seat_interface.name) == 0) {
        self.seat = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_seat_interface, 1));
    }
}

fn registryGlobalRemove(data: ?*anyopaque, registry: ?*c.wl_registry, name: u32) callconv(.c) void {
    _ = data;
    _ = registry;
    _ = name;
}

fn wlrDataDeviceDataOffer(data: ?*anyopaque, device: ?*c.zwlr_data_control_device_v1, offer: ?*c.zwlr_data_control_offer_v1) callconv(.c) void {
    _ = device;
    const self: *WaylandClipboard = @ptrCast(@alignCast(data));
    
    
    self.available_formats.clearRetainingCapacity();
    self.offer_mime_types_received = false;
    
    c.wl_proxy_set_user_data(@ptrCast(offer), self);
    
    const offer_listener = c.zwlr_data_control_offer_v1_listener{
        .offer = wlrDataOfferOffer,
    };
    
    _ = c.zwlr_data_control_offer_v1_add_listener(offer, &offer_listener, self);
}

fn wlrDataDeviceSelection(data: ?*anyopaque, device: ?*c.zwlr_data_control_device_v1, offer: ?*c.zwlr_data_control_offer_v1) callconv(.c) void {
    _ = device;
    const self: *WaylandClipboard = @ptrCast(@alignCast(data));
    
    if (self.offer_received) {
        return;
    }
    
    self.current_offer_wlr = offer;
    self.selection_received = true;
    
    if (offer != null) {
        self.we_own_selection = false;
        self.offer_received = true;
        
        self.processOfferImmediately() catch |err| {
            self.data_error = err;
        };
    } else {
        self.data_error = clipboard.ClipboardError.NoData;
    }
}

fn wlrDataDeviceFinished(data: ?*anyopaque, device: ?*c.zwlr_data_control_device_v1) callconv(.c) void {
    _ = data; _ = device;
}

fn wlrDataDevicePrimarySelection(data: ?*anyopaque, device: ?*c.zwlr_data_control_device_v1, offer: ?*c.zwlr_data_control_offer_v1) callconv(.c) void {
    _ = data; _ = device; _ = offer;
    // Primary selection not implemented
    // TODO: check if this needs to be implemented?
}

fn wlrDataOfferOffer(data: ?*anyopaque, offer: ?*c.zwlr_data_control_offer_v1, mime_type: [*c]const u8) callconv(.c) void {
    _ = offer;
    
    const self: *WaylandClipboard = @ptrCast(@alignCast(data));
    const mime_str = std.mem.span(mime_type);
    
    
    const format_to_add = mimeTypeToFormat(mime_str);
    
    if (format_to_add) |format| {
        for (self.available_formats.items) |existing_format| {
            if (existing_format == format) {
                return;
            }
        }
        self.available_formats.append(self.allocator, format) catch {};
    }
    
    self.offer_mime_types_received = true;
}

fn wlrDataSourceSend(data: ?*anyopaque, source: ?*c.zwlr_data_control_source_v1, mime_type: [*c]const u8, fd: i32) callconv(.c) void {
    _ = source; _ = mime_type;
    
    if (data == null) {
        _ = c.close(fd);
        return;
    }
    
    const context: *WriteContext = @ptrCast(@alignCast(data));
    
    _ = c.fcntl(fd, c.F_SETFL, @as(c_int, 0));
    
    const file = c.fdopen(fd, "wb");
    if (file == null) {
        _ = c.close(fd);
        return;
    }
    
    _ = c.fwrite(context.data.ptr, 1, context.data.len, file);
    _ = c.fclose(file); 
}

fn wlrDataSourceCancelled(data: ?*anyopaque, source: ?*c.zwlr_data_control_source_v1) callconv(.c) void {
    _ = source; _ = data;
    
    c.exit(0);
}

fn dataDeviceDataOffer(data: ?*anyopaque, device: ?*c.wl_data_device, offer: ?*c.wl_data_offer) callconv(.c) void {
    _ = device;
    const self: *WaylandClipboard = @ptrCast(@alignCast(data));
    
    self.available_formats.clearRetainingCapacity();
    self.offer_mime_types_received = false;
    
    c.wl_proxy_set_user_data(@ptrCast(offer), self);
    
    const offer_listener = c.wl_data_offer_listener{
        .offer = dataOfferOffer,
        .source_actions = dataOfferSourceActions,
        .action = dataOfferAction,
    };
    
    _ = c.wl_data_offer_add_listener(offer, &offer_listener, self);
}

fn dataDeviceSelection(data: ?*anyopaque, device: ?*c.wl_data_device, offer: ?*c.wl_data_offer) callconv(.c) void {
    _ = device;
    const self: *WaylandClipboard = @ptrCast(@alignCast(data));
    
    if (self.offer_received) {
        return;
    }
    
    self.current_offer_standard = offer;
    self.selection_received = true;
    
    if (offer != null) {
        self.we_own_selection = false;
        self.offer_received = true;
        
        self.processOfferImmediately() catch |err| {
            self.data_error = err;
        };
    } else {
        self.data_error = clipboard.ClipboardError.NoData;
    }
}

fn dataOfferOffer(data: ?*anyopaque, offer: ?*c.wl_data_offer, mime_type: [*c]const u8) callconv(.c) void {
    _ = offer;
    const self: *WaylandClipboard = @ptrCast(@alignCast(data));
    
    const mime_str = std.mem.span(mime_type);
    
    
    const format_to_add = mimeTypeToFormat(mime_str);
    
    if (format_to_add) |format| {
        for (self.available_formats.items) |existing_format| {
            if (existing_format == format) {
                return;
            }
        }
        self.available_formats.append(self.allocator, format) catch {};
    }
    
    self.offer_mime_types_received = true;
}

fn dataDeviceEnter(data: ?*anyopaque, device: ?*c.wl_data_device, serial: u32, surface: ?*c.wl_surface, x: c.wl_fixed_t, y: c.wl_fixed_t, offer: ?*c.wl_data_offer) callconv(.c) void {
    _ = data; _ = device; _ = serial; _ = surface; _ = x; _ = y; _ = offer;
}

fn dataDeviceLeave(data: ?*anyopaque, device: ?*c.wl_data_device) callconv(.c) void {
    _ = data; _ = device;
}

fn dataDeviceMotion(data: ?*anyopaque, device: ?*c.wl_data_device, time: u32, x: c.wl_fixed_t, y: c.wl_fixed_t) callconv(.c) void {
    _ = data; _ = device; _ = time; _ = x; _ = y;
}

fn dataDeviceDrop(data: ?*anyopaque, device: ?*c.wl_data_device) callconv(.c) void {
    _ = data; _ = device;
}

fn dataOfferSourceActions(data: ?*anyopaque, offer: ?*c.wl_data_offer, source_actions: u32) callconv(.c) void {
    _ = data; _ = offer; _ = source_actions;
}

fn dataOfferAction(data: ?*anyopaque, offer: ?*c.wl_data_offer, dnd_action: u32) callconv(.c) void {
    _ = data; _ = offer; _ = dnd_action;
}

fn dataSourceTarget(data: ?*anyopaque, source: ?*c.wl_data_source, mime_type: [*c]const u8) callconv(.c) void {
    _ = data; _ = source; _ = mime_type;
}

fn dataSourceSend(data: ?*anyopaque, source: ?*c.wl_data_source, mime_type: [*c]const u8, fd: i32) callconv(.c) void {
    _ = source; _ = mime_type;
    
    if (data == null) {
        _ = c.close(fd);
        return;
    }
    
    const context: *WriteContext = @ptrCast(@alignCast(data));
    
    _ = c.fcntl(fd, c.F_SETFL, @as(c_int, 0));
    
    const file = c.fdopen(fd, "wb");
    if (file == null) {
        _ = c.close(fd);
        return;
    }
    
    _ = c.fwrite(context.data.ptr, 1, context.data.len, file);
    _ = c.fclose(file); 
}

fn dataSourceCancelled(data: ?*anyopaque, source: ?*c.wl_data_source) callconv(.c) void {
    _ = source; _ = data;
    
    c.exit(0);
}

fn dataSourceDndDropPerformed(data: ?*anyopaque, source: ?*c.wl_data_source) callconv(.c) void {
    _ = data; _ = source;
}

fn dataSourceDndFinished(data: ?*anyopaque, source: ?*c.wl_data_source) callconv(.c) void {
    _ = data; _ = source;
}

fn dataSourceAction(data: ?*anyopaque, source: ?*c.wl_data_source, dnd_action: u32) callconv(.c) void {
    _ = data; _ = source; _ = dnd_action;
}

pub fn getAvailableClipboardFormats(allocator: std.mem.Allocator) ![]clipboard.ClipboardFormat {
    var temp_clipboard: WaylandClipboard = undefined;
    try temp_clipboard.init(allocator);
    defer temp_clipboard.deinit();
    
    
    var rounds: u32 = 0;
    while (rounds < 10) { 
        _ = c.wl_display_roundtrip(temp_clipboard.display);
        
        if (temp_clipboard.selection_received and temp_clipboard.offer_mime_types_received) {
            _ = c.wl_display_roundtrip(temp_clipboard.display);
            break;
        }
        rounds += 1;
    }
    
    
    return temp_clipboard.getAvailableFormats(allocator);
}

pub fn getClipboardDataWithAutoFormat(allocator: std.mem.Allocator) !clipboard.ClipboardData {
    var temp_clipboard: WaylandClipboard = undefined;
    temp_clipboard.init(allocator) catch |err| {
        return err;
    };
    defer temp_clipboard.deinitWithoutDataCleanup();
    
    if (temp_clipboard.data_result) |result| {
        temp_clipboard.data_result = null;
        return result;
    }
    if (temp_clipboard.data_error) |err| {
        return err;
    }
    
    if (c.wl_display_dispatch(temp_clipboard.display) >= 0) {
        if (temp_clipboard.data_result) |result| {
            temp_clipboard.data_result = null;
            return result;
        }
        if (temp_clipboard.data_error) |err| {
            return err;
        }
    }
    
    return clipboard.ClipboardError.NoData;
}
