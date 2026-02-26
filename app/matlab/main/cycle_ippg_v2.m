%function  cycle_ippg_v2(plot_path, trace_folder, main_path)
function results = cycle_ippg_v2(plot_path, trace_folder, main_path)

    extraction_fold_name = 'Extraction Methods';
    extraction_root = fullfile(main_path, extraction_fold_name);

    if ~exist(extraction_root, 'dir')
        mkdir(extraction_root);
        disp(['Folder created: ' extraction_root])
    else
        disp(['Folder already exists: ', extraction_root])
    end

    % List all subject directories inside the root folder
    sub_extraction = dir(plot_path);
    sub_extraction = sub_extraction([sub_extraction.isdir]); % Only keep directories
    sub_extraction = sub_extraction(~ismember({sub_extraction.name}, {'.', '..'})); % Exclude the current directory and parent directory and therefore only will grab the subject1 etc

    % Define extraction method folders
    extraction_methods = {'CHROM', 'AGRD', 'G_MINUS_R', 'GREEN', 'ICA', 'POS'};

    % Looping through each subject directory
    for i = 1:length(sub_extraction)
        subject_folder = fullfile(plot_path, sub_extraction(i).name); % Path to subject folder
        
        % Get list of all MATLAB figure files in the subject folder
        fig_files = dir(fullfile(subject_folder, '*.fig'));
        
        % Process each figure file
        for j = 1:length(fig_files)
            fig_path = fullfile(subject_folder, fig_files(j).name); % Full path of the figure file
            [~, file_name, ~] = fileparts(fig_files(j).name); % Get the figure name without extension
            
            % Looping through each extraction
            for k = 1:length(extraction_methods)
                method = extraction_methods{k};
                
                if contains(file_name, method, 'IgnoreCase', true)
                    % Create the extraction method folder under the root if it doesn't exist
                    method_folder = fullfile(extraction_root, method);
                    if ~isfolder(method_folder)
                        mkdir(method_folder);
                    end
                    
                    % Move the figure file to the extraction method folder
                    movefile(fig_path, fullfile(method_folder, fig_files(j).name));
                    fprintf('Moved %s to %s\n', fig_files(j).name, method_folder);
                    break; % Exit the loop after moving the file
                end
            end
        end
    end

 %% run the Fast Fourier transformation
 if nargout == 0
     clear results;
 end
 % extraction_root = "D:\Fully Automated\Extraction Methods"; 
 % trace_folder = "D:\Matlab_rPPG\Trace_plots_2";
 %  pwd = "D:\Fully Automated";
%match_and_process_fft_v4(extraction_root, trace_folder, main_path)
results = match_and_process_fft_v4(extraction_root, trace_folder, main_path);

%also find the path to the the made file which will be set to fft_path


end