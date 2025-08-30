const std = @import("std");
const clipboard = @import("../clipboard.zig");
const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xatom.h");
    @cInclude("unistd.h");
    @cInclude("string.h");
    @cInclude("sys/select.h");
});

// Context states for reading from clipboard
const ReadContext = enum {
    none,
    sent_conversion_request,
    incr_transfer,
    bad_target,
};

// Context states for writing to clipboard
const WriteContext = enum {
    none,
    selection_request,
    incr_transfer,
};

// Structure to track requestors during INCR transfers
const Requestor = struct {
    window: c.Window,
    property: c.Atom,
    context: WriteContext,
    position: usize,
    chunk_size: usize,
    next: ?*Requestor,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, window: c.Window, property: c.Atom) !*Requestor {
        const requestor = try allocator.create(Requestor);
        requestor.* = Requestor{
            .window = window,
            .property = property,
            .context = .none,
            .position = 0,
            .chunk_size = 0,
            .next = null,
            .allocator = allocator,
        };
        return requestor;
    }
    
    pub fn deinit(self: *Requestor) void {
        self.allocator.destroy(self);
    }
};

pub const X11Clipboard = struct {
    // Core X11 resources
    display: *c.Display,
    window: c.Window,
    
    // Selection atoms
    clipboard_atom: c.Atom,
    primary_atom: c.Atom,
    
    // Protocol atoms
    targets_atom: c.Atom,
    incr_atom: c.Atom,
    property_atom: c.Atom, // Custom property for transfers
    
    // Format atoms
    utf8_atom: c.Atom,
    string_atom: c.Atom,
    text_atom: c.Atom,
    image_png_atom: c.Atom,
    image_jpeg_atom: c.Atom,
    image_gif_atom: c.Atom,
    image_bmp_atom: c.Atom,
    image_avif_atom: c.Atom,
    image_jxl_atom: c.Atom,
    image_tiff_atom: c.Atom,
    image_webp_atom: c.Atom,
    text_html_atom: c.Atom,
    text_plain_atom: c.Atom,
    
    // State tracking
    read_context: ReadContext,
    write_context: WriteContext,
    
    // Data storage for serving clipboard
    clipboard_data: ?[]u8,
    clipboard_format: ?clipboard.ClipboardFormat,
    owns_selection: bool,
    
    // INCR transfer state
    chunk_size: usize,
    requestors: ?*Requestor,
    
    
    // Memory management
    allocator: std.mem.Allocator,
    should_close_display: bool,
    
    pub fn init(allocator: std.mem.Allocator) !X11Clipboard {
        const display = c.XOpenDisplay(null);
        if (display == null) {
            return clipboard.ClipboardError.InitializationFailed;
        }
        errdefer _ = c.XCloseDisplay(display);
        
        const screen = c.DefaultScreen(display);
        const window = c.XCreateSimpleWindow(
            display,
            c.RootWindow(display, screen),
            0, 0, 1, 1, 0,
            c.BlackPixel(display, screen),
            c.WhitePixel(display, screen)
        );
        errdefer _ = c.XDestroyWindow(display, window);
        
        // Don't map window - we only need it for clipboard protocol
        // Mapping creates visible interference with user interface
        
        // Create all necessary atoms
        const clipboard_atom = c.XInternAtom(display, "CLIPBOARD", c.False);
        const primary_atom = c.XA_PRIMARY;
        const targets_atom = c.XInternAtom(display, "TARGETS", c.False);
        const incr_atom = c.XInternAtom(display, "INCR", c.False);
        const property_atom = c.XInternAtom(display, "XCLIP_OUT", c.False);
        const utf8_atom = c.XInternAtom(display, "UTF8_STRING", c.False);
        const string_atom = c.XA_STRING;
        const text_atom = c.XInternAtom(display, "TEXT", c.False);
        const image_png_atom = c.XInternAtom(display, "image/png", c.False);
        const image_jpeg_atom = c.XInternAtom(display, "image/jpeg", c.False);
        const image_gif_atom = c.XInternAtom(display, "image/gif", c.False);
        const image_bmp_atom = c.XInternAtom(display, "image/bmp", c.False);
        const image_avif_atom = c.XInternAtom(display, "image/avif", c.False);
        const image_jxl_atom = c.XInternAtom(display, "image/jxl", c.False);
        const image_tiff_atom = c.XInternAtom(display, "image/tiff", c.False);
        const image_webp_atom = c.XInternAtom(display, "image/webp", c.False);
        const text_html_atom = c.XInternAtom(display, "text/html", c.False);
        const text_plain_atom = c.XInternAtom(display, "text/plain", c.False);
        
        // Calculate chunk size for INCR transfers (1/4 of max request size)
        var chunk_size = @as(usize, @intCast(c.XExtendedMaxRequestSize(display))) / 4;
        if (chunk_size == 0) {
            chunk_size = @as(usize, @intCast(c.XMaxRequestSize(display))) / 4;
        }
        if (chunk_size == 0) {
            chunk_size = 4096; // Fallback to 4KB chunks
        }
        
        return X11Clipboard{
            .display = display.?,
            .window = window,
            .clipboard_atom = clipboard_atom,
            .primary_atom = primary_atom,
            .targets_atom = targets_atom,
            .incr_atom = incr_atom,
            .property_atom = property_atom,
            .utf8_atom = utf8_atom,
            .string_atom = string_atom,
            .text_atom = text_atom,
            .image_png_atom = image_png_atom,
            .image_jpeg_atom = image_jpeg_atom,
            .image_gif_atom = image_gif_atom,
            .image_bmp_atom = image_bmp_atom,
            .image_avif_atom = image_avif_atom,
            .image_jxl_atom = image_jxl_atom,
            .image_tiff_atom = image_tiff_atom,
            .image_webp_atom = image_webp_atom,
            .text_html_atom = text_html_atom,
            .text_plain_atom = text_plain_atom,
            .read_context = .none,
            .write_context = .none,
            .clipboard_data = null,
            .clipboard_format = null,
            .owns_selection = false,
            .chunk_size = chunk_size,
            .requestors = null,
            .allocator = allocator,
            .should_close_display = true,
        };
    }
    
    pub fn deinit(self: *X11Clipboard) void {
        // Clean up requestor list
        var requestor = self.requestors;
        while (requestor) |r| {
            const next = r.next;
            r.deinit();
            requestor = next;
        }
        
        // Free clipboard data
        if (self.clipboard_data) |data| {
            self.allocator.free(data);
        }
        
        // Release selection ownership
        if (self.owns_selection) {
            _ = c.XSetSelectionOwner(self.display, self.clipboard_atom, c.None, c.CurrentTime);
            _ = c.XSetSelectionOwner(self.display, self.primary_atom, c.None, c.CurrentTime);
        }
        
        // Clean up X11 resources
        if (self.should_close_display) {
            _ = c.XDestroyWindow(self.display, self.window);
            _ = c.XCloseDisplay(self.display);
        }
    }
    
    pub fn read(self: *X11Clipboard, format: clipboard.ClipboardFormat) !clipboard.ClipboardData {
        const selection_atom = self.clipboard_atom;
        const target_atom = self.getAtomForFormat(format);
        
        // Check if there's a selection owner
        const selection_owner = c.XGetSelectionOwner(self.display, selection_atom);
        if (selection_owner == c.None) {
            return clipboard.ClipboardError.NoData;
        }
        
        // If we own the selection, return our data
        if (selection_owner == self.window and self.clipboard_data != null) {
            if (self.clipboard_format == format) {
                const data_copy = try self.allocator.dupe(u8, self.clipboard_data.?);
                return clipboard.ClipboardData{
                    .data = data_copy,
                    .format = format,
                    .allocator = self.allocator,
                };
            }
            return clipboard.ClipboardError.InvalidData;
        }
        
        // Request the selection
        _ = c.XConvertSelection(
            self.display,
            selection_atom,
            target_atom,
            self.property_atom,
            self.window,
            c.CurrentTime
        );
        _ = c.XFlush(self.display);
        
        // Wait for SelectionNotify event
        var event: c.XEvent = undefined;
        const timeout_ms = 1000; // 1 second timeout
        const start_time = std.time.milliTimestamp();
        
        while (std.time.milliTimestamp() - start_time < timeout_ms) {
            if (c.XPending(self.display) > 0) {
                _ = c.XNextEvent(self.display, &event);
                
                if (event.type == c.SelectionNotify) {
                    if (event.xselection.property == c.None) {
                        return clipboard.ClipboardError.NoData;
                    }
                    
                    // Read the property
                    return try self.readProperty();
                }
            }
            std.time.sleep(1 * std.time.ns_per_ms);
        }
        
        return clipboard.ClipboardError.Timeout;
    }
    
    fn readProperty(self: *X11Clipboard) !clipboard.ClipboardData {
        var actual_type: c.Atom = undefined;
        var actual_format: c_int = undefined;
        var nitems: c_ulong = undefined;
        var bytes_after: c_ulong = undefined;
        var prop_data: [*c]u8 = undefined;
        
        // First, check the property type and size
        var result = c.XGetWindowProperty(
            self.display,
            self.window,
            self.property_atom,
            0, 0, // Get 0 bytes to check type
            c.False,
            c.AnyPropertyType,
            &actual_type,
            &actual_format,
            &nitems,
            &bytes_after,
            &prop_data
        );
        
        if (result != c.Success) {
            return clipboard.ClipboardError.ReadFailed;
        }
        
        _ = c.XFree(prop_data);
        
        // Check if this is an INCR transfer
        if (actual_type == self.incr_atom) {
            return try self.readIncr();
        }
        
        // Regular property read
        result = c.XGetWindowProperty(
            self.display,
            self.window,
            self.property_atom,
            0,
            @as(c_long, @intCast(bytes_after)),
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
        defer _ = c.XFree(prop_data);
        
        const data_len = @as(usize, @intCast(nitems));
        if (data_len == 0) {
            return clipboard.ClipboardError.NoData;
        }
        
        const clipboard_data = try self.allocator.dupe(u8, prop_data[0..data_len]);
        
        // Delete the property
        _ = c.XDeleteProperty(self.display, self.window, self.property_atom);
        
        // Determine format from atom type
        const format = self.getFormatFromAtom(actual_type);
        
        return clipboard.ClipboardData{
            .data = clipboard_data,
            .format = format,
            .allocator = self.allocator,
        };
    }
    
    fn readIncr(self: *X11Clipboard) !clipboard.ClipboardData {
        // Start INCR transfer by deleting the property
        _ = c.XDeleteProperty(self.display, self.window, self.property_atom);
        _ = c.XFlush(self.display);
        
        var data = std.ArrayList(u8).init(self.allocator);
        defer data.deinit();
        
        var event: c.XEvent = undefined;
        const timeout_ms = 5000; // 5 second timeout for INCR
        const start_time = std.time.milliTimestamp();
        
        while (std.time.milliTimestamp() - start_time < timeout_ms) {
            if (c.XPending(self.display) > 0) {
                _ = c.XNextEvent(self.display, &event);
                
                if (event.type == c.PropertyNotify and 
                    event.xproperty.state == c.PropertyNewValue and
                    event.xproperty.atom == self.property_atom) {
                    
                    // Read the chunk
                    var actual_type: c.Atom = undefined;
                    var actual_format: c_int = undefined;
                    var nitems: c_ulong = undefined;
                    var bytes_after: c_ulong = undefined;
                    var prop_data: [*c]u8 = undefined;
                    
                    const result = c.XGetWindowProperty(
                        self.display,
                        self.window,
                        self.property_atom,
                        0,
                        0x7fffffff,
                        c.False,
                        c.AnyPropertyType,
                        &actual_type,
                        &actual_format,
                        &nitems,
                        &bytes_after,
                        &prop_data
                    );
                    
                    if (result == c.Success and prop_data != null) {
                        const chunk_len = @as(usize, @intCast(nitems));
                        
                        if (chunk_len == 0) {
                            // Empty property signals end of INCR transfer
                            _ = c.XFree(prop_data);
                            _ = c.XDeleteProperty(self.display, self.window, self.property_atom);
                            
                            const final_data = try self.allocator.dupe(u8, data.items);
                            return clipboard.ClipboardData{
                                .data = final_data,
                                .format = .text, // TODO: determine format properly
                                .allocator = self.allocator,
                            };
                        }
                        
                        // Append chunk to data
                        try data.appendSlice(prop_data[0..chunk_len]);
                        _ = c.XFree(prop_data);
                    }
                    
                    // Delete property to signal ready for next chunk
                    _ = c.XDeleteProperty(self.display, self.window, self.property_atom);
                    _ = c.XFlush(self.display);
                }
            }
            std.time.sleep(1 * std.time.ns_per_ms);
        }
        
        return clipboard.ClipboardError.Timeout;
    }
    
    pub fn write(self: *X11Clipboard, data: []const u8, format: clipboard.ClipboardFormat) !void {
        // Clean up old data
        if (self.clipboard_data) |old_data| {
            self.allocator.free(old_data);
        }
        
        // Store new data
        self.clipboard_data = try self.allocator.dupe(u8, data);
        self.clipboard_format = format;
        
        // Set selection ownership
        _ = c.XSetSelectionOwner(self.display, self.clipboard_atom, self.window, c.CurrentTime);
        _ = c.XFlush(self.display);
        
        // Verify ownership
        if (c.XGetSelectionOwner(self.display, self.clipboard_atom) != self.window) {
            return clipboard.ClipboardError.WriteFailed;
        }
        
        self.owns_selection = true;
        
        // Fork to background to serve clipboard requests
        const pid = std.posix.fork() catch {
            // If fork fails, continue in current process
            return;
        };
        
        if (pid != 0) {
            // Parent process - prevent X11 resource cleanup since child is using them
            self.owns_selection = false;
            self.should_close_display = false;
            return;
        }
        
        // Child process: serve clipboard requests
        self.serveClipboard();
    }
    
    fn serveClipboard(self: *X11Clipboard) noreturn {
        // Redirect stdio to /dev/null for production
        const dev_null = std.fs.openFileAbsolute("/dev/null", .{}) catch std.posix.exit(1);
        defer dev_null.close();
        
        _ = std.posix.dup2(dev_null.handle, 0) catch {};
        _ = std.posix.dup2(dev_null.handle, 1) catch {};
        _ = std.posix.dup2(dev_null.handle, 2) catch {};
        
        // Change to root directory to avoid blocking unmounts
        _ = std.posix.chdir("/") catch {};
        
        // Event loop
        var event: c.XEvent = undefined;
        
        while (true) {
            _ = c.XNextEvent(self.display, &event);
            
            switch (event.type) {
                c.SelectionRequest => {
                    self.handleSelectionRequest(&event.xselectionrequest) catch {};
                },
                c.SelectionClear => {
                    // Lost selection ownership, exit
                    std.posix.exit(0);
                },
                c.PropertyNotify => {
                    if (self.requestors != null) {
                        self.handlePropertyNotify(&event.xproperty) catch {};
                    }
                },
                else => {},
            }
        }
    }
    
    fn handleSelectionRequest(self: *X11Clipboard, request: *c.XSelectionRequestEvent) !void {
        var response = c.XEvent{
            .xselection = c.XSelectionEvent{
                .type = c.SelectionNotify,
                .serial = 0,
                .send_event = c.True,
                .display = request.display,
                .requestor = request.requestor,
                .selection = request.selection,
                .target = request.target,
                .property = request.property,
                .time = request.time,
            },
        };
        
        // Handle TARGETS request
        if (request.target == self.targets_atom) {
            const targets = [_]c.Atom{
                self.targets_atom,
                self.utf8_atom,
                self.string_atom,
                self.text_atom,
                self.text_plain_atom,
            };
            
            _ = c.XChangeProperty(
                self.display,
                request.requestor,
                request.property,
                c.XA_ATOM,
                32,
                c.PropModeReplace,
                @ptrCast(&targets),
                targets.len
            );
        } else if (self.clipboard_data) |data| {
            // Check if data size requires INCR transfer
            if (data.len > self.chunk_size) {
                // Start INCR transfer
                const incr_size: c_long = @intCast(data.len);
                _ = c.XChangeProperty(
                    self.display,
                    request.requestor,
                    request.property,
                    self.incr_atom,
                    32,
                    c.PropModeReplace,
                    @ptrCast(&incr_size),
                    1
                );
                
                // Create requestor tracking
                const requestor = try Requestor.init(
                    self.allocator,
                    request.requestor,
                    request.property
                );
                requestor.context = .incr_transfer;
                requestor.chunk_size = self.chunk_size;
                
                // Add to list
                requestor.next = self.requestors;
                self.requestors = requestor;
                
                // Monitor property changes
                _ = c.XSelectInput(self.display, request.requestor, c.PropertyChangeMask);
            } else {
                // Send all data at once
                _ = c.XChangeProperty(
                    self.display,
                    request.requestor,
                    request.property,
                    self.getAtomForFormat(self.clipboard_format.?),
                    8,
                    c.PropModeReplace,
                    data.ptr,
                    @intCast(data.len)
                );
            }
        } else {
            // No data available
            response.xselection.property = c.None;
        }
        
        // Send response
        _ = c.XSendEvent(
            self.display,
            request.requestor,
            c.False,
            0,
            &response
        );
        _ = c.XFlush(self.display);
    }
    
    fn handlePropertyNotify(self: *X11Clipboard, event: *c.XPropertyEvent) !void {
        if (event.state != c.PropertyDelete) {
            return;
        }
        
        // Find the requestor
        var prev: ?*Requestor = null;
        var current = self.requestors;
        
        while (current) |requestor| {
            if (requestor.window == event.window and requestor.property == event.atom) {
                if (self.clipboard_data) |data| {
                    // Calculate chunk size
                    const remaining = data.len - requestor.position;
                    const chunk_len = @min(remaining, requestor.chunk_size);
                    
                    if (chunk_len > 0) {
                        // Send next chunk
                        _ = c.XChangeProperty(
                            self.display,
                            requestor.window,
                            requestor.property,
                            self.getAtomForFormat(self.clipboard_format.?),
                            8,
                            c.PropModeReplace,
                            data.ptr + requestor.position,
                            @intCast(chunk_len)
                        );
                        requestor.position += chunk_len;
                    } else {
                        // Send empty property to signal completion
                        _ = c.XChangeProperty(
                            self.display,
                            requestor.window,
                            requestor.property,
                            self.getAtomForFormat(self.clipboard_format.?),
                            8,
                            c.PropModeReplace,
                            null,
                            0
                        );
                        
                        // Remove requestor from list
                        if (prev) |p| {
                            p.next = requestor.next;
                        } else {
                            self.requestors = requestor.next;
                        }
                        requestor.deinit();
                    }
                    _ = c.XFlush(self.display);
                }
                return;
            }
            prev = requestor;
            current = requestor.next;
        }
    }
    
    
    fn getAllTargets(self: *X11Clipboard, allocator: std.mem.Allocator) ![]c.Atom {
        const selection_owner = c.XGetSelectionOwner(self.display, self.clipboard_atom);
        if (selection_owner == c.None) {
            return clipboard.ClipboardError.NoData;
        }
        
        // Request TARGETS
        _ = c.XConvertSelection(
            self.display,
            self.clipboard_atom,
            self.targets_atom,
            self.property_atom,
            self.window,
            c.CurrentTime
        );
        _ = c.XFlush(self.display);
        
        // Wait for SelectionNotify
        var event: c.XEvent = undefined;
        const timeout_ms = 500; // Shorter timeout
        const start_time = std.time.milliTimestamp();
        
        while (std.time.milliTimestamp() - start_time < timeout_ms) {
            if (c.XPending(self.display) > 0) {
                _ = c.XNextEvent(self.display, &event);
                
                // Only process events for our window
                if (event.type == c.SelectionNotify and 
                    event.xselection.requestor == self.window) {
                    if (event.xselection.property == c.None) {
                        return clipboard.ClipboardError.NoData;
                    }
                    break;
                }
            }
            std.time.sleep(1 * std.time.ns_per_ms);
        }
        
        if (std.time.milliTimestamp() - start_time >= timeout_ms) {
            return clipboard.ClipboardError.Timeout;
        }
        
        // Read TARGETS property
        var actual_type: c.Atom = undefined;
        var actual_format: c_int = undefined;
        var nitems: c_ulong = undefined;
        var bytes_after: c_ulong = undefined;
        var prop_data: [*c]c.Atom = undefined;
        
        const result = c.XGetWindowProperty(
            self.display, self.window, self.property_atom,
            0, 0x7fffffff, c.False, c.XA_ATOM,
            &actual_type, &actual_format, &nitems, &bytes_after,
            @ptrCast(&prop_data)
        );
        
        if (result != c.Success or prop_data == null) {
            return clipboard.ClipboardError.ReadFailed;
        }
        defer _ = c.XFree(prop_data);
        defer _ = c.XDeleteProperty(self.display, self.window, self.property_atom);
        
        // Copy atoms to owned array
        const target_count = @as(usize, @intCast(nitems));
        const targets = try allocator.alloc(c.Atom, target_count);
        @memcpy(targets, prop_data[0..target_count]);
        
        return targets;
    }
    
    pub fn clear(self: *X11Clipboard) !void {
        // Clear our data
        if (self.clipboard_data) |data| {
            self.allocator.free(data);
            self.clipboard_data = null;
        }
        self.clipboard_format = null;
        self.owns_selection = false;
        
        // Release selection ownership
        _ = c.XSetSelectionOwner(self.display, self.clipboard_atom, c.None, c.CurrentTime);
        _ = c.XSetSelectionOwner(self.display, self.primary_atom, c.None, c.CurrentTime);
        _ = c.XFlush(self.display);
    }
    
    
    pub fn processEvents(self: *X11Clipboard) void {
        // Process any pending X11 events
        while (c.XPending(self.display) > 0) {
            var event: c.XEvent = undefined;
            _ = c.XNextEvent(self.display, &event);
            
            // Handle events if we're serving clipboard
            if (self.owns_selection) {
                switch (event.type) {
                    c.SelectionRequest => {
                        self.handleSelectionRequest(&event.xselectionrequest) catch {};
                    },
                    c.PropertyNotify => {
                        if (self.requestors != null) {
                            self.handlePropertyNotify(&event.xproperty) catch {};
                        }
                    },
                    else => {},
                }
            }
        }
    }
    
    
    fn getAtomForFormat(self: *X11Clipboard, format: clipboard.ClipboardFormat) c.Atom {
        return switch (format) {
            .text => self.utf8_atom,
            .image => self.image_png_atom,
            .html => self.text_html_atom,
            .rtf => c.XInternAtom(self.display, "application/rtf", c.False),
        };
    }
    
    fn getFormatFromAtom(self: *X11Clipboard, atom: c.Atom) clipboard.ClipboardFormat {
        if (atom == self.utf8_atom or atom == self.string_atom or 
            atom == self.text_atom or atom == self.text_plain_atom) {
            return .text;
        } else if (atom == self.image_png_atom or atom == self.image_jpeg_atom or 
                   atom == self.image_gif_atom or atom == self.image_bmp_atom or
                   atom == self.image_avif_atom or atom == self.image_jxl_atom or
                   atom == self.image_tiff_atom or atom == self.image_webp_atom) {
            return .image;
        } else if (atom == self.text_html_atom) {
            return .html;
        } else {
            return .text; // Default to text
        }
    }
    
    pub fn readBestFormat(self: *X11Clipboard) !clipboard.ClipboardData {
        // Get all available targets with single request
        const targets = self.getAllTargets(self.allocator) catch |err| {
            return err;
        };
        defer self.allocator.free(targets);
        
        // Priority order: image first, then text, html, rtf
        const format_priority = [_]clipboard.ClipboardFormat{ .image, .text, .html, .rtf };
        
        for (format_priority) |preferred_format| {
            // Find best atom for this format
            const best_atom = self.findBestAtomForFormat(targets, preferred_format);
            if (best_atom != c.None) {
                // Try to read this format
                if (self.readWithAtom(best_atom)) |data| {
                    return data;
                } else |_| {
                    continue; // Try next format
                }
            }
        }
        
        return clipboard.ClipboardError.NoData;
    }
    
    fn findBestAtomForFormat(self: *X11Clipboard, targets: []c.Atom, format: clipboard.ClipboardFormat) c.Atom {
        switch (format) {
            .image => {
                // Priority: AVIF > WebP > JPEG > PNG > others
                const image_priorities = [_]c.Atom{
                    self.image_avif_atom,
                    self.image_webp_atom, 
                    self.image_jxl_atom,
                    self.image_jpeg_atom,
                    self.image_png_atom,
                    self.image_tiff_atom,
                    self.image_gif_atom,
                    self.image_bmp_atom,
                };
                
                for (image_priorities) |atom| {
                    for (targets) |target| {
                        if (target == atom) return atom;
                    }
                }
            },
            .text => {
                // Priority: UTF8_STRING > text/plain > STRING > TEXT
                const text_priorities = [_]c.Atom{
                    self.utf8_atom,
                    self.text_plain_atom,
                    self.string_atom,
                    self.text_atom,
                };
                
                for (text_priorities) |atom| {
                    for (targets) |target| {
                        if (target == atom) return atom;
                    }
                }
            },
            .html => {
                for (targets) |target| {
                    if (target == self.text_html_atom) return target;
                }
            },
            .rtf => {
                const rtf_atom = c.XInternAtom(self.display, "application/rtf", c.False);
                for (targets) |target| {
                    if (target == rtf_atom) return target;
                }
            },
        }
        
        return c.None;
    }
    
    fn readWithAtom(self: *X11Clipboard, target_atom: c.Atom) !clipboard.ClipboardData {
        // Request the specific target
        _ = c.XConvertSelection(
            self.display,
            self.clipboard_atom,
            target_atom,
            self.property_atom,
            self.window,
            c.CurrentTime
        );
        _ = c.XFlush(self.display);
        
        // Wait for SelectionNotify event with filtering
        var event: c.XEvent = undefined;
        const timeout_ms = 500;
        const start_time = std.time.milliTimestamp();
        
        while (std.time.milliTimestamp() - start_time < timeout_ms) {
            if (c.XPending(self.display) > 0) {
                _ = c.XNextEvent(self.display, &event);
                
                // Only process events for our window and request
                if (event.type == c.SelectionNotify and
                    event.xselection.requestor == self.window and
                    event.xselection.target == target_atom) {
                    
                    if (event.xselection.property == c.None) {
                        return clipboard.ClipboardError.NoData;
                    }
                    
                    // Read the property
                    return try self.readProperty();
                }
            }
            std.time.sleep(1 * std.time.ns_per_ms);
        }
        
        return clipboard.ClipboardError.Timeout;
    }
};