import { defineConfig } from "vite";

export default defineConfig({
  root: "website",
  base: "/reativa/",
  build: {
    outDir: "../_site",
    emptyOutDir: true
  },
  server: {
    fs: {
      allow: [".."]
    }
  }
});
