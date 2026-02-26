function GT = data_extraction(vhdr_path, out_dir, doPlots)
%DATA_EXTRACTION  Extract ECG heart rate ground truth from BrainVision VHDR.
%
%   GT = data_extraction(vhdr_path, out_dir, doPlots)
%
% Inputs:
%   vhdr_path (string/char): full path to .vhdr file
%   out_dir   (string/char): folder to save the ground-truth .mat
%   doPlots   (logical): true/false to plot ECG and detected peaks
%
% Output:
%   GT struct saved to disk and returned:
%     GT.subject_id
%     GT.source
%     GT.fs
%     GT.num_beats
%     GT.duration_sec
%     GT.R_locs
%     GT.R_times
%     GT.HR_inst_bpm
%     GT.HR_mean_bpm
%     GT.HR_count_bpm

    if nargin < 3
        doPlots = false;
    end

    % ---- Input normalization ----
    vhdr_path = string(vhdr_path);
    out_dir   = string(out_dir);

    if strlength(vhdr_path) == 0 || ~isfile(vhdr_path)
        error('VHDR path is empty or does not exist: %s', vhdr_path);
    end

    if strlength(out_dir) == 0
        error('Output directory is empty.');
    end

    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end

    % ---- Initialize EEGLAB (needed for plugins) ----
    eeglab; 

    % ---- Load BrainVision ----
    [pth, name, ext] = fileparts(vhdr_path);
    vhdr_file = name + ext;

    EEG = pop_loadbv(char(pth), char(vhdr_file));
    EEG = eeg_checkset(EEG);

    % ---- Identify ECG channel ----
    labels = {EEG.chanlocs.labels};
    ecg_idx = find(strcmpi(labels, 'ECG'), 1);

    if isempty(ecg_idx)
        error('ECG channel not found. Available channels: %s', strjoin(labels, ', '));
    end

    % ---- Extract ECG ----
    ecg = double(EEG.data(ecg_idx, :));
    fs  = EEG.srate;
    t   = (0:numel(ecg)-1) / fs;

    % ---- Preprocess for R-peak detection ----
    % R-peak emphasis band
    ecg_f  = bandpass(ecg, [5 20], fs);
    ecg_sq = ecg_f.^2;

    % ---- Peak detection ----
    minPeakDist = round(0.25 * fs);       % 250 ms refractory
    minPeakProm = 0.5 * std(ecg_sq);      % adaptive prominence threshold

    [~, locs] = findpeaks(ecg_sq, ...
        'MinPeakDistance', minPeakDist, ...
        'MinPeakProminence', minPeakProm);

    if numel(locs) < 2
        error('Not enough R-peaks detected to compute HR. Peaks found: %d', numel(locs));
    end

    % ---- HR computation ----
    R_times = locs / fs;                  % seconds
    RR = diff(R_times);                   % seconds
    HR_inst = 60 ./ RR;                   % bpm
    HR_mean = mean(HR_inst, 'omitnan');   % bpm

    % Simple count-based HR as sanity check
    duration_sec = numel(ecg) / fs;
    HR_count = (numel(locs) / duration_sec) * 60;

    % ---- Build GT struct ----
    subject_id = char(name);

    GT = struct();
    GT.subject_id    = subject_id;
    GT.source        = 'ActiCHamp ECG (BrainVision VHDR via EEGLAB pop_loadbv)';
    GT.fs            = fs;
    GT.num_beats     = numel(locs);
    GT.duration_sec  = duration_sec;
    GT.R_locs        = locs;
    GT.R_times       = R_times;
    GT.HR_inst_bpm   = HR_inst;
    GT.HR_mean_bpm   = HR_mean;
    GT.HR_count_bpm  = HR_count;

    % ---- Save ----
    gt_file = fullfile(out_dir, sprintf('%s_ECG_GT.mat', subject_id));
    save(gt_file, 'GT');

    fprintf('[GT] %s | HR_mean=%.2f bpm | countHR=%.2f bpm | beats=%d | saved: %s\n', ...
        GT.subject_id, GT.HR_mean_bpm, GT.HR_count_bpm, GT.num_beats, gt_file);

    % ---- Optional plots ----
    if doPlots
        figure('Color','w');

        % Raw ECG
        subplot(2,1,1)
        plot(t, ecg, 'k')
        xlabel('Time (s)')
        ylabel('ECG (uV)')
        title('Raw ECG')
        grid on

        % Detected peaks overlay (on raw ECG)
        subplot(2,1,2)
        plot(t, ecg, 'k'); hold on
        plot(R_times, ecg(locs), 'ro', 'MarkerSize', 4)
        xlabel('Time (s)')
        ylabel('ECG (uV)')
        title(sprintf('Detected R-peaks | HR_mean = %.2f bpm', HR_mean))
        grid on
    end

end
