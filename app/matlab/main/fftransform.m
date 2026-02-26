function fftransform(file_1, file_2, fft_folder)
    % The purpose of this function is to use a fast Fourier transformation
    % which will then be utilized to find the actual heart rate.

    % Extract the filename from the path
    [~, filename, ~] = fileparts(file_1);

    % Regular expression to extract subject and method
    sub_pattern = 'subject(\d+)';
    meth_pattern = '_(\w+)_iPPG';

    % Extract the subject number
    subject_tokens = regexp(filename, sub_pattern, 'tokens');
    if ~isempty(subject_tokens)
        subject = ['subject' subject_tokens{1}{1}]; % e.g., 'subject18'
    else
        subject = ''; % Handle case if subject not found
    end

    % Extract the method name
    method_tokens = regexp(filename, meth_pattern, 'tokens');
    if ~isempty(method_tokens)
        method = method_tokens{1}{1}; % e.g., 'AGRD'
    else
        method = ''; % Handle case if method not found
    end

    % Combine the subject and method
    if ~isempty(subject) && ~isempty(method)
        output_name = [subject '_' method];
    else
        output_name = 'unknown'; % Handle case if either subject or method is not found
    end

    % Display the result
   % disp(['Output Name: ' output_name]);

    %% Load Data 1 (experimental)
    % Check if the file exists before attempting to open it
    if ~isfile(file_1)
        error('File %s does not exist', file_1);
    end

    fig1 = openfig(file_1); % Needs to be the iPPG
    if ~isfile(file_2)
        error('File %s does not exist', file_2);
    end

    fig2 = openfig(file_2); % Needs to be the ground truth

    % Extract Data from iPPG extraction
    axes1 = findobj(fig1, 'Type', 'axes');
    line1 = findobj(axes1, 'Type', 'line');
    data_iPPG = get(line1, 'Ydata');

    % Extract data from ground truth
    axes2 = findobj(fig2, 'Type', 'axes');
    line2 = findobj(axes2, 'Type', 'line');
    data_gt = get(line2, 'Ydata');

    close(fig1);
    close(fig2);

    %% Create the graph
    Fs = 30; % Sampling rate
    L_iPPG = length(data_iPPG);
    L_gt = length(data_gt);
    Fa = data_iPPG;
    Fa2 = data_gt;

    t = (0:L_iPPG-1) / Fs; % Time vector in seconds for iPPG
    t2 = (0:L_gt-1) / Fs;

    figure('Name', output_name);
    clf;
    subplot(4, 1, 1);
    plot(Fs * t(1:L_iPPG), Fa(1:L_iPPG));
    title('Unfiltered signal of the iPPG', output_name);
    xlabel('Time (milliseconds)');

    % Perform Fourier transform of signal and plot
    NFFT = 2^nextpow2(L_iPPG); % Next power of 2 from length of y
    Y = fft(Fa, NFFT) / L_iPPG;
    f = Fs / 2 * linspace(0, 1, NFFT / 2 + 1);

    % Plot single-sided amplitude spectrum
    subplot(4, 1, 2);
    plot(f, 2 * abs(Y(1:NFFT / 2 + 1))); 
    title('Magnitude of unfiltered signal of the iPPG in frequency domain');
    xlabel('Frequency (Hz)');
    ylabel('|Y(f)|');

    % Unfiltered of the ground truth
    subplot(4, 1, 3);
    plot(Fs * t2(1:L_gt), Fa2(1:L_gt));
    title('Unfiltered signal of the ground truth');
    xlabel('Time (milliseconds)');

    % Fourier transformation of the ground truth
    NFFT = 2^nextpow2(L_gt); % Next power of 2 from length of y
    Y2 = fft(Fa2, NFFT) / L_gt;
    f2 = Fs / 2 * linspace(0, 1, NFFT / 2 + 1);

    % Plot the single-sided amplitude spectrum
    subplot(4, 1, 4);
    plot(f2, 2 * abs(Y2(1:NFFT / 2 + 1))); 
    title('Magnitude of unfiltered signal of the Ground Truth in frequency domain');
    xlabel('Frequency (Hz)');
    ylabel('|Y(f)|');
    hold all;

    % Save the file 
    save_path = fullfile(fft_folder, [output_name, '_fft.fig']);
    try 
        saveas(gcf, save_path);
    catch ME
        error('Failed to save figure: %s', ME.message);
    end

    % Close the figure
    close(gcf);
end
