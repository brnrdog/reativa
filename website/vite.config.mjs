import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import { playgroundPlugin } from "../scripts/playground.mjs";

const page = (path) => fileURLToPath(new URL(path, import.meta.url));

export default defineConfig({
  root: "website",
  base: "/reativa/",
  // The playground compiles the editor buffer with Melange, so its endpoints
  // only exist on the dev server; the published site falls back to read-only.
  plugins: [playgroundPlugin()],
  build: {
    outDir: "../_site",
    emptyOutDir: true,
    rollupOptions: {
      input: {
        main: page("index.html"),
        playground: page("playground/index.html"),
        preview: page("playground/preview.html")
      }
    }
  },
  server: {
    fs: {
      allow: [".."]
    }
  }
});
