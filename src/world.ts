import { Chunk } from "./chunk";
import { Object3D } from "./object";
import type { Renderable } from "./renderable";
import type { Renderer } from "./renderer";

export class World {
	objects: Renderable[] = [];
	#drawDistance: number;
	#chunkRows = 5;
	#chunkSize = 100;
	#chunks: Chunk[];
	#renderer: Renderer | null = null;

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

	// Render all objects in the world
	render() {
		if (!this.#renderer) {
			console.warn("No renderer set for world");
			return;
		}

		// Clear the buffer
		this.#renderer.fill([0, 0, 0]);

		// Render each object
		for (const obj of this.objects) {
			if (obj instanceof Object3D) {
				this.#renderObject3D(obj);
			}
		}

		// Commit to canvas
		this.#renderer.render();
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
