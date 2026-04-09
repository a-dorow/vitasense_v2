%% aggregate_resolution_results.m
% Harvests HR and SpO2 results produced by run_resolution_pipeline.m across
% all three resolutions (480p, 360p, 240p), merges them with the ground
% truth spreadsheet, and writes a formatted master comparison .xlsx.
%
% Output sheets:
%   480p Results         — sorted by trial then subject; GT/iPPG HR + SpO2
%   360p Results         — same
%   240p Results         — same
%   Summary              — MAE, RMSE, Mean Error per resolution (HR + SpO2)
%   Per-Subject Summary  — per-subject stats averaged across trials
%
% Ground truth columns expected:
%   Subject Number | Distance (m) | Average O2 | Average Pulse Rate
%
% Distance -> trial mapping:
%   1.0 m  = trial_1
%   1.5 m  = trial_2
%   2.0 m  = trial_3
%
% Pipeline HR  : <dataset_root>\Resolutions\<res>\FFT_RESULTS\fft_results.csv
%   subject and trial parsed from source_fig column, e.g.:
%   subject_1_trial_2_240p_AGRD_iPPG.fig  ->  subject_1 / trial 2
% Pipeline SpO2: <dataset_root>\Resolutions\<res>\Plots\<trial_id>\*_SpO2.txt

clear; clc;

%% -------------------------------------------------------------------------
%  USER CONFIG
%% -------------------------------------------------------------------------
dataset_root = 'D:\Final Senior Desgn Data\finaldataset';
gt_file      = 'C:\Users\avask\Downloads\Final Dataset Ground Truths.xlsx';
output_file  = fullfile(dataset_root, 'Master_Resolution_Comparison.xlsx');
resolutions  = {'480p', '360p', '240p'};

% Distance (m) to trial number mapping — must match your recording protocol
dist_to_trial = containers.Map([1.0, 1.5, 2.0], [3, 2, 1]);

% Method preference order for best-HR selection
pref_methods = {'POS','CHROM','ICA','AGRD','G_MINUS_R','GREEN'};

%% -------------------------------------------------------------------------
%  LOAD GROUND TRUTH
%% -------------------------------------------------------------------------
fprintf('Loading ground truth from:\n  %s\n\n', gt_file);
gt = readtable(gt_file, 'Sheet', 'Summary Sheet', 'VariableNamingRule', 'preserve');

% Keep only the 4 meaningful columns; drop any trailing unnamed columns
gt = gt(:, {'Subject Number', 'Distance (m)', 'Average O2', 'Average Pulse Rate'});
gt.Properties.VariableNames = {'subject', 'distance_m', 'gt_spo2', 'gt_hr_bpm'};

% Add trial number column derived from distance
gt.trial = zeros(height(gt), 1);
for r = 1:height(gt)
    d = gt.distance_m(r);
    if isKey(dist_to_trial, d)
        gt.trial(r) = dist_to_trial(d);
    else
        warning('Unrecognised distance %.2f m for %s — trial set to 0.', d, gt.subject{r});
    end
end

%% -------------------------------------------------------------------------
%  DELETE OLD OUTPUT FILE SO STALE SHEETS DON'T PERSIST
%% -------------------------------------------------------------------------
if isfile(output_file)
    delete(output_file);
end

%% -------------------------------------------------------------------------
%  PROCESS EACH RESOLUTION — ONE SHEET PER RESOLUTION
%% -------------------------------------------------------------------------
summary_rows = {};
all_merged   = {};   % collect all resolutions for per-subject summary

for ri = 1:length(resolutions)
    res        = resolutions{ri};
    fft_csv    = fullfile(dataset_root, 'Resolutions', res, 'FFT_RESULTS', 'fft_results.csv');
    plots_root = fullfile(dataset_root, 'Resolutions', res, 'Plots');

    if ~isfile(fft_csv)
        warning('[%s] fft_results.csv not found — skipping.\n  Expected: %s', res, fft_csv);
        continue;
    end

    fprintf('Reading [%s] from:\n  %s\n', res, fft_csv);
    T = readtable(fft_csv, 'VariableNamingRule', 'preserve');
    T.Properties.VariableNames = lower(T.Properties.VariableNames);

    % Verify required columns
    req = {'source_fig', 'method', 'dom_bpm'};
    missing_cols = setdiff(req, T.Properties.VariableNames);
    if ~isempty(missing_cols)
        warning('[%s] fft_results.csv missing columns: %s — skipping.', ...
            res, strjoin(missing_cols, ', '));
        continue;
    end

    % Parse trial_id from source_fig for every row
    T.trial_id = extract_trial_id(T.source_fig);

    % Get unique trial IDs
    unique_ids = unique(T.trial_id);
    unique_ids = unique_ids(~cellfun(@isempty, unique_ids));

    % Build per-trial rows for this resolution
    res_rows = {};

    for ui = 1:length(unique_ids)
        trial_id = unique_ids{ui};   % e.g. "subject_1_trial_2_240p"

        subj_tok  = regexp(trial_id, '(subject_\d+)', 'tokens', 'once');
        trial_tok = regexp(trial_id, 'trial_(\d+)',   'tokens', 'once');

        if isempty(subj_tok) || isempty(trial_tok)
            warning('[%s] Cannot parse subject/trial from "%s" — skipping.', res, trial_id);
            continue;
        end

        subj_name = subj_tok{1};
        trial_num = str2double(trial_tok{1});

        % Pick best HR
        rows_for_id = T(strcmpi(T.trial_id, trial_id), :);
        hr_bpm = pick_best_hr(rows_for_id, pref_methods);

        % Read SpO2 from _SpO2.txt
        spo2_val = read_spo2_txt(plots_root, trial_id);

        res_rows(end+1, :) = {subj_name, trial_num, hr_bpm, spo2_val};
    end

    if isempty(res_rows)
        warning('[%s] No valid rows extracted — skipping sheet.', res);
        continue;
    end

    % Convert to table
    pipeline_res = cell2table(res_rows, ...
        'VariableNames', {'subject', 'trial', 'ippg_hr_bpm', 'ippg_spo2'});

    % Merge with ground truth on (subject, trial)
    merged = outerjoin(pipeline_res, gt(:, {'subject','trial','gt_hr_bpm','gt_spo2'}), ...
        'LeftKeys',  {'subject','trial'}, ...
        'RightKeys', {'subject','trial'}, ...
        'MergeKeys', true, ...
        'Type', 'left');

    % Compute error columns
    merged.hr_error_bpm   = merged.ippg_hr_bpm - merged.gt_hr_bpm;
    merged.hr_abs_error   = abs(merged.hr_error_bpm);
    merged.spo2_error     = merged.ippg_spo2   - merged.gt_spo2;
    merged.spo2_abs_error = abs(merged.spo2_error);

    % Sort by trial first, then subject number within each trial
    subj_num = regexp(merged.subject, '\d+', 'match');
    subj_num = cellfun(@(x) str2double(x{1}), subj_num);
    [~, sidx] = sortrows([merged.trial, subj_num]);
    merged = merged(sidx, :);

    % Clean column headers
    merged.Properties.VariableNames = { ...
        'Subject', 'Trial', ...
        'iPPG_HR_bpm',  'GT_HR_bpm',  'HR_Error_bpm',   'HR_Abs_Error_bpm', ...
        'iPPG_SpO2',    'GT_SpO2',    'SpO2_Error',      'SpO2_Abs_Error'};

    % Reorder so GT columns sit next to iPPG columns
    merged = merged(:, {'Subject','Trial', ...
        'GT_HR_bpm','iPPG_HR_bpm','HR_Error_bpm','HR_Abs_Error_bpm', ...
        'GT_SpO2',  'iPPG_SpO2', 'SpO2_Error',  'SpO2_Abs_Error'});

    % Write sheet
    sheet_name = [res ' Results'];
    writetable(merged, output_file, 'Sheet', sheet_name);
    fprintf('  -> Written sheet: "%s" (%d rows)\n', sheet_name, height(merged));

    % Accumulate summary stats
    valid_hr_abs   = merged.HR_Abs_Error_bpm(isfinite(merged.HR_Abs_Error_bpm));
    valid_hr_err   = merged.HR_Error_bpm(isfinite(merged.HR_Error_bpm));
    valid_spo2_abs = merged.SpO2_Abs_Error(isfinite(merged.SpO2_Abs_Error));
    valid_spo2_err = merged.SpO2_Error(isfinite(merged.SpO2_Error));
    n              = height(merged);

    hr_mae    = mean(valid_hr_abs,           'omitnan');
    hr_rmse   = sqrt(mean(valid_hr_abs.^2,   'omitnan'));
    hr_bias   = mean(valid_hr_err,           'omitnan');
    spo2_mae  = mean(valid_spo2_abs,         'omitnan');
    spo2_rmse = sqrt(mean(valid_spo2_abs.^2, 'omitnan'));
    spo2_bias = mean(valid_spo2_err,         'omitnan');

    summary_rows(end+1, :) = {res, n, ...
        hr_mae, hr_rmse, hr_bias, ...
        spo2_mae, spo2_rmse, spo2_bias}; 

    % Store for per-subject summary
    merged.Resolution = repmat({res}, height(merged), 1);
    all_merged{end+1} = merged;
end

%% -------------------------------------------------------------------------
%  SUMMARY SHEET
%% -------------------------------------------------------------------------
if ~isempty(summary_rows)
    summary = cell2table(summary_rows, 'VariableNames', ...
        {'Resolution', 'N_Trials', ...
         'HR_MAE_bpm',   'HR_RMSE_bpm',   'HR_Mean_Error_bpm', ...
         'SpO2_MAE',     'SpO2_RMSE',     'SpO2_Mean_Error'});
    writetable(summary, output_file, 'Sheet', 'Summary');
    fprintf('\n  -> Written sheet: "Summary"\n');
end

%% -------------------------------------------------------------------------
%  PER-SUBJECT SUMMARY SHEET
%% -------------------------------------------------------------------------
if ~isempty(all_merged)
    combined = vertcat(all_merged{:});

    all_subjects = unique(combined.Subject);
    subj_nums    = regexp(all_subjects, '\d+', 'match');
    subj_nums    = cellfun(@(x) str2double(x{1}), subj_nums);
    [~, sorder]  = sort(subj_nums);
    all_subjects = all_subjects(sorder);

    ps_rows = {};

    for si = 1:length(all_subjects)
        subj = all_subjects{si};

        for ri = 1:length(resolutions)
            res  = resolutions{ri};
            mask = strcmpi(combined.Subject, subj) & strcmpi(combined.Resolution, res);
            rows = combined(mask, :);

            if isempty(rows)
                ps_rows(end+1, :) = {subj, res, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN}; 
                continue;
            end

            mean_gt_hr   = mean(rows.GT_HR_bpm(isfinite(rows.GT_HR_bpm)),   'omitnan');
            mean_ippg_hr = mean(rows.iPPG_HR_bpm(isfinite(rows.iPPG_HR_bpm)),'omitnan');
            hr_mae       = mean(rows.HR_Abs_Error_bpm(isfinite(rows.HR_Abs_Error_bpm)), 'omitnan');
            hr_rmse      = sqrt(mean(rows.HR_Abs_Error_bpm(isfinite(rows.HR_Abs_Error_bpm)).^2, 'omitnan'));
            hr_bias      = mean(rows.HR_Error_bpm(isfinite(rows.HR_Error_bpm)), 'omitnan');

            mean_gt_spo2   = mean(rows.GT_SpO2(isfinite(rows.GT_SpO2)),   'omitnan');
            mean_ippg_spo2 = mean(rows.iPPG_SpO2(isfinite(rows.iPPG_SpO2)),'omitnan');
            spo2_mae       = mean(rows.SpO2_Abs_Error(isfinite(rows.SpO2_Abs_Error)), 'omitnan');
            spo2_bias      = mean(rows.SpO2_Error(isfinite(rows.SpO2_Error)), 'omitnan');

            ps_rows(end+1, :) = {subj, res, ...
                mean_gt_hr, mean_ippg_hr, hr_mae, hr_rmse, hr_bias, ...
                mean_gt_spo2, mean_ippg_spo2, spo2_mae, spo2_bias}; 
        end
    end

    per_subj = cell2table(ps_rows, 'VariableNames', ...
        {'Subject', 'Resolution', ...
         'Mean_GT_HR_bpm',   'Mean_iPPG_HR_bpm',  'HR_MAE_bpm', 'HR_RMSE_bpm', 'HR_Mean_Error_bpm', ...
         'Mean_GT_SpO2',     'Mean_iPPG_SpO2',    'SpO2_MAE',   'SpO2_Mean_Error'});

    writetable(per_subj, output_file, 'Sheet', 'Per-Subject Summary');
    fprintf('  -> Written sheet: "Per-Subject Summary"\n');
end

fprintf('\n[DONE] Master sheet written to:\n  %s\n', output_file);

%% =========================================================================
%  LOCAL HELPERS
%% =========================================================================

function ids = extract_trial_id(source_figs)
% Parse the base trial ID from each source_fig filename.
% e.g. "subject_1_trial_2_240p_AGRD_iPPG.fig" -> "subject_1_trial_2_240p"
    if ischar(source_figs) || isstring(source_figs)
        source_figs = cellstr(source_figs);
    end
    ids = cell(size(source_figs));
    for k = 1:numel(source_figs)
        [~, base, ~] = fileparts(source_figs{k});
        % Match subject_N_trial_N_<res>p  (e.g. 240p / 360p / 480p)
        tok = regexp(base, '^(subject_\d+_trial_\d+_\d+p)', 'tokens', 'once');
        if ~isempty(tok)
            ids{k} = tok{1};
        else
            % Fallback: everything before the first ALL-CAPS method token
            tok2 = regexp(base, '^(.*?)_[A-Z]', 'tokens', 'once');
            if ~isempty(tok2)
                ids{k} = strtrim(tok2{1});
            else
                ids{k} = '';
            end
        end
    end
end

function hr = pick_best_hr(rows, pref_methods)
% Iterate preferred methods in order; pick the one with the highest
% median window_peak_ratio that also has a finite dom_bpm.
    hr = NaN;
    best_score = -Inf;

    for pm = 1:numel(pref_methods)
        m   = pref_methods{pm};
        idx = strcmpi(rows.method, m);
        if ~any(idx), continue; end
        candidates = rows(idx, :);

        for k = 1:height(candidates)
            if ismember('window_peak_ratio', candidates.Properties.VariableNames)
                q = parse_peak_ratio(candidates.window_peak_ratio(k));
                q = q(isfinite(q));
            else
                q = [];
            end
            score = -Inf;
            if ~isempty(q), score = median(q); end

            if score > best_score && isfinite(candidates.dom_bpm(k))
                best_score = score;
                hr = candidates.dom_bpm(k);
            end
        end

        if isfinite(hr), return; end
    end

    % Fallback: first finite dom_bpm regardless of method
    for k = 1:height(rows)
        if isfinite(rows.dom_bpm(k))
            hr = rows.dom_bpm(k);
            return;
        end
    end
end

function q = parse_peak_ratio(val)
% Parse window_peak_ratio which writetable may store as a string.
    if isnumeric(val)
        q = double(val);
        return;
    end
    if iscell(val), val = val{1}; end
    if ischar(val) || isstring(val)
        val  = strtrim(char(val));
        val  = regexprep(val, '[\[\]]', '');
        nums = str2num(val); %#ok<ST2NM>
        q    = nums;
        if isempty(q), q = NaN; end
    else
        q = NaN;
    end
end

function spo2 = read_spo2_txt(plots_root, trial_id)
% Read the SpO2_mean value from the _SpO2.txt file written by
% iPPG_pipeline_v4 for this trial.
% File lives at: plots_root\<trial_id>\<trial_id>_SpO2.txt
    spo2 = NaN;
    txt_path = fullfile(plots_root, trial_id, [trial_id '_SpO2.txt']);
    if ~isfile(txt_path), return; end
    try
        txt = fileread(txt_path);
        tok = regexp(txt, 'SpO2_mean:\s*([\d.]+)', 'tokens', 'once');
        if ~isempty(tok)
            spo2 = str2double(tok{1});
        end
    catch
        % leave as NaN
    end
end