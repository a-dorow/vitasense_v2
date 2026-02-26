function outPath = write_vitals_json(jsonPath, hr_bpm, spo2_pct, video_path)
% write_vitals_json  Persist HR/SpO2 results to a JSON file.
%
% Inputs:
%   jsonPath   - output file path (char/string)
%   hr_bpm     - numeric scalar (heart rate)
%   spo2_pct   - numeric scalar (SpO2)
%   video_path - source video path (optional)
%
% Output:
%   outPath    - written JSON path (char)

if nargin < 4
    video_path = "";
end

if nargin < 1 || strlength(string(jsonPath)) == 0
    error('write_vitals_json:InvalidPath', 'jsonPath is required.');
end

outPath = char(string(jsonPath));
outDir = fileparts(outPath);
if ~isempty(outDir) && ~isfolder(outDir)
    mkdir(outDir);
end

payload = struct();
payload.timestamp_utc = char(datetime('now', 'TimeZone', 'UTC', 'Format', "yyyy-MM-dd'T'HH:mm:ss'Z'"));
payload.video_path = char(string(video_path));
payload.hr_bpm = double(hr_bpm);
payload.spo2_pct = double(spo2_pct);

% Add rounded display-friendly values while preserving raw values above.
payload.hr_bpm_rounded = round(payload.hr_bpm, 2);
payload.spo2_pct_rounded = round(payload.spo2_pct, 2);

jsonTxt = jsonencode(payload, 'PrettyPrint', true);

fid = fopen(outPath, 'w');
if fid == -1
    error('write_vitals_json:OpenFailed', 'Could not open %s for writing.', outPath);
end

cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonTxt, 'char');
end
