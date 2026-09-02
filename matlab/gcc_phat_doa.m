function [tdoaSeconds, angleDegrees] = gcc_phat_doa(pcm, sampleRate, spacingMeters, soundSpeed)
%GCC_PHAT_DOA Offline linear-array delay and broadside-angle estimate.
[channels, samples] = size(pcm);
if channels < 2 || samples < 2, error('MIC:DOA', 'PCM matrix is too small'); end
nfft = 2^nextpow2(2 * samples - 1);
reference = double(pcm(1, :));
referenceSpectrum = fft(reference, nfft);
lags = -nfft/2:nfft/2-1;
tdoaSeconds = zeros(channels, 1);
for channel = 2:channels
    spectrum = fft(double(pcm(channel, :)), nfft);
    crossSpectrum = spectrum .* conj(referenceSpectrum);
    crossSpectrum = crossSpectrum ./ max(abs(crossSpectrum), eps);
    correlation = fftshift(real(ifft(crossSpectrum)));
    maxLag = ceil((channel - 1) * spacingMeters * sampleRate / soundSpeed) + 1;
    selected = find(abs(lags) <= maxLag);
    [~, localIndex] = max(abs(correlation(selected)));
    tdoaSeconds(channel) = lags(selected(localIndex)) / sampleRate;
end
positions = (0:channels-1).' * spacingMeters;
fitCoefficients = polyfit(positions, tdoaSeconds, 1);
sinAngle = max(-1, min(1, fitCoefficients(1) * soundSpeed));
angleDegrees = asind(sinAngle);
end

