function iPPG = compute_ippg(rawRGB, ippgSettings)
%COMPUTE_IPPG  Extract iPPG pulse signal from raw RGB traces.
%   iPPG = compute_ippg(rawRGB, ippgSettings)
%
%   rawRGB        : 3 x N matrix  [R; G; B] (0-255 scale)
%   ippgSettings  : struct with field .extractionMethod (string or int)
%
%   Supported methods:
%     'GREEN'    / 1  – green channel
%     'ICA'      / 2  – independent component analysis (fastica)
%     'CHROM'    / 3  – chrominance (de Haan & Jeanne 2013)
%     'POS'      / 4  – plane-orthogonal-to-skin (Wang et al. 2017)
%     'G_MINUS_R'/ 5  – green minus red
%     'AGRD'     / 6  – adaptive green-red difference

    method = ippgSettings.extractionMethod;

    % Accept both string and numeric method identifiers
    if isnumeric(method)
        names = {'GREEN','ICA','CHROM','POS','G_MINUS_R','AGRD'};
        if method >= 1 && method <= numel(names)
            method = names{method};
        else
            method = 'GREEN';
        end
    end

    R = double(rawRGB(1,:));
    G = double(rawRGB(2,:));
    B = double(rawRGB(3,:));

    switch upper(string(method))

        case "GREEN"
            iPPG = G;

        case "G_MINUS_R"
            iPPG = G - R;

        case "CHROM"
            % de Haan & Jeanne (2013) chrominance method
            Rn = R / mean(R);
            Gn = G / mean(G);
            Bn = B / mean(B);

            Xs = 3*Rn - 2*Gn;
            Ys = 1.5*Rn + Gn - 1.5*Bn;

            alpha = std(Xs) / std(Ys);
            iPPG = Xs - alpha * Ys;

        case "POS"
            % Wang et al. (2017) Plane-Orthogonal-to-Skin
            Rn = R / mean(R);
            Gn = G / mean(G);
            Bn = B / mean(B);

            S1 = Gn - Bn;
            S2 = Gn + Bn - 2*Rn;

            alpha = std(S1) / std(S2);
            iPPG = S1 + alpha * S2;

        case "ICA"
            % Independent Component Analysis via JADE/fastica
            X = [R; G; B];
            % Remove mean
            X = X - mean(X, 2);

            try
                [icasig, ~, ~] = fastica(X, 'numOfIC', 3, 'verbose', 'off', 'displayMode', 'off');
            catch
                % fastica not available — fall back to GREEN
                iPPG = G;
                return;
            end

            if isempty(icasig)
                iPPG = G;
                return;
            end

            % Select the component with the highest spectral energy in HR band
            bestPow = -Inf;
            bestIC  = 1;
            Fs = ippgSettings.samplingRate;
            for k = 1:size(icasig, 1)
                sig = icasig(k,:) - mean(icasig(k,:));
                nfft = 2^nextpow2(length(sig));
                P = abs(fft(sig, nfft)).^2;
                freqs = (0:nfft-1) * Fs / nfft;
                hrBand = freqs >= 0.65 & freqs <= 4.0;
                pw = sum(P(hrBand));
                if pw > bestPow
                    bestPow = pw;
                    bestIC  = k;
                end
            end
            iPPG = icasig(bestIC,:);

        case "AGRD"
            % Adaptive Green-Red Difference
            alpha = std(G) / std(R);
            iPPG = G - alpha * R;

        otherwise
            warning('compute_ippg: unknown method "%s", falling back to GREEN.', string(method));
            iPPG = G;
    end
end
