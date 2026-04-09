function [vid_direct,subjects_info] = cycle_avi(video_path)
%The purpose of this function is to cycle through all the subject folders
%to extract the subject's info (the number) with the different file paths
%for each .avi file.
if ~isfolder (video_path)
    error('Root folder does not exist')
end

%listing out the subfolders
subjects = dir(video_path);
subjects = subjects([subjects.isdir]);
subjects = subjects(~ismember({subjects.name}, {'.','..','desktop.ini'}));

%Getting the number part 
subject_numbers = [];
valid_subs = [];

%Sort through the numbers

[~, sorted_index] = sort(subject_numbers);

valid_subs = valid_subs(sorted_index); %reorganize the data


vid_direct    = {}; %Make that cell array
subjects_info = {}; % Built alongside vid_direct so they stay the same length

%Run through directories
for i = 1:length(subjects)
    subject_name = subjects(i).name;
    subject_folder = fullfile(video_path, subject_name);
    if subjects(i).isdir
        %list the contents — collect both .avi and .mp4 so that
        %downsampled resolution videos (which are often .mp4) are found.
        avi_files = dir(fullfile(subject_folder,'*.avi'));
        mp4_files = dir(fullfile(subject_folder,'*.mp4'));
        files = [avi_files; mp4_files];
        for j = 1:length(files)
            vid_file = fullfile(subject_folder, files(j).name);
            vid_direct{end+1} = vid_file; %Add the video file path

            % Use the video filename (without extension) as the unique ID
            % so that each trial gets its own subfolder and .fig files.
            % e.g. subject_1_trial_2_360p stays intact rather than
            % collapsing all trials down to subject_1.
            [~, vid_name, ~] = fileparts(files(j).name);
            subjects_info{end+1} = vid_name; %Store unique per-trial name
        end
    end
end

% Build sort key from the subject folder name embedded in each video path.
% avi_numbers must be the same length as vid_direct.
avi_numbers = zeros(1, length(vid_direct));

for i = 1:length(vid_direct)
    [~, folder_name, ~] = fileparts(fileparts(vid_direct{i}));
    subject_num = regexp(folder_name, 'subject(\d+)', 'tokens');

    if ~isempty(subject_num)
        avi_numbers(i) = str2double(subject_num{1}{1});
    end
end

%Final sort for the .avi files

[~, sorted_idx] = sort(avi_numbers);

vid_direct    = vid_direct(sorted_idx);
subjects_info = subjects_info(sorted_idx);


end