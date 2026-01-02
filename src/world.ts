import { Chunk } from "./chunk";
import { Object3D } from "./object";
import type { Renderable } from "./renderable";
import type { Renderer } from "./renderer";

export class World {
	#drawDistance: number;
	#chunkRows = 5;
	#chunkSize = 100;
	#chunks: Chunk[];
	#renderer: Renderer | null = null;
	#cameraPosition: [number, number, number] = [0, 0, 0];

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
				row * this.#chunkSize,
			];
			this.#chunks.push(new Chunk(position));
		}
	}

	setRenderer(renderer: Renderer) {
		this.#renderer = renderer;
	}

	setCameraPosition(position: [number, number, number]) {
		this.#cameraPosition = position;
	}

	set drawDistance(distance: number) {
		this.#drawDistance = distance;
	}

	get drawDistance(): number {
		return this.#drawDistance;
	}

	addObject(obj: Renderable) {
		// Find the appropriate chunk based on object position
		const objPos = obj.getPosition();
		const chunkX = Math.floor(objPos[0] / this.#chunkSize);
		const chunkZ = Math.floor(objPos[2] / this.#chunkSize);
		
		// Clamp to chunk grid
		const clampedX = Math.max(0, Math.min(this.#chunkRows - 1, chunkX));
		const clampedZ = Math.max(0, Math.min(this.#chunkRows - 1, chunkZ));
		
		const chunkIndex = clampedZ * this.#chunkRows + clampedX;
		if (chunkIndex >= 0 && chunkIndex < this.#chunks.length) {
			this.#chunks[chunkIndex].add(obj, true);
		}
	}

	getChunks(): Chunk[] {
		return this.#chunks;
	}

	// Calculate LOD based on distance from camera
	#calculateLOD(position: [number, number, number]): number {
		const dx = position[0] - this.#cameraPosition[0];
		const dy = position[1] - this.#cameraPosition[1];
		const dz = position[2] - this.#cameraPosition[2];
		const distance = Math.sqrt(dx * dx + dy * dy + dz * dz);
		
		// Map distance to LOD level (0 = highest detail)
		if (distance < 50) return 0;
		if (distance < 100) return 1;
		if (distance < 200) return 2;
		if (distance < 400) return 3;
		if (distance < 800) return 4;
		return 5;
	}

	// Render all chunks in the world
	render() {
		if (!this.#renderer) {
			console.warn("No renderer set for world");
			return;
		}

		// Clear the buffer
		this.#renderer.fill([0, 0, 0]);

		// Render each chunk based on its LOD
		for (const chunk of this.#chunks) {
			const chunkPos = chunk.getPosition();
			const lod = this.#calculateLOD(chunkPos);
			const representation = chunk.getRepresentation(lod);
			
			this.#renderRepresentation(representation);
		}

		// Commit to canvas
		this.#renderer.render();
	}

	#renderRepresentation(data: ReturnType<Chunk['getRepresentation']>) {
		if (!this.#renderer) return;

		// If representation contains child objects, render them individually
		if (data.children) {
			for (const child of data.children) {
				if (child instanceof Object3D) {
					this.#renderObject3D(child);
				}
			}
		}

		// If representation contains voxels, render voxel data
		if (data.voxels && data.voxels.length > 0) {
			// TODO: Implement voxel rendering
		}

		// If representation contains a single pixel, render it
		if (data.pixel) {
			// TODO: Implement pixel rendering at chunk position
		}
	}

	#renderObject3D(obj: Object3D) {
		if (!this.#renderer) return;

		const transformedVertices = obj.getTransformedVertices();
		if (transformedVertices.length < 2) return;

		// Project vertices to 2D
		const renderer = this.#renderer;
		const projectedVertices = transformedVertices.map((vertex) =>
			renderer.project(vertex),
		);

		// Draw edges connecting vertices
		for (let i = 0; i < projectedVertices.length; i++) {
			const start = projectedVertices[i];
			const end = projectedVertices[(i + 1) % projectedVertices.length];
			this.#renderer.drawLine(start[0], start[1], end[0], end[1], obj.color);
		}
	}
}
