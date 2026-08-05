import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import { playgroundPlugin } from "../scripts/playground.mjs";

const page = (path) => fileURLToPath(new URL(path, import.meta.url));

export default defineConfig({
  root: "website",
  base: "/reativa/",
  // The playground compiles the editor buffer with Melange, so it only works
  // where the OCaml toolchain is: `npm run playground` serves it from the dev
  // server, and it is left out of the published build below until there is
  // somewhere online to compile. Add its two pages back to `input` to ship it.
  plugins: [playgroundPlugin()],
  build: {
    outDir: "../_site",
    emptyOutDir: true,
    rollupOptions: {
      input: {
        main: page("index.html")
      }
    }
  },
  server: {
    fs: {
      allow: [".."]
    }
  }
});
