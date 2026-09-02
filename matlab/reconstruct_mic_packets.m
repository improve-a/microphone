function [matrix, validity, stats] = reconstruct_mic_packets(datagrams, channels, frameSamples, startingSequence)
%RECONSTRUCT_MIC_PACKETS Reconstruct frame zero; gaps remain zero and invalid.
matrix = zeros(channels, frameSamples, 'int16');
validity = false(channels, frameSamples);
stats.missing = 0; stats.duplicates = 0; stats.malformed = 0;
seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');
if nargin < 4, expected = []; else, expected = uint32(startingSequence); end
for n = 1:numel(datagrams)
    try
        [header, pcm] = parse_mic_udp_packet(datagrams{n});
    catch err
        if strcmp(err.identifier, 'MIC:Protocol')
            stats.malformed = stats.malformed + 1; continue;
        end
        rethrow(err);
    end
    key = sprintf('%u', header.packet_sequence);
    if isKey(seen, key), stats.duplicates = stats.duplicates + 1; continue; end
    if isempty(expected), expected = header.packet_sequence; end
    if header.packet_sequence < expected
        stats.duplicates = stats.duplicates + 1; continue;
    end
    if header.packet_sequence > expected
        stats.missing = stats.missing + double(header.packet_sequence - expected);
    end
    expected = header.packet_sequence + uint32(1); seen(key) = true;
    startIndex = double(header.sample_start) + 1;
    endIndex = startIndex + double(header.samples_per_channel) - 1;
    if header.channel_count ~= channels || endIndex > frameSamples
        stats.malformed = stats.malformed + 1; continue;
    end
    if any(validity(:, startIndex:endIndex), 'all')
        stats.duplicates = stats.duplicates + 1; continue;
    end
    matrix(:, startIndex:endIndex) = pcm;
    validity(:, startIndex:endIndex) = true;
end
end
