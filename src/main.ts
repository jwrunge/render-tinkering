import { Canvas } from "./canvas";
import { Object3D } from "./object";
import { Renderer } from "./renderer";
import "./style.css";

const canvas = new Canvas("#app", { width: 1920, height: 1080 });
const renderer = new Renderer(canvas);

// Get direct buffer access for fast per-pixel writes
const buffer = renderer.buffer;
const width = canvas.width;
const height = canvas.height;

// Create a 3D triangle object
const triangle = new Object3D(undefined, {
	vertices: [
		[0, -1, 0], // Top vertex
		[-1, 1, 0], // Bottom left
		[1, 1, 0], // Bottom right
	],
});

// Project 3D point to 2D screen space
const project = (
	point: [number, number, number],
	scale: number,
): [number, number] => {
	const [x, y, z] = point;
	// Simple perspective projection
	const perspective = 1 / (z + 3); // z + 3 to avoid division by zero
	const screenX = Math.floor(width / 2 + x * scale * perspective);
	const screenY = Math.floor(height / 2 + y * scale * perspective);
	return [screenX, screenY];
};

// Draw a line between two points using Bresenham's algorithm
const drawLine = (
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	color: [number, number, number, number],
) => {
	const dx = Math.abs(x1 - x0);
	const dy = Math.abs(y1 - y0);
	const sx = x0 < x1 ? 1 : -1;
	const sy = y0 < y1 ? 1 : -1;
	let err = dx - dy;

	while (true) {
		// Draw pixel
		if (x0 >= 0 && y0 >= 0 && x0 < width && y0 < height) {
			const i = (y0 * width + x0) * 4;
			buffer[i] = color[0];
			buffer[i + 1] = color[1];
			buffer[i + 2] = color[2];
			buffer[i + 3] = color[3];
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
};

let startTime = 0;

const animate = (time: number) => {
	const renderStart = performance.now();
	if (startTime === 0) {
		startTime = time;
	}

	const elapsedSec = (time - startTime) / 1000;

	// Clear the buffer (black background)
	renderer.fill([0, 0, 0]);

	// Update triangle rotation
	const angleX = elapsedSec * 0.5;
	const angleY = elapsedSec * 0.8;
	const angleZ = elapsedSec * 0.3;
	triangle.setRotation(angleX, angleY, angleZ);

	// Get transformed vertices and project to 2D
	const scale = 300;
	const transformedVertices = triangle.getTransformedVertices();
	const projectedTriangle = transformedVertices.map((vertex) =>
		project(vertex, scale),
	);

	// Draw the triangle edges
	const color: [number, number, number, number] = [0, 255, 100, 255]; // Green
	drawLine(
		projectedTriangle[0][0],
		projectedTriangle[0][1],
		projectedTriangle[1][0],
		projectedTriangle[1][1],
		color,
	);
	drawLine(
		projectedTriangle[1][0],
		projectedTriangle[1][1],
		projectedTriangle[2][0],
		projectedTriangle[2][1],
		color,
	);
	drawLine(
		projectedTriangle[2][0],
		projectedTriangle[2][1],
		projectedTriangle[0][0],
		projectedTriangle[0][1],
		color,
	);

	renderer.render();

	console.info(
		`Frame render time: ${(performance.now() - renderStart).toFixed(2)} ms`,
	);

	requestAnimationFrame(animate);
};

requestAnimationFrame(animate);
