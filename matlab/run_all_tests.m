function run_all_tests()
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, 'matlab'));
packets = read_mic_packet_file(fullfile(root, 'vectors', 'mic_udp_packets.bin'));
expected = int16(readmatrix(fullfile(root, 'vectors', 'mic_expected_pcm.csv')));
[actual, validity, stats] = reconstruct_mic_packets(packets, 8, 128, 0);
assert(all(validity, 'all')); assert(isequal(actual, expected));
assert(stats.missing == 0 && stats.duplicates == 0 && stats.malformed == 0);

lossPackets = packets; lossPackets(1) = [];
[~, lossValidity, lossStats] = reconstruct_mic_packets(lossPackets, 8, 128, 0);
assert(lossStats.missing == 1); assert(~all(lossValidity, 'all'));

duplicatePackets = [packets(1), packets];
[~, ~, duplicateStats] = reconstruct_mic_packets(duplicatePackets, 8, 128, 0);
assert(duplicateStats.duplicates == 1);

malformed = packets{1}; malformed(1) = bitxor(malformed(1), uint8(255));
didReject = false;
try, parse_mic_udp_packet(malformed); catch err, didReject = strcmp(err.identifier, 'MIC:Protocol'); end
assert(didReject);

base = int32(actual(1, :));
for c = 1:7
    assert(isequal(int32(actual(c+1, c+1:end)), bitshift(base(1:end-c), -c)));
end
assert(min(actual(1, :)) == intmin('int16'));
assert(max(actual(1, :)) == intmax('int16'));
disp('MIC_MATLAB_E2E_PASS');

rng(2026, 'twister');
sampleRate = 48000; spacing = 0.04; soundSpeed = 343; sampleCount = 2048;
baseSignal = int16(randi([-20000, 20000], 1, sampleCount));
arrayPcm = zeros(8, sampleCount, 'int16');
for channel = 0:7
    arrayPcm(channel+1, channel+1:end) = baseSignal(1:end-channel);
end
[tdoa, angle] = gcc_phat_doa(arrayPcm, sampleRate, spacing, soundSpeed);
expectedTdoa = (0:7).' / sampleRate;
expectedAngle = asind(soundSpeed / (sampleRate * spacing));
assert(max(abs(tdoa - expectedTdoa)) < 0.5 / sampleRate);
assert(abs(angle - expectedAngle) < 0.25);
disp('MIC_GCC_PHAT_DOA_PASS');
end
