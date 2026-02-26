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

%Storing the subject's name with a cell array 

subjects_info = {subjects.name}';

%Getting the number part 
subject_numbers = [];
valid_subs = [];

%Sort through the numbers

[~, sorted_index] = sort(subject_numbers);

valid_subs = valid_subs(sorted_index); %reorganize the data


vid_direct={}; %Make that cell array

%Run through directories
for i = 1:length(subjects)
    subject_name = subjects(i).name;
    subject_folder = fullfile(video_path, subject_name);
    if subjects(i).isdir
        %list the contents 
        files = dir(fullfile(subject_folder,'*.avi'));
        for j = 1:length(files)
            avi_file = fullfile (subject_folder, files(j).name);
            vid_direct{end+1} = avi_file; %Add the .avi file path
        end
    end
end
avi_numbers = [];

for i = 1:length(vid_direct)
    [~, folder_name, ~] = fileparts(fileparts(vid_direct{i}));
    subject_num = regexp (folder_name, 'subject(\d+)', 'tokens');

    if ~isempty(subject_num)
        avi_numbers(i) = str2double(subject_num{1}{1});
    end
end

%Final sort for the .avi files

[~, sorted_idx] = sort(avi_numbers);

vid_direct = vid_direct(sorted_idx);

subjects_info = subjects_info(sorted_idx);


end