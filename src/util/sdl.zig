const build_options = @import("build_options");

pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    if (build_options.enable_sdl_gpu) {
        @cInclude("SDL3/SDL_gpu.h");
    }
});
