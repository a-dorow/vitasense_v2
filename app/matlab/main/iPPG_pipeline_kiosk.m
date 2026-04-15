function [hr_bpm, spo2_pct, ippg_signal, Fs] = iPPG_pipeline_kiosk(video_path, plot_path, trace_folder, main_path)
% iPPG_pipeline_kiosk
% Streamlined CHROM-only pipeline for the VitaSense kiosk.
% Computes HR directly from Welch PSD — no batch FFT post-processing,
% no folder sorting, no struct2table, no .fig file I/O. Fast single-subject path only.
%
% Outputs:
%   hr_bpm      : heart rate in BPM (double)
%   spo2_pct    : SpO2 percentage (double)
%   ippg_signal : CHROM iPPG signal vector (double row vector) — for BP server
%   Fs          : sampling rate Hz (double) — for BP server

hr_bpm      = NaN;
spo2_pct    = NaN;
ippg_signal = [];
Fs          = 30;

if ~exist(plot_path,   'dir'), mkdir(plot_path);   end
if ~exist(trace_folder,'dir'), mkdir(trace_folder); end

%% 1. Configure
fprintf('VITASENSE_PROGRESS=Configuring pipeline...\n'); drawnow;

videoSettings = configure_video_settings();

try
    vr = VideoReader(video_path);
    Fs = vr.FrameRate;
    clear vr;
catch
    Fs = 30;
end

ippgSettings = configure_ippg_settings(Fs);
ippgSettings.extractionMethod = select_extraction_method('CHROM', ippgSettings);

%% 2. Extract RGB signal
fprintf('VITASENSE_PROGRESS=Extracting facial signal...\n'); drawnow;

rawColorSignal = extract_color_channels_from_video_KLT_v2(video_path, videoSettings);

if isempty(rawColorSignal) || numel(rawColorSignal) < 10
    warning('[kiosk] No color signal extracted.');
    return;
end

rawColorSignal = local_interpolate_nonfinite(rawColorSignal);

if size(rawColorSignal,2) == 3
    rawRGB = rawColorSignal.';
elseif size(rawColorSignal,1) == 3
    rawRGB = rawColorSignal;
else
    rawRGB = rawColorSignal.';
    if size(rawRGB,1) ~= 3, return; end
end

%% 3. SpO2
fprintf('VITASENSE_PROGRESS=Computing SpO2...\n'); drawnow;

SpO2_mean = NaN;
try
    redSig   = rawRGB(1,:).';
    greenSig = rawRGB(2,:).';
    winLenSec = 4; stepSec = 2;
    if length(redSig) >= winLenSec*Fs && length(greenSig) >= winLenSec*Fs
        [SpO2_uncalib, ~, ~, R_vals] = ippg_spo2_fft(redSig, greenSig, Fs, winLenSec, stepSec);
        if ~isempty(R_vals)
            R_vals = R_vals(isfinite(R_vals));
            if ~isempty(R_vals)
                R_mean = mean(R_vals);
                persistent spo2Cal;
                if isempty(spo2Cal)
                    if exist('spo2_calibration.mat','file')
                        S = load('spo2_calibration.mat');
                        if isfield(S,'p'), spo2Cal = S.p; end
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
spo2_pct = SpO2_mean;

%% 4. CHROM iPPG extraction
fprintf('VITASENSE_PROGRESS=Running CHROM extraction...\n'); drawnow;

try
    iPPG = compute_ippg(rawRGB, ippgSettings);
catch
    iPPG = rawRGB(2,:);  % GREEN fallback
end

% Expose signal for BP server — ensure row vector of doubles
ippg_signal = double(iPPG(:).');

%% 5. Compute HR directly via Welch PSD
fprintf('VITASENSE_PROGRESS=Computing heart rate...\n'); drawnow;

hr_bpm = local_welch_hr(iPPG, Fs);

fprintf('VITASENSE_PROGRESS=Finalising results...\n'); drawnow;
fprintf('VITASENSE_HR=%.6f\n',   hr_bpm);   drawnow;
fprintf('VITASENSE_SPO2=%.6f\n', spo2_pct); drawnow;

end


% ── Inline Welch HR (no file I/O, no struct2table) ───────────────────────────
function hr_bpm = local_welch_hr(signal, fs)
% Computes HR from iPPG signal using windowed Welch PSD.

    hr_bpm = NaN;

    fMin  = 0.7;   % 42 bpm
    fMax  = 3.0;   % 180 bpm
    winSec  = 10;
    stepSec = 2;
    peakRatioThresh = 4;

    y = double(signal(:));
    y = detrend(y, 'constant');
    y(~isfinite(y)) = 0;

    N     = numel(y);
    winN  = round(winSec * fs);
    stepN = round(stepSec * fs);

    if N < winN
        % Signal too short — use full signal
        winN = N;
    end

    if winN < 16
        return;
    end

    hrs = [];
    qs  = [];

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
                peakRatio = pb(hidx) / medMag;
            end
        end

        hr = peakF * 60;
        if hr < fMin*60 || hr > fMax*60, continue; end

        hrs(end+1,1) = hr;      
        qs(end+1,1)  = peakRatio; 
    end

    if ~isempty(hrs)
        hr_bpm = median(hrs, 'omitnan');
    end
end


% ── Helpers ──────────────────────────────────────────────────────────────────
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
            xi = x(r,:); bad = ~isfinite(xi);
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