function result = live_mic_receiver(varargin)
%LIVE_MIC_RECEIVER Receive MIC0 UDP packets for a bounded live session.
% Name/value options: LocalPort (default 5000), Seconds (10), Channels (8),
% FrameSamples (128), SaveFile (''), Plot (true).
p = inputParser;
addParameter(p, 'LocalPort', 45123, @(x)isscalar(x) && x > 0);
addParameter(p, 'Seconds', 10, @(x)isscalar(x) && x >= 0);
addParameter(p, 'Channels', 8, @(x)isscalar(x) && x > 0);
addParameter(p, 'FrameSamples', 128, @(x)isscalar(x) && x > 0);
addParameter(p, 'SaveFile', '', @(x)ischar(x) || isstring(x));
addParameter(p, 'Plot', true, @(x)islogical(x) && isscalar(x));
parse(p, varargin{:}); opts = p.Results;

u = udpport('datagram', 'IPV4', 'LocalPort', opts.LocalPort, 'Timeout', 0.1);
cleanup = onCleanup(@()clear('u'));
datagrams = {};
stats = struct('received', 0, 'missing', 0, 'duplicates', 0, ...
    'malformed', 0, 'crc_errors', 0, 'heartbeats', 0, ...
    'raw_udp_diagnostics', 0, 'pcm_packets', 0, 'last_sequence', []);
fig = []; ax = []; lines = [];
history = zeros(opts.FrameSamples, opts.Channels);
fs = 48828;
if opts.Plot
    fig = figure('Name', 'MIC0 live receiver');
    ax = subplot(2, 1, 1, 'Parent', fig); lines = plot(ax, history);
    ylim(ax, [-32768 32767]); grid(ax, 'on'); title(ax, '8-channel PCM');
    spectrum_ax = subplot(2, 1, 2, 'Parent', fig);
    spectrum_lines = plot(spectrum_ax, zeros(floor(opts.FrameSamples / 2), opts.Channels));
    xlim(spectrum_ax, [0 fs / 2]); grid(spectrum_ax, 'on'); title(spectrum_ax, 'Magnitude spectrum');
else
    spectrum_ax = []; spectrum_lines = [];
end
deadline = tic;
expected = [];
while toc(deadline) < opts.Seconds
    if u.NumDatagramsAvailable == 0, pause(0.01); continue; end
    packet = read(u, 1, 'uint8');
    bytes = packet.Data(:);
    datagrams{end+1} = bytes; %#ok<AGROW>
    stats.received = stats.received + 1;
    if numel(bytes) >= 14 && isequal(char(bytes(1:14).'), 'MIC_HEARTBEAT ')
        stats.heartbeats = stats.heartbeats + 1;
        continue;
    end
    if contains(char(bytes.'), 'MIC_RAW_UDP_UNIQUE_20260903')
        stats.raw_udp_diagnostics = stats.raw_udp_diagnostics + 1;
        continue;
    end
    try
        [header, pcm] = parse_mic_udp_packet(bytes);
        stats.pcm_packets = stats.pcm_packets + 1;
        seq = uint32(header.packet_sequence);
        if isempty(expected), expected = seq; end
        if seq < expected, stats.duplicates = stats.duplicates + 1; end
        if seq > expected, stats.missing = stats.missing + double(seq - expected); end
        expected = seq + uint32(1); stats.last_sequence = seq;
        if opts.Plot && header.channel_count == opts.Channels
            count = min(size(pcm, 2), opts.FrameSamples);
            history = [history(count+1:end, :); double(pcm(:, 1:count)).'];
            for k = 1:opts.Channels, set(lines(k), 'YData', history(:, k)); end
            fft_data = abs(fft(history, [], 1));
            fft_data = fft_data(1:floor(opts.FrameSamples / 2), :);
            frequencies = (0:size(fft_data, 1) - 1).' * fs / opts.FrameSamples;
            for k = 1:opts.Channels
                set(spectrum_lines(k), 'XData', frequencies, 'YData', fft_data(:, k));
            end
            drawnow limitrate;
        end
    catch err
        stats.malformed = stats.malformed + 1;
        if contains(err.message, 'CRC'), stats.crc_errors = stats.crc_errors + 1; end
    end
end
clear cleanup
result = struct('datagrams', {datagrams}, 'stats', stats, ...
    'git_sha', git_sha(), 'received_at', datetime('now'));
if strlength(string(opts.SaveFile)) > 0
    save(opts.SaveFile, '-struct', 'result');
end
fprintf('MIC_MATLAB_LIVE_CAPTURE received=%d heartbeat=%d missing=%d duplicates=%d malformed=%d crc=%d\n', ...
    stats.received, stats.heartbeats, stats.missing, stats.duplicates, stats.malformed, stats.crc_errors);
end

function sha = git_sha()
[~, text] = system('git rev-parse HEAD'); sha = strtrim(text);
end
