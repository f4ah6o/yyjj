import { defineConfig } from "vite";
import preact from "@preact/preset-vite";
import fs from "fs";
import path from "path";

function getVersion() {
	const packageJsonPath = path.resolve(__dirname, "../package.json");
	const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf-8"));
	return packageJson.version;
}

export default defineConfig({
	plugins: [preact()],
	base: "/yyjj.mbt/",
	build: {
		outDir: "dist",
		sourcemap: true,
	},
	worker: {
		format: "es",
	},
	define: {
		__YYJJ_VERSION__: JSON.stringify(getVersion()),
	},
});
