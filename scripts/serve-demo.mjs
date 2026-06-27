import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, join, normalize, resolve, sep } from "node:path";

const demoRoot = resolve("demo");
const defaultPort = Number.parseInt(process.env.PORT ?? "8080", 10);
const host = process.env.HOST ?? "127.0.0.1";

const args = process.argv.slice(2);
const portFlagIndex = args.indexOf("--port");
const port =
  portFlagIndex === -1 ? defaultPort : Number.parseInt(args[portFlagIndex + 1] ?? "", 10);

if (!Number.isInteger(port) || port < 0 || port > 65535) {
  console.error("Invalid port. Use PORT=8080 or --port 8080.");
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

function resolveRequestPath(url) {
  let pathname;

  try {
    pathname = decodeURIComponent(new URL(url, "http://localhost").pathname);
  } catch {
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

    res.writeHead(200, {
      "Content-Length": fileStat.size,
      "Content-Type": contentTypes.get(extname(filePath)) ?? "application/octet-stream",
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
  serveFile(req, res);
});

server.on("error", (error) => {
  console.error(`Unable to serve demo: ${error.message}`);
  process.exit(1);
});

server.listen(port, host, () => {
  const address = server.address();
  const resolvedPort = typeof address === "object" && address ? address.port : port;

  console.log(`Serving demo at http://${host}:${resolvedPort}/`);
});
