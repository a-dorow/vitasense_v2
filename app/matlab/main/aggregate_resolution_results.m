%% aggregate_resolution_results.m
% Loads fft_results.mat files produced by your pipeline after running
% run_resolution_pipeline.m, then computes MAE per resolution per method


clear; clc;

%% -------------------------------------------------------------------------
%  CONFIGURATION — edit these
%% -------------------------------------------------------------------------

dataset_root = 'D:\Final Senior Desgn Data\finaldataset';

resolutions  = {'480p', '360p', '240p'};

% Methods as they appear in results(i).method (cycle_ippg_v2 subfolder names)
methods       = {'CHROM', 'POS', 'ICA', 'AGRD', 'G_MINUS_R', 'GREEN'};
method_labels = {'CHROM', 'POS', 'ICA', 'AGRD', 'G-R',       'Green'};

% Ground truth HR per subject per trial [BPM]
% Rows = subjects 1..11, Cols = trials 1..3
% *** Fill in your actual GT values — these are pulled from your spreadsheets ***
ground_truth = struct();
ground_truth.subject_1  = [72, 68, 71];   % [trial1, trial2, trial3]
ground_truth.subject_2  = [79, 75, 77];
ground_truth.subject_3  = [60, 59, 66];
ground_truth.subject_4  = [86, 84, 87];
ground_truth.subject_5  = [87, 84, 78];
ground_truth.subject_6  = [90, 90, 90];
ground_truth.subject_7  = [82, 90, 86];
ground_truth.subject_8  = [72, 75, 72];
ground_truth.subject_9  = [66, 71, 70];
ground_truth.subject_10 = [57, 60, 58];
ground_truth.subject_11 = [87, 90, 90];

%% -------------------------------------------------------------------------
%  LOAD RESULTS
%  For each resolution, load fft_results.mat and match each result entry
%  to its ground truth using subject number + trial number parsed from
%  subject_id (e.g. 'subject_1_trial_2_480p' -> subject_1, trial 2)
%% -------------------------------------------------------------------------

n_r = length(resolutions);
n_m = length(methods);

% mae_table(resolution, method) — averaged across all subjects/trials
mae_table = nan(n_r, n_m);

% Also store per-subject-trial details for the CSV
all_rows = {};

for r = 1:n_r

    res_label = resolutions{r};
    mat_path  = fullfile(dataset_root, 'Resolutions', res_label, ...
                         'Traces', 'FFT_RESULTS', 'fft_results.mat');

    if ~exist(mat_path, 'file')
        fprintf('[MISSING] %s — %s\n', res_label, mat_path);
        continue;
    end

    S = load(mat_path, 'results');
    if ~isfield(S, 'results') || isempty(S.results)
        fprintf('[EMPTY]   %s\n', res_label);
        continue;
    end

    results = S.results;
    fprintf('[OK] %s — %d entries\n', res_label, numel(results));

    for m = 1:n_m

        method_str = methods{m};
        diffs_all  = [];

        % Filter to this method
        method_mask = strcmpi({results.method}, method_str);
        method_results = results(method_mask);

        for k = 1:numel(method_results)

            sid = method_results(k).subject_id;   % e.g. subject_1_trial_2_480p

            % Parse subject number and trial number from subject_id
            subj_tok  = regexp(sid, 'subject_?(\d+)', 'tokens', 'once');
            trial_tok = regexp(sid, 'trial_?(\d+)',   'tokens', 'once');

            if isempty(subj_tok) || isempty(trial_tok)
                continue;
            end

            subj_num  = str2double(subj_tok{1});
            trial_num = str2double(trial_tok{1});

            % Look up ground truth
            gt_field = sprintf('subject_%d', subj_num);
            if ~isfield(ground_truth, gt_field)
                continue;
            end

            gt_vals = ground_truth.(gt_field);
            if trial_num > length(gt_vals)
                continue;
            end

            gt_hr  = gt_vals(trial_num);
            est_hr = method_results(k).dom_bpm;

            if ~isfinite(est_hr)
                continue;
            end

            diff = abs(est_hr - gt_hr);
            diffs_all(end+1) = diff; %#ok<AGROW>

            % Store for CSV
            all_rows{end+1, 1} = res_label;
            all_rows{end,   2} = method_labels{m};
            all_rows{end,   3} = sprintf('subject_%d', subj_num);
            all_rows{end,   4} = trial_num;
            all_rows{end,   5} = gt_hr;
            all_rows{end,   6} = est_hr;
            all_rows{end,   7} = diff;
        end

        if ~isempty(diffs_all)
            mae_table(r, m) = mean(diffs_all);
        end
    end
end

%% -------------------------------------------------------------------------
%  PRINT SUMMARY TABLE
%% -------------------------------------------------------------------------

fprintf('\n\n========================================\n');
fprintf('MAE Summary (BPM) — Resolution vs Method\n');
fprintf('========================================\n');
fprintf('%-10s', 'Method');
for r = 1:n_r
    fprintf('%-10s', resolutions{r});
end
fprintf('\n%s\n', repmat('-', 1, 10 + 10*n_r));

for m = 1:n_m
    fprintf('%-10s', method_labels{m});
    for r = 1:n_r
        v = mae_table(r, m);
        if isnan(v)
            fprintf('%-10s', 'N/A');
        else
            fprintf('%-10.2f', v);
        end
    end
    fprintf('\n');
end

%% -------------------------------------------------------------------------
%  SAVE CSV
%% -------------------------------------------------------------------------

if ~isempty(all_rows)
    T_detail = cell2table(all_rows, 'VariableNames', ...
        {'Resolution','Method','Subject','Trial','GT_HR','Est_HR','AbsDiff'});
    csv_out = fullfile(dataset_root, 'Resolutions', 'resolution_results_detail.csv');
    writetable(T_detail, csv_out);
    fprintf('\nDetailed results saved: %s\n', csv_out);
end

T_mae = array2table(mae_table, ...
    'RowNames',    resolutions, ...
    'VariableNames', method_labels);
csv_mae = fullfile(dataset_root, 'Resolutions', 'resolution_MAE_summary.csv');
writetable(T_mae, csv_mae, 'WriteRowNames', true);
fprintf('MAE summary saved:      %s\n', csv_mae);

%% -------------------------------------------------------------------------
%  PLOT — MAE vs Resolution per method
%% -------------------------------------------------------------------------

colors = lines(n_m);

figure('Name', 'MAE vs Resolution', 'NumberTitle', 'off', ...
       'Position', [100 100 850 480]);
hold on;

for m = 1:n_m
    plot(1:n_r, mae_table(:, m), '-o', ...
        'Color',       colors(m, :), ...
        'LineWidth',   2, ...
        'MarkerSize',  7, ...
        'DisplayName', method_labels{m});
end

set(gca, 'XTick', 1:n_r, 'XTickLabel', resolutions, 'FontSize', 11);
xlabel('Resolution', 'FontSize', 12);
ylabel('MAE (BPM)',  'FontSize', 12);
title('MAE vs Resolution by Extraction Method', 'FontSize', 13);
legend('Location', 'best', 'FontSize', 10);
grid on;
hold off;

fig_out = fullfile(dataset_root, 'Resolutions', 'MAE_vs_Resolution.png');
saveas(gcf, fig_out);
fprintf('Plot saved:             %s\n', fig_out);

fprintf('\nDone.\n');