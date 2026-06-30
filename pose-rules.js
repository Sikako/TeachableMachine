(function attachPoseRules(root) {
    function getReliablePoint(pointsByPart, part, minConfidence) {
        const point = pointsByPart.get(part);
        if (!point || point.score < minConfidence || !point.position) {
            return null;
        }
        return point.position;
    }

    function classifyPoseGeometry(keypoints, minConfidence = 0.5) {
        if (!Array.isArray(keypoints)) {
            return null;
        }

        const pointsByPart = new Map(keypoints.map((point) => [point.part, point]));
        const leftShoulder = getReliablePoint(pointsByPart, "leftShoulder", minConfidence);
        const rightShoulder = getReliablePoint(pointsByPart, "rightShoulder", minConfidence);
        const leftWrist = getReliablePoint(pointsByPart, "leftWrist", minConfidence);
        const rightWrist = getReliablePoint(pointsByPart, "rightWrist", minConfidence);
        const leftHip = getReliablePoint(pointsByPart, "leftHip", minConfidence);
        const rightHip = getReliablePoint(pointsByPart, "rightHip", minConfidence);

        if (!leftShoulder || !rightShoulder || !leftWrist || !rightWrist || !leftHip || !rightHip) {
            return null;
        }

        const shoulderY = (leftShoulder.y + rightShoulder.y) / 2;
        const hipY = (leftHip.y + rightHip.y) / 2;
        const torsoHeight = hipY - shoulderY;
        if (torsoHeight <= 0) {
            return null;
        }

        const openMargin = Math.max(8, torsoHeight * 0.1);
        const wristsAboveShoulders =
            leftWrist.y <= leftShoulder.y - openMargin &&
            rightWrist.y <= rightShoulder.y - openMargin;
        if (wristsAboveShoulders) {
            return "up";
        }

        const waistThreshold = shoulderY + torsoHeight * 0.65;
        const wristsNearWaist = leftWrist.y >= waistThreshold && rightWrist.y >= waistThreshold;
        if (wristsNearWaist) {
            return "down";
        }

        return null;
    }

    function combinePoseState(modelState, modelConfidence, geometryState, minModelConfidence = 0.75) {
        if (modelConfidence < minModelConfidence || !geometryState || modelState !== geometryState) {
            return null;
        }
        return modelState;
    }

    function createPoseStabilizer(requiredFrames = 2) {
        let stableState = null;
        let candidateState = null;
        let candidateFrames = 0;

        return function stabilize(nextState) {
            if (!nextState) {
                candidateState = null;
                candidateFrames = 0;
                return null;
            }
            if (nextState === stableState) {
                candidateState = null;
                candidateFrames = 0;
                return stableState;
            }
            if (nextState !== candidateState) {
                candidateState = nextState;
                candidateFrames = 1;
                return stableState;
            }

            candidateFrames += 1;
            if (candidateFrames >= requiredFrames) {
                stableState = candidateState;
                candidateState = null;
                candidateFrames = 0;
            }
            return stableState;
        };
    }

    const api = {
        classifyPoseGeometry,
        combinePoseState,
        createPoseStabilizer
    };

    if (typeof module !== "undefined" && module.exports) {
        module.exports = api;
    }
    root.PoseRules = api;
}(typeof globalThis !== "undefined" ? globalThis : window));
