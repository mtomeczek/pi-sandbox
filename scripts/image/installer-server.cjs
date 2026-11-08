// Build-only, loopback-only snapshot for the official installer's release API.
"use strict";
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");

const [, , directory, version] = process.argv;
if (!directory || !/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(version || "")) {
    throw new Error("Expected a snapshot directory and an exact Pi version");
}
const routes = new Map([
    ["/latest", JSON.stringify({ version })],
    [`/${version}/package.json`, fs.readFileSync(path.join(directory, "package.json"))],
    [`/${version}/package-lock.json`, fs.readFileSync(path.join(directory, "package-lock.json"))],
]);
const server = http.createServer((request, response) => {
    const body = request.method === "GET" ? routes.get(request.url) : undefined;
    response.writeHead(body === undefined ? 404 : 200, { "Content-Type": "application/json" });
    response.end(body === undefined ? "{}" : body);
});
server.listen(0, "127.0.0.1", () => {
    fs.writeFileSync(path.join(directory, "port"), String(server.address().port));
});
