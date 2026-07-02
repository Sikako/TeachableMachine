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

test("offers every available video input and switches the active webcam", () => {
    assert.match(html, /class="settings-row"/);
    assert.match(html, /<select[^>]+id="cameraSelect"/);
    assert.match(html, /navigator\.mediaDevices\.enumerateDevices\(\)/);
    assert.match(html, /device\.kind === "videoinput"/);
    assert.match(html, /webcam\.setup\(\{ deviceId: \{ exact: deviceId \} \}\)/);
    assert.match(html, /cameraSelect\.addEventListener\("change", switchCamera\)/);
});

test("stops the previous camera before opening another one", () => {
    assert.match(html, /webcam\.stop\(\)/);
    assert.match(html, /async function switchCamera/);
});

test("keeps the complete interface inside one viewport without scrolling", () => {
    assert.match(html, /body\s*\{[^}]*height:\s*100dvh;[^}]*overflow:\s*hidden;/s);
    assert.match(html, /\.page\s*\{[^}]*height:\s*100dvh;[^}]*overflow:\s*hidden;/s);
    assert.match(html, /@media\s*\(max-height:\s*760px\)/);
});
