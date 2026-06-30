const test = require("node:test");
const assert = require("node:assert/strict");

const {
    classifyPoseGeometry,
    combinePoseState,
    createPoseStabilizer
} = require("../pose-rules.js");

function keypoint(part, x, y, score = 0.99) {
    return { part, position: { x, y }, score };
}

function pose(overrides = {}) {
    const points = {
        leftShoulder: keypoint("leftShoulder", 180, 180),
        rightShoulder: keypoint("rightShoulder", 300, 180),
        leftWrist: keypoint("leftWrist", 150, 110),
        rightWrist: keypoint("rightWrist", 330, 110),
        leftHip: keypoint("leftHip", 205, 320),
        rightHip: keypoint("rightHip", 275, 320),
        ...overrides
    };
    return Object.values(points);
}

test("classifies open only when both wrists are clearly above the shoulders", () => {
    assert.equal(classifyPoseGeometry(pose()), "up");
    assert.equal(classifyPoseGeometry(pose({
        rightWrist: keypoint("rightWrist", 330, 195)
    })), null);
});

test("classifies closed when both wrists return near or below the waist", () => {
    assert.equal(classifyPoseGeometry(pose({
        leftWrist: keypoint("leftWrist", 185, 305),
        rightWrist: keypoint("rightWrist", 295, 305)
    })), "down");
});

test("rejects geometry when a required keypoint has low confidence", () => {
    assert.equal(classifyPoseGeometry(pose({
        leftWrist: keypoint("leftWrist", 150, 110, 0.2)
    })), null);
});

test("accepts a model result only when confidence and geometry agree", () => {
    assert.equal(combinePoseState("up", 0.9, "up"), "up");
    assert.equal(combinePoseState("up", 0.9, "down"), null);
    assert.equal(combinePoseState("up", 0.7, "up"), null);
});

test("requires two consecutive matching frames without skipping inference frames", () => {
    const stabilize = createPoseStabilizer(2);

    assert.equal(stabilize("up"), null);
    assert.equal(stabilize("down"), null);
    assert.equal(stabilize("up"), null);
    assert.equal(stabilize("up"), "up");
});
