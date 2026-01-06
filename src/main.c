#include <SDL3/SDL.h>

int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    if (!SDL_Init(SDL_INIT_VIDEO)) {
        const char *err = SDL_GetError();
        SDL_Log("SDL_Init failed: %s", (err && *err) ? err : "(no error message)");
        return 1;
    }

    SDL_Window *window = SDL_CreateWindow("SDL3.4 + C (CMake)", 800, 600, 0);
    if (!window) {
        SDL_Log("SDL_CreateWindow failed: %s", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    const char *autoclose_ms_env = SDL_getenv("RENDER_AUTOCLOSE_MS");
    const Uint64 start_ms = SDL_GetTicks();
    const Uint64 autoclose_ms = (autoclose_ms_env && *autoclose_ms_env)
                                   ? (Uint64)SDL_strtoull(autoclose_ms_env, NULL, 10)
                                   : 0;

    bool running = true;
    while (running) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_EVENT_QUIT) {
                running = false;
            }
        }

        if (autoclose_ms > 0 && (SDL_GetTicks() - start_ms) >= autoclose_ms) {
            running = false;
        }

        SDL_Delay(16);
    }

    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
