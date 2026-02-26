function process_fft_files(fft_folder, master_file)
% The purpose of this function is to process all the Fourier transform
% files in the FFT folder and store heart rate results in the master file

%The HR on the spreadsheets are reversed. And I can't figure out why. 

% Get list of FFT files in the folder
fft_files = dir(fullfile(fft_folder, '*.fig'));

% Prepare the master file
if exist(master_file, 'file')
    T = readtable(master_file);
    expect_columns = {'FileName', 'iPPG_HR', 'GT_HR'};

    %check if the master file has the right column names
    if ~all(ismember(expect_columns, T.Properties.VariableNames))
        miss_col = setdiff(expect_columns, T.Properties.VariableNames);
        if ~isempty(miss_col)
            for i = 1:length(miss_col)
            T.(miss_col{i}) = NaN(height(T), 1);
            end
        end
        writetable(T, master_file), %save the updated file
     %   fprintf('Master File has been updated with missing columns.')
    end

else
    T = table('Size', [0,3], 'VariableTypes', {'string', 'double', 'double'}, ...
        'VariableNames', {'FileName', 'iPPG_HR', 'GT_HR'});
end

% Check if master file has correct columns
if ~all(ismember({'FileName', 'iPPG_HR', 'GT_HR'}, T.Properties.VariableNames))
    error('Master file does not have correct column names.')
end

for i = 1:length(fft_files)
    fft_file_path = fullfile(fft_folder, fft_files(i).name);

    % Open the figure file and extract data
    fig = openfig(fft_file_path, 'invisible');
    axes_handles = findobj(fig, 'Type', 'axes');

    % Ensure figure has enough axes
    if length(axes_handles) < 4
        warning('Figure does not have enough axes: %s', fft_file_path);
        close(fig);
        continue;
    end

    % Get data for plot 2 (iPPG) and plot 4 (ground truth)
    iPPG_data = get(axes_handles(1), 'Children');
    gt_data = get(axes_handles(3), 'Children');

    % Extract frequency and amplitude data
    iPPG_X = get(iPPG_data, 'XData');
    iPPG_Y = get(iPPG_data, 'YData');
    gt_X = get(gt_data, 'XData');
    gt_Y = get(gt_data, 'YData');

    % Finding the peak frequency for iPPG and ground truth
    [~, idx_2] = max(iPPG_Y);
    max_peak_freq_iPPG = iPPG_X(idx_2);  % iPPG data

    [~, idx_4] = max(gt_Y);
    max_peak_freq_gt = gt_X(idx_4);  % Ground truth data

    % Compute heart rates
    iPPG_HR = max_peak_freq_iPPG * 60;
    GT_HR = max_peak_freq_gt * 60;

    % Extract file name without extension
    [~, output_name, ~] = fileparts(fft_file_path);

    % Skip already processed files
    if any(strcmp(T.FileName, output_name))
      %  fprintf('File %s has already been processed. Skipping.\n', output_name);
        close(fig);
        continue;
    end

  % disp([output_name 'HR for iPPG is ' num2str(iPPG_HR)])
  % disp([output_name ' HR for GT is ' num2str(GT_HR)])
    % Append new data
    new_row = table({output_name}', iPPG_HR, GT_HR, 'VariableNames', {'FileName', 'iPPG_HR', 'GT_HR'});
    T = [T; new_row];  % Concatenate new row to the table

    % Save the updated master spreadsheet
    try
        writetable(T, master_file);
    catch ME
        error('Failed to write to master file: %s', ME.message);
    end

    % Close the figure
    close(fig);
end
end

%put in a display for each extraction method to make sure the proper
%extraction is being done. 