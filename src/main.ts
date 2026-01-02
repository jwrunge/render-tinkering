import { Canvas } from "./canvas";
import { Object3D } from "./object";
import { Renderer } from "./renderer";
import { World } from "./world";
import "./style.css";

// Setup
const canvas = new Canvas("#app", { width: 1920, height: 1080 });
const renderer = new Renderer(canvas);
const world = new World(1000);
world.setRenderer(renderer);

// Create a 3D triangle object
const triangle = new Object3D(undefined, {
	vertices: [
		[0, -1, 0], // Top vertex
		[-1, 1, 0], // Bottom left
		[1, 1, 0], // Bottom right
	],
	color: [0, 255, 100, 255], // Green
});
world.addObject(triangle);

// Animation loop
let startTime = 0;

const animate = (time: number) => {
	const now = performance.now();

	if (startTime === 0) {
		startTime = time;
	}

	const elapsedSec = (time - startTime) / 1000;

	// Update triangle rotation
	const angleX = elapsedSec * 0.5;
	const angleY = elapsedSec * 0.8;
	const angleZ = elapsedSec * 0.3;
	triangle.setRotation(angleX, angleY, angleZ);

	// Render the world
	world.render();

	requestAnimationFrame(animate);

	console.log("Frame time:", performance.now() - now, "ms");
};

requestAnimationFrame(animate);
