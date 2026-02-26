%Function to perform notch and bandpass filtering
%INPUTS:
%fa: input [time x channels]
%Fs: sampling frequency
%hp_cutoff: high pass cutoff 
%lp_cutoff: low pass cutoff

function filter_out = filter_fcn_liu (fa,Fs,hp_cutoff,lp_cutoff)

% %form time vector
% t=[0:length(fa)-1]/Fs;
% L=length(fa);
%------------------------------------------
%lowpass filter signal @ 20Hz cutoff frequency
%------------------------------------------
%For data sampled at 256 Hz, design a 3rd-order highpass Butterworth
%filter with cutoff frequency of 20 Hz, which corresponds to a normalized value of 0.6:
% % [z,p,k] = butter(3,20/128,'low');
% % [sos,g] = zp2sos(z,p,k);	     % Convert to SOS form
% % Hd = dfilt.df2tsos(sos,g);   % Create a dfilt object
% % h = fvtool(Hd);	             % Plot magnitude response
% % set(h,'Analysis','freq')	     % Display frequency response
% % 
% % [b,a] = butter(3,20/128,'s');
% % yy = filter(b,a,fa);

% %------------------------------------------
% %plot original data
% %------------------------------------------
% figure;
% clf;
% subplot(4,1,1);
% plot(Fs*t(1:L),fa(1:L));
% title('Unfiltered signal')
% xlabel('time (milliseconds)')
% 
% %perform fourier transform of signal and plot.
% subplot(4,1,2);
% NFFT = 2^nextpow2(L); % Next power of 2 from length of y
% Y = fft(fa,NFFT)/L;
% f = Fs/2*linspace(0,1,NFFT/2+1);
% 
% % Plot single-sided amplitude spectrum.
% plot(f,2*abs(Y(1:NFFT/2+1))); 
% title('Magnitude of unfiltered signal in frequency domain')
% xlabel('Frequency (Hz)')
% ylabel('|Y(f)|')
% hold all;

%--------------------------------
%---------Adding Notch-----------
%--------------------------------
Fn = Fs/2; % Nyquist freq [Hz]
W0 = 60; % notch frequency [Hz] %changed for US
w0 = W0*pi/Fn; % notch frequency normalized
BandWidth = 5; % -3dB BandWidth [Hz]
B = BandWidth*pi/Fn; % normalized bandwidth
k1 = -cos(w0); k2 = (1 - tan(B/2))/(1 + tan(B/2));
b = [1+k2 2*k1*(1+k2) 1+k2];
a = [2 2*k1*(1+k2) 2*k2];
notch_filtered=double(filtfilt(b,a,fa));

%------------------------------------------
%Lowpass filter signal @10Hz and plot (cutoff/128)
%------------------------------------------

parameter=lp_cutoff/(Fs/2);
 [b,a] = butter(4,parameter,'low');
 lp_filtered = filtfilt(b,a,notch_filtered);

% blah = lowpass_20Hz;
% lp_filtered=filter(blah, notch_filtered);
%------------------------------------------
%highpass signal @ 1Hz and plot 
%------------------------------------------

parameter=hp_cutoff/(Fs/2);
[b,a] = butter(4,parameter,'high');
hp_filtered = filtfilt(b,a,lp_filtered);

% subplot(4,1,3);
% plot(Fs*t(1:L),hp_filtered(1:L));
% title('filtered signal in time domain (notch+lowpass+highpass)')
% xlabel('Time (ms)')
% 
% %perform fourier transform of signal and plot.
% subplot(4,1,4);
% NFFT = 2^nextpow2(L); % Next power of 2 from length of y
% Y = fft(hp_filtered,NFFT)/L;
% 
% % Plot single-sided amplitude spectrum.
% plot(f,2*abs(Y(1:NFFT/2+1))); 
% title('Amplitude spectrum after notch + lowpass + highpass filtering')
% xlabel('Frequency (Hz)')
% ylabel('|Y(f)|')
 filter_out = hp_filtered;


