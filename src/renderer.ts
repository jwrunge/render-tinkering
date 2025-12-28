import type { Canvas } from "./canvas";

type Color = [ number, number, number ];

export class Renderer {
    canvas: Canvas;
    // Flat RGBA buffer: [r0, g0, b0, a0, r1, g1, b1, a1, ...]
    #buffer: Uint8ClampedArray;
    #image: ImageData;

    get buffer(): Uint8ClampedArray {
        return this.#buffer;
    }

    constructor(canvas: Canvas) {
        this.canvas = canvas;

        const size = canvas.width * canvas.height * 4;
        this.#buffer = new Uint8ClampedArray(size);

        this.#image = this.canvas.ctx.createImageData(canvas.width, canvas.height);
    }

    fill(color: Color) {
        const [r, g, b] = color;
        const buf = this.#buffer;
        
        // Write 4 bytes at a time without function calls.
        for (let i = 0; i < buf.length; i += 4) {
            buf[i] = r;
            buf[i + 1] = g;
            buf[i + 2] = b;
            buf[i + 3] = 255;
        }
    }

    setPixel(x: number, y: number, color: Color) {
        if (x < 0 || y < 0 || x >= this.canvas.width || y >= this.canvas.height) {
            return;
        }

        const i = (y * this.canvas.width + x) * 4;
        this.#buffer[i] = color[0];
        this.#buffer[i + 1] = color[1];
        this.#buffer[i + 2] = color[2];
        this.#buffer[i + 3] = 255;
    }

    render() {
        const renderStart = performance.now();

        // Direct copy: no per-pixel operations, just memcpy-like bulk transfer.
        this.#image.data.set(this.#buffer);

        this.canvas.ctx.putImageData(this.#image, 0, 0);
        console.log(`Render time: ${(performance.now() - renderStart).toFixed(2)} ms`);
    }
}