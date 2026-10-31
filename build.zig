const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("photonyx", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
}

const onyx_protocol = "2";

pub const ModelsOptions = struct {
    /// Project file `photonyx.json` location
    project: std.Build.LazyPath,
    /// The `photonyx` module of the project, imported by the generated code
    photonyx: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

pub const Models = struct {
    module: *std.Build.Module,
    /// The generator step. Compile steps that import `module` must depend on it.
    step: *std.Build.Step,
};

/// Call it once per build
///
///     const photonyx = b.dependency("photonyx", .{ .target = target, .optimize = optimize }).module("photonyx");
///     const models = @import("photonyx").addModels(b, .{
///         .project = b.path("photonyx.json"),
///         .photonyx = photonyx,
///         .target = target,
///         .optimize = optimize,
///     });
///     lib_mod.addImport("db", models.module);
///     lib.step.dependOn(models.step);
pub fn addModels(b: *std.Build, options: ModelsOptions) Models {
    // a plain string: the system finds `onyx` in PATH when the step runs
    const onyx = b.option([]const u8, "onyx", "Path to the onyx executable (default: onyx from PATH)") orelse "onyx";

    const gen = std.Build.Step.Run.create(b, "onyx models generate");
    gen.has_side_effects = true;
    gen.addArgs(&.{ onyx, "models", "generate", "--lang", "zig", "--protocol", onyx_protocol });
    gen.addArg("--project");
    gen.addFileArg(options.project);

    for (modelDirs(b, options.project), 0..) |dir, i| {
        const models_copy = b.addWriteFiles().addCopyDirectory(dir, b.fmt("models-{d}", .{i}), .{});
        gen.addDirectoryArg2(models_copy, .{ .prefix = "--watch-dir=" });
    }

    const gen_dir = std.Build.LazyPath.cache_root.path(b, "onyx/models");
    gen.addDirectoryArg2(gen_dir, .{});
    _ = gen.addDepFileOutputArg2("models.d", .{});

    b.step("models", "Generate model bindings").dependOn(&gen.step);

    const module = b.createModule(.{
        .root_source_file = gen_dir.path(b, "db.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    module.addImport("photonyx", options.photonyx);

    return .{ .module = module, .step = &gen.step };
}

fn modelDirs(b: *std.Build, project: std.Build.LazyPath) []const std.Build.LazyPath {
    const graph = b.graph;
    const io = graph.io;
    const arena = graph.arena;

    const project_path = switch (project) {
        .src_path => |sp| sp.owner.root.joinString(arena, sp.sub_path) catch @panic("OOM"),
        .dependency => |dep| dep.dependency.builder.root.joinString(arena, dep.sub_path) catch @panic("OOM"),
        .cwd_relative => |p| p,
        .relative => |r| if (r.base == .cwd) r.sub_path else std.process.fatal("addModels: .project must be a source path (b.path), not {f}", .{project}),
        .generated => std.process.fatal("addModels: .project must be a source path (b.path), not a generated file", .{}),
    };
    b.dependOnFileContents(project);

    const source = std.Io.Dir.cwd().readFileAlloc(io, project_path, arena, .limited(1 << 20)) catch |err|
        std.process.fatal("addModels: failed to read the project file {s}: {t}", .{ project_path, err });
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena, source, .{}) catch |err|
        std.process.fatal("addModels: {s}: invalid JSON: {t}", .{ project_path, err });

    const dbs = switch (root) {
        .object => |object| object.get("db") orelse return &.{},
        else => std.process.fatal("addModels: {s}: expected an object", .{project_path}),
    };
    if (dbs != .object) std.process.fatal("addModels: {s}: `db` must be an object", .{project_path});

    const project_dir = std.fs.path.dirname(project_path) orelse ".";
    var result: std.ArrayList(std.Build.LazyPath) = .empty;
    var it = dbs.object.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        const explicit = switch (entry.value_ptr.*) {
            .object => |db| db.get("models"),
            else => std.process.fatal("addModels: {s}: db.{s} must be an object", .{ project_path, name }),
        };
        const sub_path = if (explicit) |value| switch (value) {
            .string => |string| string,
            else => std.process.fatal("addModels: {s}: db.{s}.models must be a string", .{ project_path, name }),
        } else b.fmt("src/models/{s}", .{name});

        const absolute = std.fs.path.isAbsolute(sub_path);
        const dir = if (absolute) graph.cwdRelativePath(sub_path) else project.dirname().path(b, sub_path);
        const dir_path = if (absolute) sub_path else b.pathJoin(&.{ project_dir, sub_path });

        if (std.Io.Dir.cwd().openDir(io, dir_path, .{})) |handle| {
            handle.close(io);
        } else |_| {
            if (explicit != null) continue;

            const parent = std.fs.path.dirname(sub_path) orelse "";
            if (std.Io.Dir.cwd().openDir(io, b.pathJoin(&.{ project_dir, parent }), .{})) |handle| {
                handle.close(io);
                b.dependOnDirectoryContents(project.dirname().path(b, parent));
            } else |_| graph.poisonCache();
            continue;
        }

        result.append(arena, dir) catch @panic("OOM");
    }

    return result.items;
}
