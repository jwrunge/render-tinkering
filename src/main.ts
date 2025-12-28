import { Canvas } from "./canvas";
import { Renderer } from "./renderer";
import "./style.css";

const canvas = new Canvas("#app", { width: 3000, height: 2400 });
const renderer = new Renderer(canvas);

let px_y = 0;
const px_x = Math.floor(canvas.width / 2);

let startTime = 0;
let lastTime = 0;

const movePx = (time: number) => {
	if (startTime === 0) {
		startTime = time;
		lastTime = time;
	}

	const elapsedMs = time - startTime;
	const deltaMs = time - lastTime;
	lastTime = time;

	// Example: time-based motion using elapsed time.
	px_y = Math.floor(((Math.sin(elapsedMs / 500) + 1) / 2) * (canvas.height - 1));

	// Optional: clear previous frame so the pixel doesn't leave a trail.
	renderer.fill([0, 0, 0]);
	renderer.setPixel(px_x, px_y, [0, 255, 0]);
	renderer.setPixel(px_x-1, px_y, [0, 255, 0]);
	renderer.setPixel(px_x-1, px_y-1, [0, 255, 0]);
	renderer.setPixel(px_x+1, px_y, [0, 255, 0]);
	renderer.setPixel(px_x+1, px_y+1, [0, 255, 0]);
	renderer.setPixel(px_x, px_y-1, [0, 255, 0]);
	renderer.setPixel(px_x-1, px_y-1, [0, 255, 0]);
	renderer.setPixel(px_x, px_y+1, [0, 255, 0]);
	renderer.setPixel(px_x+1, px_y+1, [0, 255, 0]);
	renderer.render();

	// deltaMs is available if you want velocity-based updates.
	void deltaMs;
	requestAnimationFrame(movePx);
};

requestAnimationFrame(movePx);
