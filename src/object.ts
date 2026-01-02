import type { Chunk } from "./chunk";
import { Renderable, type RenderableData } from "./renderable";

type MatrixRow = [number, number, number, number];
type TxMatrix = [MatrixRow, MatrixRow, MatrixRow, MatrixRow];

const IDENTITY_MATRIX: TxMatrix = [
    [1, 0, 0, 0],
    [0, 1, 0, 0],
    [0, 0, 1, 0],
    [0, 0, 0, 1],
];

export type SummaryOutput = {
    pixel: [number, number, number],
    maxLod: number,
} & {
    [key: `lod${number}`]: number[]
}

export class Object3D extends Renderable {
    #worldSpace: TxMatrix = IDENTITY_MATRIX;
    #transform: TxMatrix;
    #summary: SummaryOutput = { pixel: [255, 0, 255], maxLod: 20 };

    constructor(
        worldSpace: TxMatrix = IDENTITY_MATRIX,
        ops?: {
            position?: [number, number, number],
            transform?: TxMatrix,
            vertices?: Array<[number, number, number]>,
            renderAt?: number
        }
    ) {
        super(ops?.position);
        this.#worldSpace = worldSpace;
        this.#transform = ops?.transform ?? IDENTITY_MATRIX;
        this.vertices = ops?.vertices ?? [];
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