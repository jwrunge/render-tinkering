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

        // Fast path: if filling with black, just zero the whole buffer
        if (r === 0 && g === 0 && b === 0) {
            buf.fill(0);
            return;
        }

        // For non-black: write RGBA pattern once, then copy it repeatedly
        // This is faster than writing each pixel individually
        const pixelCount = this.canvas.width * this.canvas.height;
        
        // Write first pixel
        buf[0] = r;
        buf[1] = g;
        buf[2] = b;
        buf[3] = 255;

        // Double the filled region repeatedly (1 pixel -> 2 -> 4 -> 8 -> ...)
        let filled = 1;
        while (filled < pixelCount) {
            const copySize = Math.min(filled, pixelCount - filled) * 4;
            buf.copyWithin(filled * 4, 0, copySize);
            filled += copySize / 4;
        }
    }

    render() {
        // Direct copy: no per-pixel operations, just memcpy-like bulk transfer.
        this.#image.data.set(this.#buffer);
        this.canvas.ctx.putImageData(this.#image, 0, 0);
    }
}