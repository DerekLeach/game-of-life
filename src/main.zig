const std = @import("std");
const core = @import("core");
const gpu = core.gpu;

const grid_size = 32;
const workgroup_size = 8;

pub const App = @This();

timer: core.Timer,
title_timer: core.Timer,
pipeline: *gpu.RenderPipeline,
simulation_pipeline: *gpu.ComputePipeline,
vertex_buffer: *gpu.Buffer,
bind_groups: [2]*gpu.BindGroup,
step: usize,

pub fn init(app: *App) !void {
    try core.init(.{});

    core.setSize(.{ .width = 512, .height = 512 });

    const uniform_array = [_]f32{ grid_size, grid_size };

    const uniform_buffer_descriptor = gpu.Buffer.Descriptor{
        .label = "Grid Uniforms",
        .usage = .{
            .uniform = true,
            .copy_dst = true,
        },
        .size = uniform_array.len * @sizeOf(f32),
    };

    var uniform_buffer = core.device.createBuffer(&uniform_buffer_descriptor);

    core.queue.writeBuffer(uniform_buffer, 0, &uniform_array);

    const size: f32 = 0.8;

    const vertices = [_]f32{
        -size, -size, // Triangle 1
        size,  -size,
        size,  size,
        -size, -size, // Triangle 2
        size,  size,
        -size, size,
    };

    const vertex_buffer_descriptor = gpu.Buffer.Descriptor{
        .label = "Cell vertices",
        .usage = .{
            .vertex = true,
            .copy_dst = true,
        },
        .size = vertices.len * @sizeOf(f32),
    };

    var vertex_buffer = core.device.createBuffer(&vertex_buffer_descriptor);
    core.queue.writeBuffer(vertex_buffer, 0, &vertices);

    const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = 8,
        .attributes = &[_]gpu.VertexAttribute{
            .{
                .format = .float32x2,
                .offset = 0,
                .shader_location = 0,
            },
        },
    });

    const shader_module = core.device.createShaderModuleWGSL("shader.wgsl", @embedFile("shader.wgsl"));
    defer shader_module.release();

    const bind_group_layout = core.device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .label = "Cell bind group layout",
        .entries = &[_]gpu.BindGroupLayout.Entry{
            gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true, .compute = true, .fragment = true }, .uniform, false, 0),
            gpu.BindGroupLayout.Entry.buffer(1, .{ .vertex = true, .compute = true }, .read_only_storage, false, 0),
            gpu.BindGroupLayout.Entry.buffer(2, .{ .compute = true }, .storage, false, 0),
        },
    }));

    const pipeline_layout = core.device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .label = "Cell Pipeline Layout",
        .bind_group_layouts = &[_]*gpu.BindGroupLayout{bind_group_layout},
    }));

    const blend = gpu.BlendState{};
    const color_target = gpu.ColorTargetState{
        .format = core.descriptor.format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };

    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "frag_main",
        .targets = &.{color_target},
    });

    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .label = "Cell pipeline",
        .layout = pipeline_layout,
        .fragment = &fragment,
        .vertex = gpu.VertexState.init(.{
            .module = shader_module,
            .entry_point = "vertex_main",
            .buffers = &[_]gpu.VertexBufferLayout{
                vertex_buffer_layout,
            },
        }),
    };

    const pipeline = core.device.createRenderPipeline(&pipeline_descriptor);

    const simulation_pipeline = core.device.createComputePipeline(&gpu.ComputePipeline.Descriptor{
        .label = "Simulation pipeline",
        .layout = pipeline_layout,
        .compute = gpu.ProgrammableStageDescriptor{
            .module = shader_module,
            .entry_point = "compute_main",
        },
    });

    var cell_state_array = [_]u32{0} ** (grid_size * grid_size);

    const cell_state_storage = [_]*gpu.Buffer{
        core.device.createBuffer(&gpu.Buffer.Descriptor{
            .label = "Cell State A",
            .size = cell_state_array.len * @sizeOf(u32),
            .usage = .{
                .storage = true,
                .copy_dst = true,
            },
        }),
        core.device.createBuffer(&gpu.Buffer.Descriptor{
            .label = "Cell State B",
            .size = cell_state_array.len * @sizeOf(u32),
            .usage = .{
                .storage = true,
                .copy_dst = true,
            },
        }),
    };

    const timestamp: u128 = @bitCast(std.time.nanoTimestamp());
    const seed: u64 = @truncate(timestamp);
    var prng = std.rand.DefaultPrng.init(seed);

    for (&cell_state_array) |*cell_state| {
        cell_state.* = if (prng.random().float(f32) > 0.6) 1 else 0;
    }

    core.queue.writeBuffer(cell_state_storage[0], 0, &cell_state_array);

    const bind_groups = [_]*gpu.BindGroup{
        core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
            .label = "Cell renderer bind group A",
            .layout = bind_group_layout,
            .entries = &[_]gpu.BindGroup.Entry{
                gpu.BindGroup.Entry.buffer(0, uniform_buffer, 0, uniform_array.len * @sizeOf(f32)),
                gpu.BindGroup.Entry.buffer(1, cell_state_storage[0], 0, cell_state_array.len * @sizeOf(u32)),
                gpu.BindGroup.Entry.buffer(2, cell_state_storage[1], 0, cell_state_array.len * @sizeOf(u32)),
            },
        })),
        core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
            .label = "Cell renderer bind group B",
            .layout = bind_group_layout,
            .entries = &[_]gpu.BindGroup.Entry{
                gpu.BindGroup.Entry.buffer(0, uniform_buffer, 0, uniform_array.len * @sizeOf(f32)),
                gpu.BindGroup.Entry.buffer(1, cell_state_storage[1], 0, cell_state_array.len * @sizeOf(u32)),
                gpu.BindGroup.Entry.buffer(2, cell_state_storage[0], 0, cell_state_array.len * @sizeOf(u32)),
            },
        })),
    };

    app.* = .{
        .timer = try core.Timer.start(),
        .title_timer = try core.Timer.start(),
        .pipeline = pipeline,
        .simulation_pipeline = simulation_pipeline,
        .vertex_buffer = vertex_buffer,
        .bind_groups = bind_groups,
        .step = 0,
    };
}

pub fn deinit(app: *App) void {
    defer core.deinit();
    _ = app;
}

pub fn update(app: *App) !bool {
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => return true,
            else => {},
        }
    }

    if (app.timer.read() >= 0.2) {
        app.timer.reset();

        const encoder = core.device.createCommandEncoder(null);

        const compute_pass_info = gpu.ComputePassDescriptor.init(.{});
        const compute_pass = encoder.beginComputePass(&compute_pass_info);
        compute_pass.setPipeline(app.simulation_pipeline);
        compute_pass.setBindGroup(0, app.bind_groups[app.step % 2], null);
        const workgroup_count = @ceil(@as(f32, grid_size / workgroup_size));
        compute_pass.dispatchWorkgroups(workgroup_count, workgroup_count, 1);
        compute_pass.end();

        app.step += 1;

        const queue = core.queue;
        const back_buffer_view = core.swap_chain.getCurrentTextureView().?;
        const color_attachment = gpu.RenderPassColorAttachment{
            .view = back_buffer_view,
            .clear_value = gpu.Color{ .r = 0, .g = 0, .b = 0.4, .a = 1 },
            .load_op = .clear,
            .store_op = .store,
        };

        const render_pass_info = gpu.RenderPassDescriptor.init(.{
            .color_attachments = &.{color_attachment},
        });
        const pass = encoder.beginRenderPass(&render_pass_info);
        pass.setPipeline(app.pipeline);
        pass.setBindGroup(0, app.bind_groups[app.step % 2], null);
        pass.setVertexBuffer(0, app.vertex_buffer, 0, gpu.whole_size);
        pass.draw(6, grid_size * grid_size, 0, 0);
        pass.end();
        pass.release();

        var command = encoder.finish(null);
        encoder.release();

        queue.submit(&[_]*gpu.CommandBuffer{command});
        command.release();
        core.swap_chain.present();
        back_buffer_view.release();
    }

    // update the window title every second
    if (app.title_timer.read() >= 1.0) {
        app.title_timer.reset();
        try core.printTitle("Triangle [ {d}fps ] [ Input {d}hz ]", .{
            core.frameRate(),
            core.inputRate(),
        });
    }

    return false;
}
