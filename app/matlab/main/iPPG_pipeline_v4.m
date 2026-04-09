function [hr_bpm, spo2_pct, rawColorSignal_out, Fs_out] = iPPG_pipeline_v4(video_path, plot_path, trace_folder, main_path, doPopup)
% iPPG_pipeline_v4 (VIDEO-ONLY)
% Fully automated iPPG extraction + plotting + FFT post-processing.
%
% Modes:
%   doPopup = false (Research) — cycles through ALL extraction methods,
%       saves .fig files, runs full FFT post-processing.
%   doPopup = true  (Quick Popup) — runs CHROM only, no file I/O,
%       computes HR via inline Welch PSD, shows popup with results.
%
% Additional outputs (for BP reuse):
%   rawColorSignal_out : [Nframes x 3] extracted RGB signal
%   Fs_out             : video frame rate (Hz)

setup_paths();

if nargin < 5
    doPopup = false;
end
doPopup = logical(doPopup);

hr_bpm  = NaN;
spo2_pct = NaN;
rawColorSignal_out = [];
Fs_out = NaN;

% Ensure output folder exists (research mode needs it)
if ~doPopup && ~exist(plot_path,'dir'); mkdir(plot_path); end

%% Configure settings
videoSettings = configure_video_settings();
if ~doPopup
    plotSettings = configure_plot_settings();
end

% Fallback sampling rate (overwritten per video if possible)
VIDEO_SR = 30;

%% Resolve videos
if isfolder(video_path)
    subjects = dir(video_path);
    subjects = subjects([subjects.isdir]);
    subjects = subjects(~ismember({subjects.name}, {'.','..','desktop.ini'}));

    if isempty(subjects)
        vid_direct    = {video_path};
        subjects_info = {extract_subject_from_path(video_path)};
    else
        [vid_direct, subjects_info] = cycle_avi(video_path);
    end
else
    vid_direct    = {video_path};
    subjects_info = {extract_subject_from_path(video_path)};
end

%% Main loop
for i = 1:length(vid_direct)

    this_video   = vid_direct{i};
    subject_name = subjects_info{i};

    if ~doPopup
        subject_folder = create_sub_folder(plot_path, subject_name);
    end

    % ---- True FPS per video (reuse VideoReader for extraction) ----
    Fs = VIDEO_SR;
    try
        vr = VideoReader(this_video);
        Fs = vr.FrameRate;
    catch
        vr = [];
    end
    Fs_out = Fs;

    ippgSettings = configure_ippg_settings(Fs);

    % ---- Extract RGB (KLT rect) — pass VideoReader to avoid re-opening ----
    if ~isempty(vr)
        rawColorSignal = extract_color_channels_from_video_KLT_v2(vr, videoSettings);
    else
        rawColorSignal = extract_color_channels_from_video_KLT_v2(this_video, videoSettings);
    end

    if isempty(rawColorSignal) || numel(rawColorSignal) < 10
        warning('[iPPG_pipeline_v4] No color signal extracted for %s. Face detection likely failed at this resolution — skipping subject.', subject_name);
        continue;
    end

    % Store for BP reuse
    rawColorSignal_out = rawColorSignal;

    % ---- Force RGB to 3xN ----
    rawColorSignal = local_interpolate_nonfinite(rawColorSignal);
    if size(rawColorSignal,2) == 3
        rawRGB = rawColorSignal.';
    elseif size(rawColorSignal,1) == 3
        rawRGB = rawColorSignal;
    else
        rawRGB = rawColorSignal.';
        if size(rawRGB,1) ~= 3
            continue;
        end
    end

    % ================= SpO2 (ONCE per video) =================
    SpO2_mean = NaN;
    try
        redSig   = rawRGB(1,:).';
        greenSig = rawRGB(2,:).';

        % Skip the first 6 seconds: camera/face-detection is still
        % stabilising and the signal is unreliable during that period.
        % Processing speed can push stabilisation beyond 6 s, so we
        % use a generous skip to ensure only settled signal is used.
        skipSec     = 6;
        skipSamples = floor(skipSec * Fs);
        if skipSamples >= length(redSig)
            skipSamples = 0;   % video is too short; skip nothing
        end
        redSig   = redSig(skipSamples+1:end);
        greenSig = greenSig(skipSamples+1:end);

        winLenSec = 4;
        stepSec   = 2;

        minSamples = winLenSec * Fs;
        if length(redSig) >= minSamples && length(greenSig) >= minSamples
            [SpO2_uncalib, ~, ~, R_vals] = ippg_spo2_fft(redSig, greenSig, Fs, winLenSec, stepSec);

            if ~isempty(R_vals)
                R_vals = R_vals(isfinite(R_vals));
                if ~isempty(R_vals)
                    R_mean = mean(R_vals);

                    persistent spo2Cal;
                    if isempty(spo2Cal)
                        if exist('spo2_calibration.mat','file')
                            S = load('spo2_calibration.mat');
                            if isfield(S,'p')
                                spo2Cal = S.p;   % [a1 a0]
                            end
                        end
                    end

                    if ~isempty(spo2Cal)
                        SpO2_mean = spo2Cal(1) * R_mean + spo2Cal(2);
                    else
                        SpO2_mean = SpO2_uncalib;
                    end

                    SpO2_mean = min(max(SpO2_mean, 80), 100);
                end
            end
        end
    catch
        SpO2_mean = NaN;
    end
    % Store SpO2 for return (single-video use case)
    spo2_pct = SpO2_mean;
    % =========================================================

    if doPopup
        % ===== QUICK POPUP: CHROM only, no file I/O =====
        ippgSettingsLocal = ippgSettings;
        ippgSettingsLocal.extractionMethod = 'CHROM';

        try
            iPPG = compute_ippg(rawRGB, ippgSettingsLocal);
        catch
            iPPG = rawRGB(2,:);
        end

        % Compute HR directly via inline Welch PSD (no .fig round-trip)
        hr_bpm = local_quick_hr(iPPG, Fs);

    else
        % ===== RESEARCH MODE: all extraction methods =====
        extraction_methods = fieldnames(ippgSettings.EXTRACTION);

        for j = 1:length(extraction_methods)

            method_name = extraction_methods{j};

            ippgSettingsLocal = ippgSettings;
            ippgSettingsLocal.extractionMethod = ...
                select_extraction_method(method_name, ippgSettingsLocal);

            % ---- iPPG ----
            try
                iPPG = compute_ippg(rawRGB, ippgSettingsLocal);
            catch
                iPPG = rawRGB(2,:); % GREEN fallback
            end

            % ---- Plot ----
            fig = figure('Visible','off');
            try
                t = (1:length(iPPG)) / Fs;
                plot(t, iPPG, 'LineWidth', plotSettings.lineWidth);
                set(gca, 'FontSize', plotSettings.fontSize, 'FontName', plotSettings.fontType);
                xlabel('Time [s]');
                ylabel('iPPG [a.u.]');
                title(sprintf('%s | %s | SpO2 = %.2f%%', subject_name, method_name, SpO2_mean));
                axis tight;

                out_name = sprintf('%s_%s_iPPG.fig', subject_name, method_name);
                saveas(fig, fullfile(subject_folder, out_name));
            catch
                % swallow plot/save errors per-method
            end
            close(fig);
        end

        % ---- Diagnostic: warn if no .fig files were saved ----
        saved_figs = dir(fullfile(subject_folder, '*.fig'));
        if isempty(saved_figs)
            warning('[iPPG_pipeline_v4] No .fig files saved for subject "%s". Check extraction or plot errors above.', subject_name);
        end

        % Save SpO2 summary (once per video)
        try
            fid = fopen(fullfile(subject_folder, subject_name + "_SpO2.txt"), 'w');
            fprintf(fid, 'Video: %s\nFs: %.3f\nSpO2_mean: %.3f\n', this_video, Fs, SpO2_mean);
            fclose(fid);
        catch
            % ignore
        end
    end
end

%% Post-processing (research mode only)
if ~doPopup
    fft_results = cycle_ippg_v2(plot_path, trace_folder, main_path);

    % Pick HR for this video (single-video use case)
    try
        if ~isempty(vid_direct) && numel(vid_direct) == 1 && ~isempty(fft_results)
            hr_bpm = local_pick_hr_bpm(fft_results, subjects_info{1});
        end
    catch
        hr_bpm = NaN;
    end
end

% Optional popup (quick mode)
if doPopup
    msgbox(sprintf('HR: %.1f bpm\nSpO2: %.1f%%', hr_bpm, spo2_pct), 'VitaSense Results');
end

end

% ================= Helper =================
function x = local_interpolate_nonfinite(x)
    if ~isfloat(x), x = double(x); end

    if isvector(x)
        bad = ~isfinite(x);
        if any(bad)
            good = find(isfinite(x));
            if ~isempty(good)
                x(bad) = interp1(good, x(good), find(bad), 'linear', 'extrap');
            else
                x(:) = 0;
            end
        end
    else
        for r = 1:size(x,1)
            xi = x(r,:);
            bad = ~isfinite(xi);
            if any(bad)
                good = find(isfinite(xi));
                if ~isempty(good)
                    xi(bad) = interp1(good, xi(good), find(bad), 'linear', 'extrap');
                else
                    xi(:) = 0;
                end
            end
            x(r,:) = xi;
        end
    end
end

function hr_bpm = local_pick_hr_bpm(results, subject_name)
% Deterministic selection:
% 1) Filter by subject_id match
% 2) Prefer methods in fixed order
% 3) Within a method, pick highest median peak ratio
% 4) Fallback: best overall by median peak ratio

hr_bpm = NaN;
if isempty(results)
    return;
end

sub = string(subject_name);

subject_ids = string({results.subject_id});
methods     = string({results.method});

ix = find(strcmpi(subject_ids, sub));
if isempty(ix)
    % If infer_subject_id differs, try substring match
    ix = find(contains(lower(subject_ids), lower(sub)));
end
if isempty(ix)
    return;
end

pref = ["POS","CHROM","ICA","AGRD","G_MINUS_R","GREEN"];

bestScore = -Inf;
bestHR    = NaN;

for pm = 1:numel(pref)
    m = pref(pm);
    im = ix(strcmpi(methods(ix), m));
    if isempty(im)
        continue;
    end

    for k = 1:numel(im)
        q = results(im(k)).window_peak_ratio;
        q = q(isfinite(q));
        if isempty(q)
            score = -Inf;
        else
            score = median(q);
        end

        if score > bestScore && isfinite(results(im(k)).dom_bpm)
            bestScore = score;
            bestHR    = results(im(k)).dom_bpm;
        end
    end

    if isfinite(bestHR)
        hr_bpm = bestHR;
        return;
    end
end

% Fallback: best overall among methods for this subject
for k = 1:numel(ix)
    q = results(ix(k)).window_peak_ratio;
    q = q(isfinite(q));
    if isempty(q)
        score = -Inf;
    else
        score = median(q);
    end

    if score > bestScore && isfinite(results(ix(k)).dom_bpm)
        bestScore = score;
        bestHR    = results(ix(k)).dom_bpm;
    end
end

hr_bpm = bestHR;
end

function hr_bpm = local_quick_hr(iPPG, fs)
%LOCAL_QUICK_HR  Windowed Welch PSD heart rate (same logic as
%   match_and_process_fft_v4 > local_windowed_hr_welch but without file I/O).
    y = double(iPPG(:));
    y = detrend(y, 'constant');
    y(~isfinite(y)) = 0;

    N = numel(y);
    fMin = 0.7;   fMax = 3.0;
    winSec = 10;  stepSec = 2;
    peakRatioThresh = 4;

    winN  = round(winSec * fs);
    stepN = round(stepSec * fs);

    if winN < 16 || N < 16
        hr_bpm = NaN;
        return;
    end

    nWin = max(1, floor((N - winN) / stepN) + 1);
    hrs = NaN(nWin, 1);
    wIdx = 0;

    for s = 1:stepN:(N - winN + 1)
        seg = y(s:s+winN-1);
        win = hann(winN);
        noverlap = round(0.5 * winN);
        nfft = max(256, 2^nextpow2(winN));

        [pxx, f] = pwelch(seg, win, noverlap, nfft, fs);

        band = (f >= fMin) & (f <= fMax);
        if ~any(band), continue; end

        fb = f(band);
        pb = pxx(band);

        [peakMag, idx] = max(pb);
        peakF = fb(idx);

        medMag = median(pb);
        if medMag <= 0, medMag = eps; end
        peakRatio = peakMag / medMag;

        if peakRatio < peakRatioThresh, continue; end

        % Harmonic check
        halfF = peakF / 2;
        if halfF >= fMin
            [~, hidx] = min(abs(fb - halfF));
            if pb(hidx) >= 0.5 * peakMag
                peakF = fb(hidx);
            end
        end

        hr = peakF * 60;
        if hr < fMin*60 || hr > fMax*60, continue; end

        wIdx = wIdx + 1;
        hrs(wIdx) = hr;
    end

    hrs = hrs(1:wIdx);
    if isempty(hrs)
        hr_bpm = NaN;
    else
        hr_bpm = median(hrs, 'omitnan');
    end
end