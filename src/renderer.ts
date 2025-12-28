import type { Canvas } from "./canvas";

type Color = [ number, number, number ];

export class Renderer {
    canvas: Canvas;
    #buffer: Color[][] = [];
    #image: ImageData;

    get buffer(): ReadonlyArray<Color[]> {
        return this.#buffer;
    }

    constructor(canvas: Canvas) {
        this.canvas = canvas;

        this.#buffer = Array.from({ length: canvas.height }, () =>
            Array.from({ length: canvas.width }, (): Color => [0, 0, 0]),
        );

        // Prevent replacing whole rows (e.g. buffer[0] = ...), while still
        // allowing pixel edits (e.g. buffer[0][0] = ...).
        Object.freeze(this.#buffer);

        this.#image = this.canvas.ctx.createImageData(canvas.width, canvas.height);
    }

    fill(color: Color) {
        for (let y = 0; y < this.canvas.height; y++) {
            for (let x = 0; x < this.canvas.width; x++) {
                this.setPixel(x, y, color);
            }
        }
    }

    setPixel(x: number, y: number, color: Color) {
        if (x < 0 || y < 0 || x >= this.canvas.width || y >= this.canvas.height) {
            return;
        }

        this.#buffer[y][x] = color;
    }

    render() {
        const bufferWidth = this.canvas.width;
        const bufferHeight = this.canvas.height;

        // If logical resolution ever changes, rebuild the ImageData.
        if (this.#image.width !== bufferWidth || this.#image.height !== bufferHeight) {
            this.#image = this.canvas.ctx.createImageData(bufferWidth, bufferHeight);
        }

        const data = this.#image.data;
        let i = 0;
        for (let y = 0; y < bufferHeight; y++) {
            const row = this.#buffer[y];
            for (let x = 0; x < bufferWidth; x++) {
                const [r, g, b] = row[x];
                data[i++] = r;
                data[i++] = g;
                data[i++] = b;
                data[i++] = 255;
            }
        }

        this.canvas.ctx.putImageData(this.#image, 0, 0);
    }
}