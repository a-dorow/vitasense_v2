function results = match_and_process_fft_v4(extraction_root, trace_folder, master_root)
%MATCH_AND_PROCESS_FFT_V3
% Post-process saved iPPG .fig files (time-domain) by computing WINDOWED
% Welch-PSD HR estimates and saving FFT/PSD plots + a summary table.
%
% Dominant HR is computed as the MEDIAN of per-window HR estimates.
%
% Defaults:
%   HR band: 0.7–3.0 Hz (42–180 bpm)
%   Window:  10 s
%   Step:    2 s
%   Peak quality gate: peakRatio >= 4
%   Harmonic check: if 2x HR suspected, use half-frequency

    if nargin < 2
        error('Usage: match_and_process_fft_v3(extraction_root, trace_folder, master_root)');
    end
    if nargin < 3
        master_root = pwd;
    end

    if ~exist(extraction_root, 'dir')
        error('Extraction root does not exist: %s', extraction_root);
    end
    if ~exist(trace_folder, 'dir')
        mkdir(trace_folder);
    end

    % -------- Defaults you asked for --------
    cfg = struct();
    cfg.fMin = 0.7;              % Hz  (42 bpm)
    cfg.fMax = 3.0;              % Hz  (180 bpm)
    cfg.winSec = 10;             % seconds
    cfg.stepSec = 2;             % seconds
    cfg.peakRatioThresh = 4;     % tune 3–6 if needed
    cfg.harmonicCheck = true;
    % ---------------------------------------

    % Method subfolders
    d = dir(extraction_root);
    d = d([d.isdir]);
    d = d(~ismember({d.name}, {'.','..'}));

    if isempty(d)
        warning('No method subfolders found in %s', extraction_root);
        results = struct([]);
        return;
    end

    results = struct([]);
    r = 1;

    for m = 1:numel(d)
        method = d(m).name;
        method_folder = fullfile(extraction_root, method);
        fig_files = dir(fullfile(method_folder, '*.fig'));
        if isempty(fig_files)
            continue;
        end

        method_out = fullfile(trace_folder, method);
        if ~exist(method_out, 'dir'); mkdir(method_out); end

        for k = 1:numel(fig_files)
            fig_name = fig_files(k).name;
            fig_path = fullfile(method_folder, fig_name);

            subject_id = infer_subject_id(fig_name);

            % --- Open and extract time series from .fig ---
            try
                h = openfig(fig_path, 'invisible');
            catch
                warning('Could not open figure: %s', fig_path);
                continue;
            end

            ax = findall(h, 'type', 'axes');
            ln = findall(ax, 'type', 'line');
            if isempty(ln)
                close(h);
                warning('No line objects found in: %s', fig_name);
                continue;
            end

            x = get(ln(1), 'XData');
            y = get(ln(1), 'YData');
            close(h);

            if isempty(x) || isempty(y)
                warning('Empty XData/YData in: %s', fig_name);
                continue;
            end

            x = double(x(:));
            y = double(y(:));

            % --- Infer sampling rate from XData ---
            dx = diff(x);
            dx = dx(isfinite(dx) & dx > 0);
            if numel(dx) < 5
                warning('Cannot infer sampling rate from XData for: %s', fig_name);
                continue;
            end
            fs = 1 / median(dx);

            % --- Windowed HR via Welch PSD ---
            [hr_med_bpm, hr_windows_bpm, q_windows] = local_windowed_hr_welch(y, fs, cfg);

            dom_bpm = hr_med_bpm;
            dom_freq = dom_bpm / 60;

            % --- Save PSD figure for THIS FILE (full-signal PSD + mark HR) ---
            fft_fig = figure('Visible','off');
            try
                y0 = detrend(double(y(:)), 'constant');
                y0(~isfinite(y0)) = 0;

                % full-signal Welch (for display only)
                winN = min(numel(y0), max(256, round(cfg.winSec*fs)));
                winN = max(winN, 16);
                win = hann(winN);
                noverlap = round(0.5*winN);
                nfft = max(256, 2^nextpow2(winN));
                [pxx, f] = pwelch(y0, win, noverlap, nfft, fs);

                plot(f, pxx, 'LineWidth', 1);
                grid on;
                xlabel('Frequency (Hz)');
                ylabel('PSD (a.u.)');
                xlim([0 6]);

                if isfinite(dom_freq)
                    hold on;
                    yl = ylim;
                    plot([dom_freq dom_freq], yl, '--', 'LineWidth', 1);
                    hold off;
                end

                title(sprintf('%s | %s | HR median = %.1f bpm (%d windows)', ...
                    subject_id, method, dom_bpm, numel(hr_windows_bpm)));

                out_name = sprintf('%s_%s_PSD.fig', subject_id, method);
                saveas(fft_fig, fullfile(method_out, out_name));

                % OPTIONAL: save window HR trace as .mat for debugging
                dbg_name = sprintf('%s_%s_windowHR.mat', subject_id, method);
                save(fullfile(method_out, dbg_name), 'hr_windows_bpm', 'q_windows', 'cfg', 'fs');

            catch ME
                warning('Failed to save PSD fig for %s: %s', fig_name, ME.message);
            end
            close(fft_fig);

            % --- Record result ---
            results(r).subject_id         = subject_id;
            results(r).method             = method;
            results(r).source_fig         = fig_name;
            results(r).fs_hz              = fs;
            results(r).dom_freq_hz        = dom_freq;
            results(r).dom_bpm            = dom_bpm;
            results(r).window_hr_bpm      = hr_windows_bpm;
            results(r).window_peak_ratio  = q_windows;
            r = r + 1;
        end
    end

    if isempty(results)
        warning('No FFT results produced. Check that extraction_root contains .fig files.');
        return;
    end

    % Save summary
    T = struct2table(results);

    summary_dir = fullfile(trace_folder, 'FFT_RESULTS');
    if ~exist(summary_dir,'dir'); mkdir(summary_dir); end

    mat_file = fullfile(summary_dir, 'fft_results.mat');
    csv_file = fullfile(summary_dir, 'fft_results.csv');
    save(mat_file, 'results');
    writetable(T, csv_file);

    % Copy to master_root
    try
        if ~strcmpi(string(master_root), string(trace_folder))
            master_dir = fullfile(master_root, 'FFT_RESULTS');
            if ~exist(master_dir,'dir'); mkdir(master_dir); end
            save(fullfile(master_dir, 'fft_results.mat'), 'results');
            writetable(T, fullfile(master_dir, 'fft_results.csv'));
        end
    catch
        % ignore
    end

    fprintf('[FFT] Saved summary: %s\n', summary_dir);
end

% ==========================================================
% Windowed HR helper (Welch PSD + band + quality + harmonic)
% ==========================================================
function [hr_med_bpm, hr_windows_bpm, q_windows] = local_windowed_hr_welch(y, fs, cfg)

    y = double(y(:));
    y = detrend(y, 'constant');
    y(~isfinite(y)) = 0;

    N = numel(y);
    winN  = round(cfg.winSec * fs);
    stepN = round(cfg.stepSec * fs);

    if winN < round(4*fs)
        % If your clip is super short, it will be shaky; still try
        winN = min(N, winN);
    end
    if winN < 16 || N < 16
        hr_med_bpm = NaN;
        hr_windows_bpm = [];
        q_windows = [];
        return;
    end

    hrs = [];
    qs  = [];

    for s = 1:stepN:(N - winN + 1)
        seg = y(s:s+winN-1);

        % Welch on the window (using the window itself)
        win = hann(winN);
        noverlap = round(0.5*winN);
        nfft = max(256, 2^nextpow2(winN));

        [pxx, f] = pwelch(seg, win, noverlap, nfft, fs);

        band = (f >= cfg.fMin) & (f <= cfg.fMax);
        if ~any(band)
            continue;
        end

        fb = f(band);
        pb = pxx(band);

        [peakMag, idx] = max(pb);
        peakF = fb(idx);

        medMag = median(pb);
        if medMag <= 0, medMag = eps; end
        peakRatio = peakMag / medMag;

        % Quality gate
        if peakRatio < cfg.peakRatioThresh
            continue;
        end

        % Harmonic check (2x HR)
        if cfg.harmonicCheck
            halfF = peakF/2;
            if halfF >= cfg.fMin
                [~, hidx] = min(abs(fb - halfF));
                halfMag = pb(hidx);
                if halfMag >= 0.5 * peakMag
                    peakF = fb(hidx);
                    peakRatio = halfMag / medMag;
                end
            end
        end

        hr = peakF * 60;

        % Safety clamp (not your main defense; just a last guardrail)
        if hr < cfg.fMin*60 || hr > cfg.fMax*60
            continue;
        end

        hrs(end+1,1) = hr; 
        qs(end+1,1)  = peakRatio; 
    end

    hr_windows_bpm = hrs;
    q_windows = qs;

    if isempty(hrs)
        hr_med_bpm = NaN;
    else
        hr_med_bpm = median(hrs, 'omitnan');
    end
end

function subject_id = infer_subject_id(fname)
% Heuristic subject ID extraction for subject-first naming.
% 1) Subject\d+
% 2) prefix before first underscore
% 3) filename without extension
    tok = regexp(fname, '(Subject\\d+)', 'tokens', 'once');
    if ~isempty(tok)
        subject_id = tok{1};
        return;
    end
    [~, base, ~] = fileparts(fname);
    parts = split(string(base), '_');
    if numel(parts) >= 1 && strlength(parts(1)) > 0
        subject_id = char(parts(1));
    else
        subject_id = char(base);
    end
end
