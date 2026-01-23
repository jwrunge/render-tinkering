const c = @import("../sdl.zig").sdl;

pub const VertexLayout = struct {
    vb_desc: []const c.SDL_GPUVertexBufferDescription,
    vb_attr: []const c.SDL_GPUVertexAttribute,

    pub fn vertexInputState(self: VertexLayout) c.SDL_GPUVertexInputState {
        return .{
            .vertex_buffer_descriptions = self.vb_desc.ptr,
            .num_vertex_buffers = @intCast(self.vb_desc.len),
            .vertex_attributes = self.vb_attr.ptr,
            .num_vertex_attributes = @intCast(self.vb_attr.len),
        };
    }
};
