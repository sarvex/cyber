const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("stdx");
const cy = @import("cyber.zig");
const log = stdx.log.scoped(.main);
const build_options = @import("build_options");
const TraceEnabled = build_options.trace;
const fmt = @import("fmt.zig");

var verbose = false;
var reload = false;
var pc: ?u32 = null;

const CP_UTF8 = 65001;
var prevWinConsoleOutputCP: u32 = undefined;

pub fn main() !void {
    if (builtin.os.tag == .windows) {
        prevWinConsoleOutputCP = std.os.windows.kernel32.GetConsoleOutputCP();
        _ = std.os.windows.kernel32.SetConsoleOutputCP(CP_UTF8);
    }
    defer {
        if (builtin.os.tag == .windows) {
            _ = std.os.windows.kernel32.SetConsoleOutputCP(prevWinConsoleOutputCP);
        }
    }

    const alloc = cy.heap.getAllocator();
    defer cy.heap.deinitAllocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    var cmd = Command.none;
    var arg0: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (arg[0] == '-') {
            if (std.mem.eql(u8, arg, "-v")) {
                verbose = true;
            } else if (std.mem.eql(u8, arg, "-r")) {
                reload = true;
            } else if (std.mem.eql(u8, arg, "-pc")) {
                i += 1;
                if (i < args.len) {
                    pc = try std.fmt.parseInt(u32, args[i], 10);
                } else {
                    std.debug.print("Missing pc arg.\n", .{});
                    exit(1);
                }
            }
        } else {
            if (cmd == .none) {
                if (std.mem.eql(u8, arg, "compile")) {
                    cmd = .compile;
                } else if (std.mem.eql(u8, arg, "version")) {
                    cmd = .version;
                } else if (std.mem.eql(u8, arg, "help")) {
                    cmd = .help;
                } else {
                    cmd = .eval;
                    if (arg0 == null) {
                        arg0 = arg;
                    }
                }

            } else {
                if (arg0 == null) {
                    arg0 = arg;
                }
            }
        }
    }

    switch (cmd) {
        .eval => {
            if (arg0) |path| {
                try evalPath(alloc, path);
            } else {
                return error.MissingFilePath;
            }
        },
        .compile => {
            if (arg0) |path| {
                try compilePath(alloc, path);
            } else {
                return error.MissingFilePath;
            }
        },
        .help => {
            help();
        },
        .version => {
            version();
        },
        .none => {
            help();
            exit(1);
        },
    }
}

fn exit(code: u8) noreturn {
    if (builtin.os.tag == .windows) {
        _ = std.os.windows.kernel32.SetConsoleOutputCP(prevWinConsoleOutputCP);
    }
    std.os.exit(code);
}

const Command = enum {
    eval,
    compile,
    help,
    version,
    none,
};

fn compilePath(alloc: std.mem.Allocator, path: []const u8) !void {
    const src = try std.fs.cwd().readFileAlloc(alloc, path, 1e10);
    defer alloc.free(src);

    const vm = cy.getUserVM();
    try vm.init(alloc);
    defer vm.deinit();

    var trace: cy.TraceInfo = undefined;
    vm.setTrace(&trace);
    const res = vm.compile(path, src) catch |err| {
        fmt.panic("unexpected {}\n", &.{fmt.v(err)});
    };
    if (res.err) |err| {
        switch (err) {
            .tokenize,
            .parse,
            .compile, => {
                if (!cy.silentError) {
                    const report = try vm.allocLastErrorReport();
                    defer alloc.free(report);
                    fmt.printStderr(report, &.{});
                }
                exit(1);
            },
        }
    }
    try cy.debug.dumpBytecode(vm.constInternal(), pc);
}

fn evalPath(alloc: std.mem.Allocator, path: []const u8) !void {
    const src = try std.fs.cwd().readFileAllocOptions(alloc, path, 1e10, 4096, @alignOf(u8), null);
    defer alloc.free(src);

    cy.verbose = verbose;

    const vm = cy.getUserVM();
    try vm.init(alloc);
    defer vm.deinit();

    var trace: cy.TraceInfo = undefined;
    vm.setTrace(&trace);
    defer {
        if (TraceEnabled) {
            trace.deinit(alloc);
        }
    }

    _ = vm.eval(path, src, .{
        .singleRun = builtin.mode == .ReleaseFast,
        .enableFileModules = true,
        .reload = reload,
    }) catch |err| {
        switch (err) {
            error.Panic,
            error.TokenError,
            error.ParseError,
            error.CompileError => {
                if (!cy.silentError) {
                    const report = try vm.allocLastErrorReport();
                    defer alloc.free(report);
                    fmt.printStderr(report, &.{});
                }
                exit(1);
            },
            else => {
                fmt.panic("unexpected {}\n", &.{fmt.v(err)});
            },
        }
    };
    if (verbose) {
        std.debug.print("\n==VM Info==\n", .{});
        try vm.dumpInfo();
        if (TraceEnabled) {
            vm.dumpStats();
        }
    }
    if (cy.TrackGlobalRC) {
        vm.internal().compiler.deinitRtObjects();
        vm.internal().deinitRtObjects();
        try cy.arc.checkGlobalRC(vm.internal());
    }
}

fn help() void {
    std.debug.print(
        \\Cyber {s}
        \\
        \\Usage: cyber [source]
        \\       cyber [command] ...
        \\
        \\Commands:
        \\  cyber [source]            Compile and run a script.
        \\  cyber compile [source]    Compile script and dump the bytecode.
        \\  cyber help                Print usage.
        \\  cyber version             Print version number.
        \\  
        \\General Options:
        \\  -r      Refetch url imports and cached assets.
        \\  -v      Verbose.
        \\                            
        \\cyber compile Options:
        \\  -pc     Next arg is the pc to dump detailed bytecode at.
        \\
    , .{build_options.version});
}

fn version() void {
    std.debug.print("{s}\n", .{build_options.full_version});
}