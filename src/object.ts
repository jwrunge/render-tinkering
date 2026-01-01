import type { Chunk } from "./chunk";
import { Renderable, type RenderableData } from "./renderable";

export type SummaryOutput = {
    pixel: [number, number, number],
    maxLod: number,
} & {
    [key: `lod${number}`]: number[]
}

export class Object3D extends Renderable {
    #transform: [[number, number, number], [number, number, number], [number, number, number]];
    #chunkRef: Chunk | null = null;
    #summary: SummaryOutput = { pixel: [255, 0, 255], maxLod: 20 };

    constructor(
        chunkRef: Chunk | null,
        ops?: {
            position?: [number, number, number],
            transform?: [[number, number, number], [number, number, number], [number, number, number]],
            vertices?: Array<[number, number, number]>,
            renderAt?: number
        }
    ) {
        super(ops?.position);
        this.#transform = ops?.transform ?? [[1, 0, 0], [0, 1, 0], [0, 0, 1]];
        this.vertices = ops?.vertices ?? [];
        this.#chunkRef = chunkRef;
    }

    setVertices(vertices: Array<[number, number, number]>) {
        this.vertices = vertices;
        this.dirty = true;
    }

    setRep(value: Partial<SummaryOutput>) {
        this.#summary = { ...this.#summary, ...value } as SummaryOutput;

        // Construct LODs
    }

    getRepresentation(lod: number): RenderableData {
        this.dirty = false;
        
        // At close range, return full vertex data
        if (lod === 0) {
            return { vertices: this.vertices };
        }
        
        // At medium range, return simplified representation if available
        const lodData = this.#summary[`lod${lod}`];
        if (lodData) {
            return { voxels: lodData };
        }
        
        // At far range, return single pixel if within max LOD
        if (this.#summary.maxLod >= lod) {
            return { pixel: this.#summary.pixel };
        }
        
        // Beyond max LOD, don't render
        return {};
    }

    getRep(lod: number): number[] | undefined {
        return this.#summary[`lod${lod}`] ?? this.#summary.maxLod >= lod ? this.#summary.pixel : undefined;
    }
}