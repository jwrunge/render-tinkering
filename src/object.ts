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
    #rotation: [number, number, number] = [0, 0, 0]; // X, Y, Z rotation in radians
    #summary: SummaryOutput = { pixel: [255, 0, 255], maxLod: 20 };
    color: [number, number, number, number] = [0, 255, 100, 255]; // RGBA color

    constructor(
        worldSpace: TxMatrix = IDENTITY_MATRIX,
        ops?: {
            position?: [number, number, number],
            transform?: TxMatrix,
            vertices?: Array<[number, number, number]>,
            renderAt?: number,
            color?: [number, number, number, number]
        }
    ) {
        super(ops?.position);
        this.#worldSpace = worldSpace;
        this.#transform = ops?.transform ?? IDENTITY_MATRIX;
        this.vertices = ops?.vertices ?? [];
        if (ops?.color) {
            this.color = ops.color;
        }
    }

    setVertices(vertices: Array<[number, number, number]>) {
        this.vertices = vertices;
        this.dirty = true;
    }

    rotate(x: number, y: number, z: number) {
        this.#rotation[0] += x;
        this.#rotation[1] += y;
        this.#rotation[2] += z;
        this.dirty = true;
    }

    setRotation(x: number, y: number, z: number) {
        this.#rotation = [x, y, z];
        this.dirty = true;
    }

    getRotation(): [number, number, number] {
        return [...this.#rotation];
    }

    // Apply rotation transformations to a vertex
    #rotateVertex(vertex: [number, number, number]): [number, number, number] {
        const [x, y, z] = vertex;
        const [rx, ry, rz] = this.#rotation;
        
        // Rotate around X axis
        const px = x;
        const py = y * Math.cos(rx) - z * Math.sin(rx);
        const pz = y * Math.sin(rx) + z * Math.cos(rx);
        
        // Rotate around Y axis
        const px2 = px * Math.cos(ry) + pz * Math.sin(ry);
        const py2 = py;
        const pz2 = -px * Math.sin(ry) + pz * Math.cos(ry);
        
        // Rotate around Z axis
        const px3 = px2 * Math.cos(rz) - py2 * Math.sin(rz);
        const py3 = px2 * Math.sin(rz) + py2 * Math.cos(rz);
        const pz3 = pz2;
        
        return [px3, py3, pz3];
    }

    // Get transformed vertices (with rotation and position applied)
    getTransformedVertices(): Array<[number, number, number]> {
        return this.vertices.map(vertex => {
            const rotated = this.#rotateVertex(vertex);
            return [
                rotated[0] + this.position[0],
                rotated[1] + this.position[1],
                rotated[2] + this.position[2]
            ];
        });
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