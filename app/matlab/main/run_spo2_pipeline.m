%% Converting a .mp4 to .avi

video = "D:\CNAP Data\BV Pipeline\VitaSense Validation\Subject_8.mp4";

readerobj = VideoReader(video);
writerobj = VideoWriter("D:\CNAP Data\BV Pipeline\VitaSense Validation\Subject_8.avi", 'Uncompressed AVI');
open(writerobj)

%Loop through the frames
while hasFrame(readerobj)
    frame = readFrame(readerobj);
    writeVideo(writerobj,frame)
end

%Close the writer
close(writerobj)
disp('Conversion Done!')

%%

video_path   = "D:\CNAP Data\spo2_retest_ring_off\subject_2\subject_2.mp4";
plot_path    = 'D:\SpO2 Validation Pipeline\Plots';
trace_folder = "D:\SpO2 Validation Pipeline\Traces";
main_path    = 'D:\SpO2 Validation Pipeline';


iPPG_pipeline_v4(video_path, plot_path, trace_folder, main_path);

%% Batch Running



% Paths that do NOT change
plot_path    = 'D:\SpO2 Validation Pipeline\Plots Parish';
trace_folder = 'D:\SpO2 Validation Pipeline\Traces Parish';
main_path    = 'D:\SpO2 Validation Pipeline';

% Root where subject folders live
video_root = "D:\SpO2 Validation Pipeline\Data for Parish Stats";

% Loop over subjects 1–10
for subj = 1:3

    subject_name = sprintf('subject_%d', subj);

    video_path = fullfile( ...
        video_root, ...
        subject_name, ...
        subject_name + ".mp4" ...
    );

    fprintf('\n=== Processing %s ===\n', subject_name);
    fprintf('Video path: %s\n', video_path);

    if ~isfile(video_path)
        warning('Video not found for %s — skipping.', subject_name);
        continue;
    end

    % Run pipeline
    iPPG_pipeline_v4(video_path, plot_path, trace_folder, main_path);

end

fprintf('\nAll subjects processed.\n');
