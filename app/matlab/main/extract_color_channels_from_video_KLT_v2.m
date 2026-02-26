function rawColorSignal = extract_color_channels_from_video_KLT_v2(video_input, videoSettings)
%EXTRACT_COLOR_CHANNELS_FROM_VIDEO_KLT_RECT_WAITFACE
% Viola-Jones face detection + KLT tracking + masked ROI averaging.
% Waits until a face is in view (up to maxWaitSec) before starting.
%
% Output:
%   rawColorSignal : [Nframes x 3] where cols = [R G B] means (0..255)
%
% Notes:
% - Uses videoSettings fields:
%     isHSVmaskingOn, hsvMin, hsvMax
%     isSTDmaskingOn, stdCoef
% - Shrinks ROI to reduce eyes/mouth/hair/background contamination.
% - If no face is detected within maxWaitSec, returns [].

    if nargin < 2 || isempty(videoSettings)
        videoSettings = configure_video_settings();
    end

    %% ---------- Open video ----------
    if isa(video_input, "VideoReader")
        videoReader = video_input;
    elseif ischar(video_input) || isstring(video_input)
        videoReader = VideoReader(video_input);
    else
        error("video_input must be a filename (char/string) or a VideoReader object.");
    end

    if ~hasFrame(videoReader)
        error("Video appears to have no frames.");
    end

    fps = videoReader.FrameRate;

    %% ---------- Face detector ----------
    faceDetector = vision.CascadeObjectDetector();
    % Slightly higher merge threshold can reduce jittery detections
    faceDetector.MergeThreshold = 4;

    %% ---------- Wait until a valid face is detected ----------
    maxWaitSec = 5;                      % DEFAULT: wait up to 5 seconds
    maxWaitFrames = max(1, round(maxWaitSec * fps));

    found = false;
    frameCount = 0;

    % We will optionally pad these skipped frames with NaNs
    PAD_SKIPPED_FRAMES = true;

    while hasFrame(videoReader) && frameCount < maxWaitFrames
        videoFrame = readFrame(videoReader);
        frameCount = frameCount + 1;

        bboxAll = step(faceDetector, videoFrame);
        if ~isempty(bboxAll)
            % choose largest face
            [~, idx] = max(bboxAll(:,3) .* bboxAll(:,4));
            bbox = bboxAll(idx,:);
            found = true;
            break;
        end
    end

    if ~found
        warning("No face detected in first %.1f seconds; skipping video.", maxWaitSec);
        rawColorSignal = [];
        return;
    end

    bboxPoints = double(bbox2points(bbox));

    %% ---------- Detect features inside face ROI ----------
    grayFrame = im2gray(videoFrame);
    ptsObj = detectMinEigenFeatures(grayFrame, "ROI", bbox);

    if ptsObj.Count < 2
        warning("Not enough features in face ROI; using global features fallback.");
        ptsObj = detectMinEigenFeatures(grayFrame);
    end

    if ptsObj.Count < 2
        warning("Could not find enough features to track; skipping video.");
        rawColorSignal = [];
        return;
    end

    points = ptsObj.Location;     % Nx2 double
    oldPoints = points;

    %% ---------- Setup KLT point tracker ----------
    pointTracker = vision.PointTracker("MaxBidirectionalError", 2);
    initialize(pointTracker, points, videoFrame);

    %% ---------- Helper: mean RGB in ROI with shrink + masking ----------
    function [rgbMean, maskFrac] = meanRGB_masked(frame, bboxPts)
        [h, w, ~] = size(frame);

        xs = bboxPts(:,1);
        ys = bboxPts(:,2);

        x1 = max(1, floor(min(xs)));
        x2 = min(w, ceil(max(xs)));
        y1 = max(1, floor(min(ys)));
        y2 = min(h, ceil(max(ys)));

        if x2 <= x1 || y2 <= y1
            rgbMean  = [NaN NaN NaN];
            maskFrac = 0;
            return;
        end

        % ---- ROI shrink (avoid hair/eyes/mouth/edges) ----
        shrinkX = 0.15;   % 15% each side
        shrinkY = 0.20;   % 20% each side (vertical more aggressive)

        dx = x2 - x1;
        dy = y2 - y1;

        x1 = x1 + round(shrinkX * dx);
        x2 = x2 - round(shrinkX * dx);
        y1 = y1 + round(shrinkY * dy);
        y2 = y2 - round(shrinkY * dy);

        if x2 <= x1 || y2 <= y1
            rgbMean  = [NaN NaN NaN];
            maskFrac = 0;
            return;
        end

        roi = frame(y1:y2, x1:x2, :);
        roiD = im2double(roi);

        R = roiD(:,:,1);
        G = roiD(:,:,2);
        B = roiD(:,:,3);

        mask = true(size(R));

        % ---- HSV skin masking ----
        if isfield(videoSettings,'isHSVmaskingOn') && videoSettings.isHSVmaskingOn
            hsvImg = rgb2hsv(roiD);
            Hh = hsvImg(:,:,1); Ss = hsvImg(:,:,2); Vv = hsvImg(:,:,3);

            hMin = videoSettings.hsvMin(1); sMin = videoSettings.hsvMin(2); vMin = videoSettings.hsvMin(3);
            hMax = videoSettings.hsvMax(1); sMax = videoSettings.hsvMax(2); vMax = videoSettings.hsvMax(3);

            hsvMask = (Hh>=hMin & Hh<=hMax) & (Ss>=sMin & Ss<=sMax) & (Vv>=vMin & Vv<=vMax);
            mask = mask & hsvMask;
        end

        % ---- STD masking (remove extreme/noisy pixels) ----
        if isfield(videoSettings,'isSTDmaskingOn') && videoSettings.isSTDmaskingOn
            stdCoef = videoSettings.stdCoef;
            I = G; % use green intensity

            mu = median(I(:));
            sigma = std(I(:));

            if sigma > 0
                stdMask = abs(I - mu) <= stdCoef * sigma;
                mask = mask & stdMask;
            end
        end

        maskFrac = nnz(mask) / numel(mask);

        % If mask collapses, fall back to whole ROI to avoid NaN floods
        if maskFrac < 0.10
            mask = true(size(mask));
            maskFrac = 1.0;
        end

        rgbMean = [mean(R(mask)), mean(G(mask)), mean(B(mask))] * 255;
    end

    %% ---------- Initialize output ----------
    if PAD_SKIPPED_FRAMES
        rawColorSignal = NaN(frameCount-1, 3); % frames before detection
    else
        rawColorSignal = zeros(0,3);
    end

    % First sample at the detection frame
    [rgb0, ~] = meanRGB_masked(videoFrame, bboxPoints);
    rawColorSignal(end+1,:) = rgb0;

    %% ---------- Process remaining frames ----------
    while hasFrame(videoReader)
        videoFrame = readFrame(videoReader);

        % Track points
        [pointsNew, isFound] = step(pointTracker, videoFrame);
        visiblePoints = pointsNew(isFound,:);
        oldInliers    = oldPoints(isFound,:);

        if size(visiblePoints,1) >= 2
            [xform, inlierIdx] = estimateGeometricTransform2D( ...
                oldInliers, visiblePoints, "similarity", "MaxDistance", 4);

            oldInliers    = oldInliers(inlierIdx,:);
            visiblePoints = visiblePoints(inlierIdx,:);

            bboxPoints = transformPointsForward(xform, bboxPoints);

            oldPoints = visiblePoints;
            setPoints(pointTracker, oldPoints);

        else
            % Too few points -> re-detect face and REINITIALIZE tracker
            bboxAll = step(faceDetector, videoFrame);
            if ~isempty(bboxAll)
                [~, idx] = max(bboxAll(:,3).*bboxAll(:,4));
                bbox = bboxAll(idx,:);
                bboxPoints = double(bbox2points(bbox));

                grayFrame = im2gray(videoFrame);
                ptsObj = detectMinEigenFeatures(grayFrame, "ROI", bbox);

                if ptsObj.Count >= 2
                    points = ptsObj.Location;

                    release(pointTracker);
                    pointTracker = vision.PointTracker("MaxBidirectionalError", 2);
                    initialize(pointTracker, points, videoFrame);

                    oldPoints = points;
                end
            end
        end

        [rgbMean, ~] = meanRGB_masked(videoFrame, bboxPoints);
        rawColorSignal(end+1,:) = rgbMean; %#ok<AGROW>
    end

    release(pointTracker);
end
