import { createReadStream, watch } from "node:fs";
import { readFile, readdir, stat } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, join, normalize, relative, resolve, sep } from "node:path";

const defaultPort = Number.parseInt(process.env.PORT ?? "8080", 10);
const host = process.env.HOST ?? "127.0.0.1";
const reloadPath = "/__reativa/reload";
const reloadClient = `
<script>
(() => {
  const source = new EventSource("${reloadPath}");
  source.addEventListener("reload", () => window.location.reload());
})();
</script>`;

const args = process.argv.slice(2);
const portFlagIndex = args.indexOf("--port");
const rootFlagIndex = args.indexOf("--root");
const port =
  portFlagIndex === -1 ? defaultPort : Number.parseInt(args[portFlagIndex + 1] ?? "", 10);
const root = rootFlagIndex === -1 ? process.env.DEMO_ROOT ?? "demo" : args[rootFlagIndex + 1];
const demoRoot = resolve(root ?? "");

if (!Number.isInteger(port) || port < 0 || port > 65535) {
  console.error("Invalid port. Use PORT=8080 or --port 8080.");
  process.exit(1);
}

if (!root) {
  console.error("Invalid demo root. Use DEMO_ROOT=demo/ui or --root demo/ui.");
  process.exit(1);
}

const contentTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".map", "application/json; charset=utf-8"],
  [".svg", "image/svg+xml"],
]);

const reloadClients = new Set();
let reloadTimer = null;

function requestPathname(url) {
  try {
    return decodeURIComponent(new URL(url, "http://localhost").pathname);
  } catch {
    return null;
  }
}

function scheduleReload() {
  clearTimeout(reloadTimer);
  reloadTimer = setTimeout(() => {
    for (const client of reloadClients) {
      client.write("event: reload\ndata: changed\n\n");
    }
  }, 80);
}

async function watchDemoRoot() {
  const watchedDirectories = new Set();

  async function watchDirectory(directory) {
    if (watchedDirectories.has(directory)) {
      return;
    }

    watchedDirectories.add(directory);

    try {
      const watcher = watch(directory, (_event, filename) => {
        if (!filename) {
          scheduleReload();
          return;
        }

        const changedPath = normalize(filename.toString());

        if (changedPath.includes(`${sep}.`) || changedPath.endsWith("~")) {
          return;
        }

        scheduleReload();
      });

      watcher.on("error", (error) => {
        console.error(`Unable to watch ${relative(process.cwd(), directory)}: ${error.message}`);
      });
    } catch (error) {
      console.error(`Unable to watch ${relative(process.cwd(), directory)}: ${error.message}`);
      return;
    }

    const entries = await readdir(directory, { withFileTypes: true });

    await Promise.all(
      entries
        .filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
        .map((entry) => watchDirectory(join(directory, entry.name))),
    );
  }

  try {
    await watchDirectory(demoRoot);
  } catch (error) {
    console.error(`Unable to watch demo files: ${error.message}`);
  }
}

function serveReloadEvents(req, res) {
  if (req.method !== "GET") {
    res.writeHead(405, { Allow: "GET" });
    res.end("Method not allowed\n");
    return;
  }

  res.writeHead(200, {
    "Cache-Control": "no-store",
    "Connection": "keep-alive",
    "Content-Type": "text/event-stream; charset=utf-8",
  });
  res.write("event: ready\ndata: connected\n\n");

  reloadClients.add(res);

  req.on("close", () => {
    reloadClients.delete(res);
  });
}

function resolveRequestPath(url) {
  const pathname = requestPathname(url);

  if (!pathname) {
    return null;
  }

  const normalizedPath = normalize(pathname).replace(/^(\.\.(\/|\\|$))+/, "");
  const relativePath = normalizedPath === sep ? "index.html" : normalizedPath.slice(1);
  const filePath = resolve(join(demoRoot, relativePath));

  if (filePath !== demoRoot && !filePath.startsWith(`${demoRoot}${sep}`)) {
    return null;
  }

  return filePath;
}

async function serveHtml(filePath, fileStat, res) {
  const html = await readFile(filePath, "utf8");
  const body = html.includes("</body>")
    ? html.replace("</body>", `${reloadClient}\n  </body>`)
    : `${html}\n${reloadClient}\n`;

  res.writeHead(200, {
    "Cache-Control": "no-store",
    "Content-Length": Buffer.byteLength(body),
    "Content-Type": "text/html; charset=utf-8",
    "Last-Modified": fileStat.mtime.toUTCString(),
  });
  res.end(body);
}

async function serveFile(req, res) {
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.writeHead(405, { Allow: "GET, HEAD" });
    res.end("Method not allowed\n");
    return;
  }

  const filePath = resolveRequestPath(req.url ?? "/");

  if (!filePath) {
    res.writeHead(403);
    res.end("Forbidden\n");
    return;
  }

  try {
    const fileStat = await stat(filePath);

    if (!fileStat.isFile()) {
      res.writeHead(404);
      res.end("Not found\n");
      return;
    }

    if (extname(filePath) === ".html") {
      if (req.method === "HEAD") {
        res.writeHead(200, {
          "Cache-Control": "no-store",
          "Content-Type": "text/html; charset=utf-8",
          "Last-Modified": fileStat.mtime.toUTCString(),
        });
        res.end();
        return;
      }

      await serveHtml(filePath, fileStat, res);
      return;
    }

    res.writeHead(200, {
      "Cache-Control": "no-store",
      "Content-Length": fileStat.size,
      "Content-Type": contentTypes.get(extname(filePath)) ?? "application/octet-stream",
      "Last-Modified": fileStat.mtime.toUTCString(),
    });

    if (req.method === "HEAD") {
      res.end();
      return;
    }

    createReadStream(filePath).pipe(res);
  } catch (error) {
    if (error?.code === "ENOENT") {
      res.writeHead(404);
      res.end("Not found\n");
      return;
    }

    console.error(error);
    res.writeHead(500);
    res.end("Internal server error\n");
  }
}

const server = createServer((req, res) => {
  if (requestPathname(req.url ?? "/") === reloadPath) {
    serveReloadEvents(req, res);
    return;
  }

  serveFile(req, res);
});

server.on("error", (error) => {
  console.error(`Unable to serve demo: ${error.message}`);
  process.exit(1);
});

server.listen(port, host, () => {
  const address = server.address();
  const resolvedPort = typeof address === "object" && address ? address.port : port;
  const servedPath = relative(process.cwd(), demoRoot) || ".";

  console.log(`Serving ${servedPath} at http://${host}:${resolvedPort}/`);
  watchDemoRoot();
});
