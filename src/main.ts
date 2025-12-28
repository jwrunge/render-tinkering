import { Canvas } from "./canvas";
import { Renderer } from "./renderer";
import "./style.css";

const canvas = new Canvas("#app", { width: 1920, height: 1080 });
const renderer = new Renderer(canvas);

// Get direct buffer access for fast per-pixel writes
const buffer = renderer.buffer;
const width = canvas.width;
const height = canvas.height;

let px_y = 0;
const px_x = Math.floor(width / 2);

let startTime = 0;
let lastTime = 0;

const movePx = (time: number) => {
  const renderStart = performance.now();
	if (startTime === 0) {
		startTime = time;
		lastTime = time;
	}

	const elapsedMs = time - startTime;
	const deltaMs = time - lastTime;
	lastTime = time;

	// Example: time-based motion using elapsed time.
	px_y = Math.floor(((Math.sin(elapsedMs / 500) + 1) / 2) * (height - 1));

	// Draw pixels directly to buffer (faster than setPixel calls)
	const pixels = [
		[px_x, px_y],
		[px_x - 1, px_y],
		[px_x - 1, px_y - 1],
		[px_x + 1, px_y],
		[px_x + 1, px_y + 1],
		[px_x, px_y - 1],
		[px_x - 1, px_y - 1],
		[px_x, px_y + 1],
		[px_x + 1, px_y + 1],
	];

	for (const [x, y] of pixels) {
		if (x >= 0 && y >= 0 && x < width && y < height) {
			const i = (y * width + x) * 4;
			buffer[i] = 0;       // r
			buffer[i + 1] = 255; // g
			buffer[i + 2] = 0;   // b
			buffer[i + 3] = 255; // a
		}
	}

	renderer.render();

  console.info(`Frame render time: ${(performance.now() - renderStart).toFixed(2)} ms`);

	// deltaMs is available if you want velocity-based updates.
	void deltaMs;
	requestAnimationFrame(movePx);
};

requestAnimationFrame(movePx);
