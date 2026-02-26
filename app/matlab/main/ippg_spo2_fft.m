function [SpO2_mean, SpO2_win, t_win, R_vals] = ippg_spo2_fft(redSig, irSig, fs, winLenSec, stepSec)
%IPPB_SPO2_FFT  Estimate SpO2 from RED / IR-like iPPG signals using FFT.
%
%   [SpO2_mean, SpO2_win, t_win, R_vals] = ippg_spo2_fft(redSig, irSig, fs, winLenSec, stepSec)
%
%   redSig    : RED-like iPPG signal (vector)
%   irSig     : IR- or green-like iPPG signal (vector)
%   fs        : sampling rate [Hz]
%   winLenSec : window length in seconds (e.g., 4 or 8)
%   stepSec   : step between windows in seconds (e.g., 2 or 4)
%
%   SpO2_mean : average SpO2 across windows (uncalibrated)
%   SpO2_win  : SpO2 per window (uncalibrated)
%   t_win     : time (center of each window) [s]
%   R_vals    : ratio-of-ratios R per window (useful for calibration)

    % Ensure column vectors
    redSig = redSig(:);
    irSig  = irSig(:);

    % Match lengths
    N = min(length(redSig), length(irSig));
    redSig = redSig(1:N);
    irSig  = irSig(1:N);

    % Window params
    winLen = round(winLenSec * fs);
    if nargin < 5 || isempty(stepSec)
        step = winLen;   % non-overlapping if not given
    else
        step = round(stepSec * fs);
    end

    % Reasonable HR band (Hz)
    fMin = 0.7;   % ~42 bpm
    fMax = 3.0;   % ~180 bpm

    SpO2_win = [];
    t_win    = [];
    R_vals   = [];

    idx = 1;
    while (idx + winLen - 1) <= N
        % Raw segment (for DC)
        segR_raw  = redSig(idx:idx+winLen-1);
        segIR_raw = irSig(idx:idx+winLen-1);

        % Skip segments that are all zeros / constant / NaN
        if any(~isfinite(segR_raw)) || any(~isfinite(segIR_raw)) || ...
           std(segR_raw) == 0 || std(segIR_raw) == 0
            SpO2_win(end+1) = NaN; %#ok<AGROW>
            t_win(end+1)    = (idx + winLen/2 - 1) / fs; %#ok<AGROW>
            R_vals(end+1)   = NaN; %#ok<AGROW>
            idx = idx + step;
            continue;
        end

        % Detrended version for AC / spectral peak
        segR  = detrend(segR_raw);
        segIR = detrend(segIR_raw);

        % FFT
        NFFT = 2^nextpow2(winLen);
        YR   = fft(segR,  NFFT);
        YIR  = fft(segIR, NFFT);

        f = (0:NFFT-1)' * (fs / NFFT);
        posIdx = f <= fs/2;
        f   = f(posIdx);
        YR  = YR(posIdx);
        YIR = YIR(posIdx);

        % Limit to HR band
        bandIdx = (f >= fMin) & (f <= fMax);

        if ~any(bandIdx)
            SpO2_win(end+1) = NaN; %#ok<AGROW>
            t_win(end+1)    = (idx + winLen/2 - 1) / fs; %#ok<AGROW>
            R_vals(end+1)   = NaN; %#ok<AGROW>
            idx = idx + step;
            continue;
        end

        fBand    = f(bandIdx);
        YR_band  = abs(YR(bandIdx));
        YIR_band = abs(YIR(bandIdx));

        % Peak frequency from "IR" channel
        [~, maxIdxIR] = max(YIR_band);
        f_peak = fBand(maxIdxIR);

        % Find closest bins to f_peak
        [~, pkIdxR]  = min(abs(f - f_peak));
        [~, pkIdxIR] = min(abs(f - f_peak));

        AC_red = abs(YR(pkIdxR));
        AC_ir  = abs(YIR(pkIdxIR));

        % DC from raw (non-detrended) segments
        DC_red = mean(segR_raw);
        DC_ir  = mean(segIR_raw);

        if DC_red == 0 || DC_ir == 0 || ~isfinite(DC_red) || ~isfinite(DC_ir)
            SpO2_win(end+1) = NaN; %#ok<AGROW>
            t_win(end+1)    = (idx + winLen/2 - 1) / fs; %#ok<AGROW>
            R_vals(end+1)   = NaN; %#ok<AGROW>
            idx = idx + step;
            continue;
        end

        R_RED = AC_red / DC_red;
        R_IR  = AC_ir  / DC_ir;
        R     = R_RED / R_IR;

        % Store R for later calibration
        R_vals(end+1) = R; %#ok<AGROW>

        % TEMPORARY calibration (from Thinh's example) – replace with your own later
      % example: subject had true SpO2_true = 97 at R_mean
SpO2_true = 97;       % measured from reference pulse ox
R_mean    = mean(R_vals(isfinite(R_vals)));  % from that run

A = SpO2_true + 28 * R_mean;
SpO2_est = A - 28 * R;

        SpO2_win(end+1) = SpO2_est; %#ok<AGROW>

        % Center time of this window
        t_win(end+1) = (idx + winLen/2 - 1) / fs; %#ok<AGROW>

        idx = idx + step;
    end

    % Final mean, ignoring NaNs
    valid = isfinite(SpO2_win);
    if any(valid)
        SpO2_mean = mean(SpO2_win(valid));
    else
        SpO2_mean = NaN;
    end
end
