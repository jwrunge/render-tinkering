export class Canvas {
    canvas: HTMLCanvasElement;
    ctx: CanvasRenderingContext2D;

    #width = 1200;
    #height = 675;
    #actualWidth = 1200;
    #actualHeight = 675;
    #aspectRatio = this.#width / this.#height;
    #resizerHooks: Array<() => void> = [];

    private onResize = () => {
        // Keep CSS sizing rules untouched; only track the displayed size.
        this.#actualWidth = this.canvas.clientWidth;
        this.#actualHeight = this.canvas.clientHeight;

        for (const resizer of this.#resizerHooks) {
            resizer();
        }
    };

    constructor(ref: string | HTMLCanvasElement, ops?: { width?: number, height?: number, resizeHooks?: Array<() => void> }) {
        // biome-ignore lint/style/noNonNullAssertion: OK to fail if no canvas
        this.canvas = typeof ref === 'string' ? document.querySelector(ref)! as HTMLCanvasElement : ref;
        const ctx = this.canvas.getContext('2d');
        if(!ctx) {
            throw new Error("Could not get 2D context from canvas");
        }
        this.ctx = ctx;
        
        this.#width = ops?.width ?? this.#width;
        this.#height = ops?.height ?? this.#height;
        this.#aspectRatio = this.#width / this.#height;
        this.#resizerHooks = ops?.resizeHooks ?? [];

        // Fix the backing store size to the logical resolution.
        this.canvas.width = this.#width;
        this.canvas.height = this.#height;

        window.addEventListener('resize', this.onResize);
        this.onResize();
    }

    addResizeHook(resizer: () => void) {
        this.#resizerHooks.push(resizer);
    }

    removeResizeHook(resizer: () => void) {
        this.#resizerHooks = this.#resizerHooks.filter(r => r !== resizer);
    }

    get width() {
        return this.#width;
    }

    get height() {
        return this.#height;
    }

    get actualWidth() {
        return this.#actualWidth;
    }

    get actualHeight() {
        return this.#actualHeight;
    }

    get aspectRatio() {
        return this.#aspectRatio;
    }
}