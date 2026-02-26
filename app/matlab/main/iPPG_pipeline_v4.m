%function [] = iPPG_pipeline_v4(video_path, plot_path, trace_folder, main_path)
function [hr_bpm, spo2_pct] = iPPG_pipeline_v4(video_path, plot_path, trace_folder, main_path, doPopup)
% iPPG_pipeline_v4 (VIDEO-ONLY)
% Fully automated iPPG extraction + plotting + FFT post-processing.
% - Cycles through ALL extraction methods (same as original v3)
% - Computes SpO2 ONCE per video (sliding window, RED/GREEN)
% - Uses extract_color_channels_from_video_KLT_rect for RGB extraction
% - NO BrainVision / NO ground truth

setup_paths();

if nargin < 5
    doPopup = false;
end
doPopup = logical(doPopup);

hr_bpm  = NaN;
spo2_pct = NaN;
% Ensure output folder exists
if ~exist(plot_path,'dir'); mkdir(plot_path); end

%% Configure settings
videoSettings = configure_video_settings();
plotSettings  = configure_plot_settings();

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

    subject_folder = create_sub_folder(plot_path, subject_name);

    % ---- True FPS per video (important for SpO2 + filters) ----
    Fs = VIDEO_SR;
    try
        vr = VideoReader(this_video);
        Fs = vr.FrameRate;
        clear vr;
    catch
        % fallback
    end

    ippgSettings = configure_ippg_settings(Fs);

    % ---- Extract RGB (KLT rect) ----
    rawColorSignal = extract_color_channels_from_video_KLT_v2(this_video, videoSettings);

    if isempty(rawColorSignal) || numel(rawColorSignal) < 10
        continue;
    end

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

    % Save SpO2 summary (once per video)
    try
        fid = fopen(fullfile(subject_folder, subject_name + "_SpO2.txt"), 'w');
        fprintf(fid, 'Video: %s\nFs: %.3f\nSpO2_mean: %.3f\n', this_video, Fs, SpO2_mean);
        fclose(fid);
    catch
        % ignore
    end
end

%% Post-processing FFT sorting (unchanged)
%cycle_ippg_v2(plot_path, trace_folder, main_path);

fft_results = cycle_ippg_v2(plot_path, trace_folder, main_path);

% Pick HR for this video (single-video use case)
try
    if ~isempty(vid_direct) && numel(vid_direct) == 1 && ~isempty(fft_results)
        hr_bpm = local_pick_hr_bpm(fft_results, subjects_info{1});
    end
catch
    hr_bpm = NaN;
end

% Optional popup (quick mode)
if doPopup && isfinite(hr_bpm) && isfinite(spo2_pct)
    msgbox(sprintf('HR: %.1f bpm\nSpO2: %.1f%%', hr_bpm, spo2_pct), 'VitaSense Results');
elseif doPopup
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