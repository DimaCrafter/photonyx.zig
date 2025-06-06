# Photonyx Zig bindings

Very WIP project.

## Quick start

### Using Onyx CLI

You can bootstrap your project with Onyx:

```sh
onyx new --zig my_controller
```

Command above will create directory `my_controller` with basic Photonyx project skeleton. You can also create project in current directory by passing dot (`.`).

<!-- TODO: how to install Onyx -->

### Manual installation

1. Create new Zig library:

   ```sh
   mkdir my_controller
   cd my_controller
   zig init
   ```

2. Remove `main.zig` as binary artifact is not needed.
3. Install Photonyx dependency:

    ```sh
    zig fetch --save git+https://github.com/DimaCrafter/photonyx.zig
    ```

4. Edit `build.zig` to make your new library dynamic and add Photonyx:

    ```zig
    const lib = b.addLibrary(.{
        // Here will be .static by default
        .linkage = .dynamic,
        .name = "My_controllers",
        .root_module = lib_mod,
    });

    const photonyx = b.dependency("photonyx", .{
        .target = target,
        .optimize = optimize,
    });

    lib.root_module.addImport("photonyx", photonyx.module("photonyx"));
    lib.linker_allow_shlib_undefined = true;
    ```
