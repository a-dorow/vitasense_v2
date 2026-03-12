%% ===================== HRV FROM iPPG FIG =====================
clear; clc; close all;

%% --------------------- USER INPUT ---------------------
figPath = "C:\Users\avask\OneDrive\Desktop\bpSp02-estimation-ippg\Extraction Methods\CHROM\subject1_CHROM_iPPG.fig";
fs = 30;   % camera frame rate in Hz

% Windowed HRV settings
windowLengthSec = 10;   % 10-second HRV windows
windowStepSec   = 5;    % 5-second overlap step

%% --------------------- OPEN FIG AND EXTRACT SIGNAL ---------------------
figHandle = openfig(figPath, 'invisible');
cleanupFig = onCleanup(@() close(figHandle));

ax = findobj(figHandle, 'Type', 'axes');
if isempty(ax)
    error('No axes found in the .fig file.');
end

lineObjs = findobj(ax, 'Type', 'line');
if isempty(lineObjs)
    error('No line objects found in the .fig file.');
end

maxLen = 0;
bestIdx = 1;

for k = 1:numel(lineObjs)
    xk = get(lineObjs(k), 'XData');
    yk = get(lineObjs(k), 'YData');

    if isnumeric(xk) && isnumeric(yk) && numel(xk) == numel(yk) && numel(yk) > maxLen
        maxLen = numel(yk);
        bestIdx = k;
    end
end

ippg = get(lineObjs(bestIdx), 'YData');
ippg = ippg(:);

if numel(ippg) < 10
    error('Extracted signal is too short.');
end

t = (0:numel(ippg)-1)' / fs;

signalDurationSec = numel(ippg) / fs;
fprintf('Signal duration: %.2f s\n', signalDurationSec);

if signalDurationSec < 10
    error('Signal too short. Need at least about 10 seconds.');
elseif signalDurationSec < 30
    warning('Short signal (%.2f s). HRV estimates may be unstable.', signalDurationSec);
end

%% --------------------- PREPROCESSING ---------------------
[b, a] = butter(3, [0.7 2.2] / (fs/2), 'bandpass');

sig = detrend(ippg);
sig = filtfilt(b, a, sig);
sig = movmean(sig, 5);

sigStd = std(sig, 'omitnan');
if sigStd == 0 || ~isfinite(sigStd)
    error('Filtered signal has zero or invalid standard deviation.');
end

sig = (sig - mean(sig, 'omitnan')) / sigStd;

%% --------------------- OPTIONAL POLARITY CHECK ---------------------
[pks_pos, ~] = findpeaks(sig);
[pks_neg, ~] = findpeaks(-sig);

if isempty(pks_pos)
    medPos = -Inf;
else
    medPos = median(pks_pos, 'omitnan');
end

if isempty(pks_neg)
    medNeg = -Inf;
else
    medNeg = median(pks_neg, 'omitnan');
end

if medNeg > medPos
    sig = -sig;
    signalFlipped = 1;
else
    signalFlipped = 0;
end

%% --------------------- ENVELOPE-STYLE CANDIDATE DETECTION ---------------------
sigSmooth = movmean(sig, 3);
envSig = movmax(sigSmooth, [1 1]);

minPeakDistanceSec = 0.60;
minPeakDistanceSamples = max(1, round(minPeakDistanceSec * fs));

minProm = 0.15 * std(envSig, 'omitnan');

[candPks, candLocs] = findpeaks(envSig, ...
    'MinPeakDistance', minPeakDistanceSamples, ...
    'MinPeakProminence', minProm);

if numel(candLocs) < 5
    error('Too few candidate peaks detected.');
end

%% --------------------- SNAP CANDIDATES TO TRUE LOCAL MAXIMA ---------------------
searchRadius = 3;
locs_refined_int = nan(size(candLocs));
truePks = nan(size(candLocs));

for i = 1:numel(candLocs)
    k = candLocs(i);

    leftIdx  = max(1, k - searchRadius);
    rightIdx = min(numel(sig), k + searchRadius);

    [localPk, relIdx] = max(sig(leftIdx:rightIdx));
    locs_refined_int(i) = leftIdx + relIdx - 1;
    truePks(i) = localPk;
end

[locs_refined_int, uniqIdx] = unique(locs_refined_int, 'stable');
truePks = truePks(uniqIdx);

if numel(locs_refined_int) < 5
    error('Too few peaks remain after local snapping.');
end

%% --------------------- PEAK AMPLITUDE CLEANING ---------------------
medPk = median(truePks, 'omitnan');
goodPeakMask = truePks >= 0.60 * medPk;

locs_refined_int = locs_refined_int(goodPeakMask);
truePks = truePks(goodPeakMask);

if numel(locs_refined_int) < 5
    error('Too few peaks remain after peak amplitude cleaning.');
end

%% --------------------- SUB-SAMPLE REFINEMENT ---------------------
refinedLocs = nan(size(locs_refined_int));

for i = 1:numel(locs_refined_int)
    k = locs_refined_int(i);

    if k <= 1 || k >= numel(sig)
        refinedLocs(i) = k;
        continue;
    end

    y1 = sig(k-1);
    y2 = sig(k);
    y3 = sig(k+1);

    denom = (y1 - 2*y2 + y3);

    if abs(denom) < eps
        delta = 0;
    else
        delta = 0.5 * (y1 - y3) / denom;
    end

    delta = max(min(delta, 0.5), -0.5);
    refinedLocs(i) = k + delta;
end

peakTimes = (refinedLocs - 1) / fs;

%% --------------------- PULSE-TO-PULSE INTERVALS ---------------------
ppi_sec = diff(peakTimes);
ppi_ms = 1000 * ppi_sec;

valid = ppi_sec >= 0.50 & ppi_sec <= 1.30;

ppi_sec_valid = ppi_sec(valid);
ppi_ms_valid = ppi_ms(valid);

if numel(ppi_ms_valid) < 3
    error('Too few valid intervals after physiologic screening.');
end

%% --------------------- INTERVAL OUTLIER SUPPRESSION ---------------------
if numel(ppi_ms_valid) >= 3
    ppi_ms_smooth = medfilt1(ppi_ms_valid, 3);
else
    ppi_ms_smooth = ppi_ms_valid;
end

ppi_sec_smooth = ppi_ms_smooth / 1000;

globalMed = median(ppi_ms_smooth, 'omitnan');
keep = abs(ppi_ms_smooth - globalMed) <= 0.25 * globalMed;

ppi_ms_clean = ppi_ms_smooth(keep);
ppi_sec_clean = ppi_sec_smooth(keep);

% Approximate time assigned to each interval = time of second beat in pair
ppi_times_all = peakTimes(2:end);
ppi_times_valid = ppi_times_all(valid);
ppi_times_clean = ppi_times_valid(keep);

if numel(ppi_ms_clean) < 3
    error('Too few clean intervals after artifact rejection.');
end

if numel(ppi_ms_clean) < 8
    warning('Very few clean intervals remain (%d). HRV reliability is limited.', numel(ppi_ms_clean));
elseif numel(ppi_ms_clean) < 15
    warning('Clean interval count is low (%d). HRV should be treated cautiously.', numel(ppi_ms_clean));
end

%% --------------------- HRV METRICS ---------------------
% Interval-derived HR is diagnostic only. Pipeline HR should still come from FFT.
instHR_bpm = 60 ./ ppi_sec_clean;

meanHR_bpm = mean(instHR_bpm, 'omitnan');
meanNN_ms  = mean(ppi_ms_clean, 'omitnan');
SDNN_ms    = std(ppi_ms_clean, 'omitnan');
RMSSD_ms   = sqrt(mean(diff(ppi_ms_clean).^2, 'omitnan'));
CVNN_percent = 100 * (SDNN_ms / meanNN_ms);

if numel(ppi_ms_clean) >= 2
    nnDiff = abs(diff(ppi_ms_clean));
    pNN50_percent = 100 * sum(nnDiff > 50) / numel(nnDiff);
else
    pNN50_percent = NaN;
end

%% --------------------- WINDOWED HRV (RMSSD) ---------------------
windowStarts = 0:windowStepSec:max(0, signalDurationSec - windowLengthSec);
windowEnds = windowStarts + windowLengthSec;

rmssd_window_values = nan(size(windowStarts));
window_interval_counts = zeros(size(windowStarts));

for w = 1:numel(windowStarts)
    idx = ppi_times_clean >= windowStarts(w) & ppi_times_clean < windowEnds(w);
    ppi_win = ppi_ms_clean(idx);

    window_interval_counts(w) = numel(ppi_win);

    % Need at least 3 intervals to compute diff-based RMSSD sensibly
    if numel(ppi_win) >= 3
        rmssd_window_values(w) = sqrt(mean(diff(ppi_win).^2, 'omitnan'));
    end
end

validWindowMask = ~isnan(rmssd_window_values);

if any(validWindowMask)
    RMSSD_windowed_mean_ms = mean(rmssd_window_values(validWindowMask), 'omitnan');
    RMSSD_windowed_std_ms  = std(rmssd_window_values(validWindowMask), 'omitnan');
    numValidWindows = sum(validWindowMask);
else
    RMSSD_windowed_mean_ms = NaN;
    RMSSD_windowed_std_ms  = NaN;
    numValidWindows = 0;
end

% Final HRV display metric should use windowed RMSSD if available
if ~isnan(RMSSD_windowed_mean_ms)
    HRV_display_ms = RMSSD_windowed_mean_ms;
else
    HRV_display_ms = RMSSD_ms;
end

%% --------------------- DISPLAY RESULTS ---------------------
fprintf('\n===== HRV RESULTS FROM iPPG FIG =====\n');
fprintf('File: %s\n', figPath);
fprintf('Sampling frequency: %.2f Hz\n', fs);
fprintf('Signal flipped: %d\n', signalFlipped);
fprintf('Detected peaks after refinement: %d\n', numel(refinedLocs));
fprintf('Clean intervals: %d\n', numel(ppi_ms_clean));
fprintf('Mean HR (interval-derived, diagnostic only): %.2f bpm\n', meanHR_bpm);
fprintf('Mean NN: %.2f ms\n', meanNN_ms);
fprintf('SDNN: %.2f ms\n', SDNN_ms);
fprintf('RMSSD (global): %.2f ms\n', RMSSD_ms);
fprintf('CVNN: %.2f %%\n', CVNN_percent);
fprintf('pNN50: %.2f %%\n', pNN50_percent);
fprintf('Windowed RMSSD mean: %.2f ms\n', RMSSD_windowed_mean_ms);
fprintf('Windowed RMSSD std: %.2f ms\n', RMSSD_windowed_std_ms);
fprintf('Valid RMSSD windows: %d\n', numValidWindows);
fprintf('Final HRV display metric: %.2f ms\n', HRV_display_ms);

disp('Raw PPI (ms):');
disp(ppi_ms');

disp('Valid PPI (ms):');
disp(ppi_ms_valid');

disp('Smoothed PPI (ms):');
disp(ppi_ms_smooth');

disp('Keep mask (1 = kept, 0 = rejected):');
disp(double(keep)');

disp('Windowed RMSSD values (ms):');
disp(rmssd_window_values');

disp('Intervals per window:');
disp(window_interval_counts');

%% --------------------- OPTIONAL EXPORT STRUCT ---------------------
results = struct();
results.figPath = figPath;
results.fs = fs;
results.signalDurationSec = signalDurationSec;
results.signalFlipped = signalFlipped;
results.detectedPeaks = numel(refinedLocs);
results.cleanIntervals = numel(ppi_ms_clean);
results.meanHR_bpm_interval = meanHR_bpm;
results.meanNN_ms = meanNN_ms;
results.SDNN_ms = SDNN_ms;
results.RMSSD_ms = RMSSD_ms;
results.CVNN_percent = CVNN_percent;
results.pNN50_percent = pNN50_percent;
results.RMSSD_windowed_mean_ms = RMSSD_windowed_mean_ms;
results.RMSSD_windowed_std_ms = RMSSD_windowed_std_ms;
results.numValidWindows = numValidWindows;
results.HRV_display_ms = HRV_display_ms;
results.ppi_ms_clean = ppi_ms_clean;
results.ppi_times_clean = ppi_times_clean;
results.peakTimes_sec = peakTimes;

%% --------------------- PLOTS ---------------------
figure('Color', 'w', 'Name', 'iPPG HRV Analysis');

subplot(7,1,1);
plot(t, ippg, 'b');
xlabel('Time (s)');
ylabel('Amplitude');
title('Raw iPPG Extracted from .fig');

subplot(7,1,2);
plot(t, sig, 'k'); hold on;
plot((refinedLocs-1)/fs, interp1(1:numel(sig), sig, refinedLocs, 'linear'), ...
    'ro', 'MarkerSize', 6, 'LineWidth', 1.2);
xlabel('Time (s)');
ylabel('Filtered');
title('Filtered iPPG with Refined Peaks');

subplot(7,1,3);
plot(peakTimes(2:end), ppi_ms, 'o-');
xlabel('Time (s)');
ylabel('PPI (ms)');
title('Raw Pulse-to-Pulse Intervals');

subplot(7,1,4);
plot(ppi_ms_valid, 'o-', 'DisplayName', 'Valid intervals'); hold on;
plot(ppi_ms_smooth, 's-', 'DisplayName', 'Median filtered');
xlabel('Beat Index');
ylabel('PPI (ms)');
title('Interval Series Before and After Smoothing');
legend('Location', 'best');

subplot(7,1,5);
plot(ppi_ms_smooth, 'o-', 'DisplayName', 'Smoothed intervals'); hold on;
plot(find(keep), ppi_ms_clean, 'ro-', 'LineWidth', 1.2, 'DisplayName', 'Kept intervals');
xlabel('Beat Index');
ylabel('PPI (ms)');
title('Smoothed vs Kept Pulse Intervals');
legend('Location', 'best');

subplot(7,1,6);
if ~isempty(windowStarts)
    validIdx = find(validWindowMask);
    plot(windowStarts(validIdx) + windowLengthSec/2, rmssd_window_values(validIdx), 'o-');
    xlabel('Window Center Time (s)');
    ylabel('RMSSD (ms)');
    title('Windowed RMSSD');
else
    text(0.5, 0.5, 'No windows available', 'HorizontalAlignment', 'center');
    axis off;
end

subplot(7,1,7);
plot(ppi_ms_clean, 'o-');
xlabel('Beat Index');
ylabel('Clean PPI (ms)');
title(sprintf('HRV Display = %.1f ms | Global RMSSD = %.1f ms | SDNN = %.1f ms', ...
    HRV_display_ms, RMSSD_ms, SDNN_ms));