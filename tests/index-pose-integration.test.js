const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");

test("loads and uses geometry rules in the live prediction loop", () => {
    assert.match(html, /<script src="\.\/pose-rules\.js"><\/script>/);
    assert.match(html, /classifyPoseGeometry\(pose\?\.keypoints/);
    assert.match(html, /combinePoseState\(/);
    assert.match(html, /stabilizePoseState\(/);
});
