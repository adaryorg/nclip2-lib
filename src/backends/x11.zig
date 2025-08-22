const std = @import("std");
const clipboard = @import("../clipboard.zig");
const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xatom.h");
    @cInclude("X11/Xmu/Atoms.h");
});

pub const X11Clipboard = struct {
    display: *c.Display,
    window: c.Window,
    clipboard_atom: c.Atom,
    primary_atom: c.Atom,
    utf8_atom: c.Atom,
    targets_atom: c.Atom,
    text_atom: c.Atom,
    image_atom: c.Atom,
    html_atom: c.Atom,
    rtf_atom: c.Atom,
    allocator: std.mem.Allocator,
    monitoring: bool,
    monitor_callback: ?clipboard.ClipboardChangeCallback,
    last_selection_owner: c.Window,
    
    pub fn init(allocator: std.mem.Allocator) !X11Clipboard {
        const display = c.XOpenDisplay(null);
        if (display == null) {
            return clipboard.ClipboardError.InitializationFailed;
        }
        
        const screen = c.DefaultScreen(display);
        const window = c.XCreateSimpleWindow(
            display,
            c.RootWindow(display, screen),
            0, 0, 1, 1, 0,
            c.BlackPixel(display, screen),
            c.WhitePixel(display, screen)
        );
        
        const clipboard_atom = c.XInternAtom(display, "CLIPBOARD", c.False);
        const primary_atom = c.XA_PRIMARY;
        const utf8_atom = c.XInternAtom(display, "UTF8_STRING", c.False);
        const targets_atom = c.XInternAtom(display, "TARGETS", c.False);
        const text_atom = c.XInternAtom(display, "text/plain", c.False);
        const image_atom = c.XInternAtom(display, "image/png", c.False);
        const html_atom = c.XInternAtom(display, "text/html", c.False);
        const rtf_atom = c.XInternAtom(display, "application/rtf", c.False);
        
        return X11Clipboard{
            .display = display.?,
            .window = window,
            .clipboard_atom = clipboard_atom,
            .primary_atom = primary_atom,
            .utf8_atom = utf8_atom,
            .targets_atom = targets_atom,
            .text_atom = text_atom,
            .image_atom = image_atom,
            .html_atom = html_atom,
            .rtf_atom = rtf_atom,
            .allocator = allocator,
            .monitoring = false,
            .monitor_callback = null,
            .last_selection_owner = c.None,
        };
    }
    
    pub fn deinit(self: *X11Clipboard) void {
        _ = c.XDestroyWindow(self.display, self.window);
        _ = c.XCloseDisplay(self.display);
    }
    
    pub fn read(self: *X11Clipboard, format: clipboard.ClipboardFormat) !clipboard.ClipboardData {
        const selection_atom = self.clipboard_atom;
        const target_atom = self.getAtomForFormat(format);
        
        const selection_owner = c.XGetSelectionOwner(self.display, selection_atom);
        if (selection_owner == c.None) {
            return clipboard.ClipboardError.NoData;
        }
        
        // Request conversion
        _ = c.XConvertSelection(
            self.display,
            selection_atom,
            target_atom,
            selection_atom,
            self.window,
            c.CurrentTime
        );
        
        _ = c.XFlush(self.display);
        
        // Wait for SelectionNotify event
        var event: c.XEvent = undefined;
        var timeout_counter: u32 = 0;
        const max_timeout = 1000; // 1 second timeout
        
        while (timeout_counter < max_timeout) {
            if (c.XCheckTypedWindowEvent(self.display, self.window, c.SelectionNotify, &event) == c.True) {
                break;
            }
            std.time.sleep(1000000); // 1ms
            timeout_counter += 1;
        }
        
        if (timeout_counter >= max_timeout) {
            return clipboard.ClipboardError.Timeout;
        }
        
        if (event.xselection.property == c.None) {
            return clipboard.ClipboardError.NoData;
        }
        
        // Get the data
        var actual_type: c.Atom = undefined;
        var actual_format: c_int = undefined;
        var nitems: c_ulong = undefined;
        var bytes_after: c_ulong = undefined;
        var prop_data: [*c]u8 = undefined;
        
        const result = c.XGetWindowProperty(
            self.display,
            self.window,
            selection_atom,
            0,
            0x7fffffff, // Large number to get all data
            c.False,
            c.AnyPropertyType,
            &actual_type,
            &actual_format,
            &nitems,
            &bytes_after,
            &prop_data
        );
        
        if (result != c.Success or prop_data == null) {
            return clipboard.ClipboardError.ReadFailed;
        }
        
        const data_len = @as(usize, @intCast(nitems));
        if (data_len == 0) {
            _ = c.XFree(prop_data);
            return clipboard.ClipboardError.NoData;
        }
        
        const clipboard_data = try self.allocator.dupe(u8, prop_data[0..data_len]);
        
        _ = c.XFree(prop_data);
        _ = c.XDeleteProperty(self.display, self.window, selection_atom);
        
        return clipboard.ClipboardData{
            .data = clipboard_data,
            .format = format,
            .allocator = self.allocator,
        };
    }
    
    pub fn write(self: *X11Clipboard, data: []const u8, format: clipboard.ClipboardFormat) !void {
        // Set selection owner
        _ = c.XSetSelectionOwner(self.display, self.clipboard_atom, self.window, c.CurrentTime);
        
        if (c.XGetSelectionOwner(self.display, self.clipboard_atom) != self.window) {
            return clipboard.ClipboardError.WriteFailed;
        }
        
        // Store data in window property for later retrieval
        const target_atom = self.getAtomForFormat(format);
        _ = c.XChangeProperty(
            self.display,
            self.window,
            self.clipboard_atom,
            target_atom,
            8,
            c.PropModeReplace,
            data.ptr,
            @intCast(data.len)
        );
        
        // Also set primary selection for terminal compatibility
        _ = c.XSetSelectionOwner(self.display, self.primary_atom, self.window, c.CurrentTime);
        _ = c.XChangeProperty(
            self.display,
            self.window,
            self.primary_atom,
            target_atom,
            8,
            c.PropModeReplace,
            data.ptr,
            @intCast(data.len)
        );
        
        _ = c.XFlush(self.display);
    }
    
    pub fn startMonitoring(self: *X11Clipboard, callback: clipboard.ClipboardChangeCallback) !void {
        self.monitor_callback = callback;
        self.monitoring = true;
        self.last_selection_owner = c.XGetSelectionOwner(self.display, self.clipboard_atom);
        
        // Start monitoring thread
        const thread = try std.Thread.spawn(.{}, monitorThread, .{self});
        thread.detach();
    }
    
    pub fn stopMonitoring(self: *X11Clipboard) void {
        self.monitoring = false;
        self.monitor_callback = null;
    }
    
    pub fn isAvailable(self: *X11Clipboard, format: clipboard.ClipboardFormat) bool {
        const selection_owner = c.XGetSelectionOwner(self.display, self.clipboard_atom);
        if (selection_owner == c.None) {
            return false;
        }
        
        // Request targets to check available formats
        _ = c.XConvertSelection(
            self.display,
            self.clipboard_atom,
            self.targets_atom,
            self.targets_atom,
            self.window,
            c.CurrentTime
        );
        
        _ = c.XFlush(self.display);
        
        var event: c.XEvent = undefined;
        var timeout_counter: u32 = 0;
        const max_timeout = 100; // Shorter timeout for availability check
        
        while (timeout_counter < max_timeout) {
            if (c.XCheckTypedWindowEvent(self.display, self.window, c.SelectionNotify, &event) == c.True) {
                break;
            }
            std.time.sleep(1000000); // 1ms
            timeout_counter += 1;
        }
        
        if (timeout_counter >= max_timeout or event.xselection.property == c.None) {
            return false;
        }
        
        // Check if our target format is in the targets list
        var actual_type: c.Atom = undefined;
        var actual_format: c_int = undefined;
        var nitems: c_ulong = undefined;
        var bytes_after: c_ulong = undefined;
        var prop_data: [*c]c.Atom = undefined;
        
        const result = c.XGetWindowProperty(
            self.display,
            self.window,
            self.targets_atom,
            0,
            0x7fffffff,
            c.False,
            c.XA_ATOM,
            &actual_type,
            &actual_format,
            &nitems,
            &bytes_after,
            @ptrCast(&prop_data)
        );
        
        if (result != c.Success or prop_data == null) {
            return false;
        }
        
        const target_atom = self.getAtomForFormat(format);
        var found = false;
        
        for (0..@intCast(nitems)) |i| {
            if (prop_data[i] == target_atom) {
                found = true;
                break;
            }
        }
        
        _ = c.XFree(prop_data);
        _ = c.XDeleteProperty(self.display, self.window, self.targets_atom);
        
        return found;
    }
    
    pub fn getAvailableFormats(self: *X11Clipboard, allocator: std.mem.Allocator) ![]clipboard.ClipboardFormat {
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
    
    pub fn clear(self: *X11Clipboard) !void {
        _ = c.XSetSelectionOwner(self.display, self.clipboard_atom, c.None, c.CurrentTime);
        _ = c.XSetSelectionOwner(self.display, self.primary_atom, c.None, c.CurrentTime);
        _ = c.XFlush(self.display);
    }
    
    fn getAtomForFormat(self: *X11Clipboard, format: clipboard.ClipboardFormat) c.Atom {
        return switch (format) {
            .text => self.utf8_atom,
            .image => self.image_atom,
            .html => self.html_atom,
            .rtf => self.rtf_atom,
        };
    }
    
    pub fn processEvents(self: *X11Clipboard) void {
        // X11 uses polling, so no event processing needed
        _ = self;
    }
    
    fn monitorThread(self: *X11Clipboard) void {
        while (self.monitoring) {
            const current_owner = c.XGetSelectionOwner(self.display, self.clipboard_atom);
            
            if (current_owner != self.last_selection_owner) {
                self.last_selection_owner = current_owner;
                
                if (current_owner != c.None and self.monitor_callback != null) {
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