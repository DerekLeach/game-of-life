struct VertexInput {
    @location(0) pos: vec2f,
    @builtin(instance_index) instance: u32,
};

struct VertexOutput {
    @builtin(position) pos: vec4f,
    @location(0) cell: vec2f,
};

@group(0) @binding(0) var<uniform> grid: vec2f;
@group(0) @binding(1) var<storage> cellStateIn: array<u32>;
@group(0) @binding(2) var<storage, read_write> cellStateOut: array<u32>;

@vertex
fn vertex_main(input: VertexInput) -> VertexOutput {
    let i = f32(input.instance);
    let cell = vec2f(i % grid.x, floor(i / grid.x));
    let state = f32(cellStateIn[input.instance]);

    let cellOffset = cell / grid * 2;
    let gridPos = (input.pos * state + 1) / grid - 1 + cellOffset;

    var output: VertexOutput;
    output.pos = vec4f(gridPos, 0, 1);
    output.cell = cell;
    return output;
}

@fragment
fn frag_main(input: VertexOutput) -> @location(0) vec4f {
    let c = input.cell / grid;
    return vec4f(c, 1 - c.x, 1);
}

fn cell_index(cell: vec2u) -> u32 {
    return (cell.y % u32(grid.y)) * u32(grid.x) + (cell.x % u32(grid.x));
}

fn cell_active(x: u32, y: u32) -> u32 {
    return cellStateIn[cell_index(vec2(x, y))];
}

@compute
@workgroup_size(8, 8)
fn compute_main(@builtin(global_invocation_id) cell: vec3u) {
    var active_neighbours = cell_active(cell.x + 1, cell.y + 1)
        + cell_active(cell.x + 1, cell.y) + cell_active(cell.x + 1, cell.y - 1)
        + cell_active(cell.x, cell.y - 1) + cell_active(cell.x - 1, cell.y - 1)
        + cell_active(cell.x - 1, cell.y) + cell_active(cell.x - 1, cell.y + 1)
        + cell_active(cell.x, cell.y + 1);

    let i = cell_index(cell.xy);

    switch active_neighbours {
        case 2: {
            cellStateOut[i] = cellStateIn[i];
        }
        case 3: {
            cellStateOut[i] = 1;
        }
        default: {
            cellStateOut[i] = 0;
        }
    }
}
