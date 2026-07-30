import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import postcss from "./postcss.config.js";
import { resolve } from "path";

export default defineConfig({
  css: { postcss },
  plugins: [svelte()],
  base: "./", // FiveM NUI needs local dir references
  resolve: {
    alias: {
      "@components": resolve("./src/components"),
      "@providers": resolve("./src/providers"),
      "@store": resolve("./src/store"),
      "@utils": resolve("./src/utils"),
      "@typings": resolve("./src/typings"),
      "@actions": resolve("./src/actions"),
    },
  },
  build: {
    emptyOutDir: true,
    outDir: "../html",
    assetsDir: "./",
    rollupOptions: {
      output: {
        // No hashes: the manifest never has to be updated.
        entryFileNames: "[name].js",
        chunkFileNames: "[name].js",
        assetFileNames: "[name].[ext]",
      },
    },
  },
});
