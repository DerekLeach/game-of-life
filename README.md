# Game of Life

A simulation of Conway's game of life using the GPU and written in Zig.

This replicates the completed program from [this guide](https://codelabs.developers.google.com/your-first-webgpu-app) but instead of Javascript and the WebGPU API it is uses Zig and [mach-core](https://github.com/hexops/mach-core).

## Installation

This was written with Zig 0.11.0. With [Zig installed](https://ziglang.org/learn/getting-started/) it should just be:

```shell
git clone https://github.com/DerekLeach/game-of-life
cd game-of-life/
zig build run
```
