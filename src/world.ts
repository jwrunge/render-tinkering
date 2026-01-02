import { Chunk } from "./chunk";
import type { Renderable } from "./renderable";

export class World {
    objects: Renderable[] = [];
    #drawDistance: number;
    #chunkRows = 5;
    #chunkSize = 100;
    #chunks: Chunk[];

    constructor(drawDistance: number) {
        this.#drawDistance = drawDistance;
        this.#chunks = [];
        this.#initializeChunks();
    }

    #initializeChunks() {
        // Initialize chunk grid based on chunk size
        for (let i = 0; i < this.#chunkRows * this.#chunkRows; i++) {
            const row = Math.floor(i / this.#chunkRows);
            const col = i % this.#chunkRows;
            const position: [number, number, number] = [
                col * this.#chunkSize,
                0,
                row * this.#chunkSize
            ];
            this.#chunks.push(new Chunk(position));
        }
    }

    set drawDistance(distance: number) {
        this.#drawDistance = distance;
    }

    get drawDistance(): number {
        return this.#drawDistance;
    }

    addObject(obj: Renderable) {
        this.objects.push(obj);
        // TODO: Assign to appropriate chunk based on position
    }

    getChunks(): Chunk[] {
        return this.#chunks;
    }
}