function [hr_bpm, spo2_pct, ippg_signal, Fs] = run_pipeline_kiosk(video_path, varargin)
% run_pipeline_kiosk
% Wrapper for iPPG_pipeline_kiosk — called by vitasense_server matlab_runner.py
%
% Outputs:
%   hr_bpm      : heart rate BPM
%   spo2_pct    : SpO2 percentage
%   ippg_signal : CHROM iPPG signal vector (row) — passed to BP server
%   Fs          : sampling rate Hz — passed to BP server
%
% Optional args (name/value):
%   'writeJson' (logical) default false
%   'jsonPath'  (char/string) default: <video_dir>\<video_name>_vitals.json

    p = inputParser;
    p.addParameter('writeJson', false, @(x)islogical(x) || isnumeric(x));
    p.addParameter('jsonPath',  "",    @(x)ischar(x) || isstring(x));
    p.parse(varargin{:});

    writeJson = logical(p.Results.writeJson);
    jsonPath  = string(p.Results.jsonPath);

    % Resolve repo root from this file's location
    this_file    = mfilename('fullpath');
    this_dir     = fileparts(this_file);
    repo_root    = this_dir;
    fprintf('VITASENSE_PROGRESS=Repo root: %s\n', repo_root); drawnow;

    plot_path    = fullfile(repo_root, 'outputs', 'figs');
    trace_folder = fullfile(repo_root, 'outputs', 'logs');

    if ~isfolder(plot_path),    mkdir(plot_path);    end
    if ~isfolder(trace_folder), mkdir(trace_folder); end

    [hr_bpm, spo2_pct, ippg_signal, Fs] = iPPG_pipeline_kiosk(video_path, plot_path, trace_folder, repo_root);

    if writeJson
        if strlength(jsonPath) == 0
            [vp, vn] = fileparts(video_path);
            jsonPath = fullfile(vp, string(vn) + "_vitals.json");
        end
        write_vitals_json(jsonPath, hr_bpm, spo2_pct, video_path);
    end
end