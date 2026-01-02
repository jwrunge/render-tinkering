import type { Canvas } from "./canvas";

type Color = [ number, number, number ];
type ColorWithAlpha = [ number, number, number, number ];

export class Renderer {
    canvas: Canvas;
    // Flat RGBA buffer: [r0, g0, b0, a0, r1, g1, b1, a1, ...]
    #buffer: Uint8ClampedArray;
    #image: ImageData;
    #scale = 300; // Default projection scale

    get buffer(): Uint8ClampedArray {
        return this.#buffer;
    }

    constructor(canvas: Canvas) {
        this.canvas = canvas;

        const size = canvas.width * canvas.height * 4;
        this.#buffer = new Uint8ClampedArray(size);

        this.#image = this.canvas.ctx.createImageData(canvas.width, canvas.height);
    }

    setScale(scale: number) {
        this.#scale = scale;
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

    // Project 3D point to 2D screen space
    project(point: [number, number, number]): [number, number] {
        const [x, y, z] = point;
        // Simple perspective projection
        const perspective = 1 / (z + 3); // z + 3 to avoid division by zero
        const screenX = Math.floor(this.canvas.width / 2 + x * this.#scale * perspective);
        const screenY = Math.floor(this.canvas.height / 2 + y * this.#scale * perspective);
        return [screenX, screenY];
    }

    // Draw a line between two points using Bresenham's algorithm
    drawLine(x0: number, y0: number, x1: number, y1: number, color: ColorWithAlpha) {
        const dx = Math.abs(x1 - x0);
        const dy = Math.abs(y1 - y0);
        const sx = x0 < x1 ? 1 : -1;
        const sy = y0 < y1 ? 1 : -1;
        let err = dx - dy;

        while (true) {
            // Draw pixel
            if (x0 >= 0 && y0 >= 0 && x0 < this.canvas.width && y0 < this.canvas.height) {
                const i = (y0 * this.canvas.width + x0) * 4;
                this.#buffer[i] = color[0];
                this.#buffer[i + 1] = color[1];
                this.#buffer[i + 2] = color[2];
                this.#buffer[i + 3] = color[3];
            }

            if (x0 === x1 && y0 === y1) break;
            const e2 = 2 * err;
            if (e2 > -dy) {
                err -= dy;
                x0 += sx;
            }
            if (e2 < dx) {
                err += dx;
                y0 += sy;
            }
        }
    }

    render() {
        // Direct copy: no per-pixel operations, just memcpy-like bulk transfer.
        this.#image.data.set(this.#buffer);
        this.canvas.ctx.putImageData(this.#image, 0, 0);
    }
}