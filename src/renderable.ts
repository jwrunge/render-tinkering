/**
 * Renderable.ts
 * Base class for anything that can be rendered in the world.
 * A Renderable may contain vertex data, child Renderables, or both.
 * Determines how to represent itself at different LODs.
 */

export type RenderableData = {
    vertices?: Array<[number, number, number]>;
    children?: Renderable[];
    voxels?: number[]; // Voxel representation for distant LODs
    pixel?: [number, number, number]; // Single pixel color for very distant LODs
}

export abstract class Renderable {
    protected position: [number, number, number] = [0, 0, 0];
    protected children: Renderable[] = [];
    protected vertices: Array<[number, number, number]> = [];
    protected dirty = true;

    constructor(position?: [number, number, number]) {
        if (position) {
            this.position = position;
        }
    }

    /**
     * Get the appropriate representation for this Renderable at the given LOD.
     * @param lod - Level of detail (0 = highest detail, higher = more simplified)
     * @returns Data needed to render this Renderable
     */
    abstract getRepresentation(lod: number): RenderableData;

    /**
     * Add a child Renderable
     */
    addChild(child: Renderable) {
        this.children.push(child);
        this.dirty = true;
    }

    /**
     * Remove a child Renderable
     */
    removeChild(child: Renderable) {
        const index = this.children.indexOf(child);
        if (index !== -1) {
            this.children.splice(index, 1);
            this.dirty = true;
        }
    }

    /**
     * Get the position of this Renderable
     */
    getPosition(): [number, number, number] {
        return this.position;
    }

    /**
     * Set the position of this Renderable
     */
    setPosition(position: [number, number, number]) {
        this.position = position;
        this.dirty = true;
    }
}
