function result = live_mic_receiver(varargin)
%LIVE_MIC_RECEIVER Receive and visualize the validated MIC0 UDP stream.
% The receiver keeps raw datagrams plus PCM, and emits a ready marker only
% after continuous valid PCM has arrived. It is intended for R2024a udpport.
p = inputParser;
addParameter(p, 'LocalPort', 45123, @(x)isscalar(x) && x > 0);
addParameter(p, 'Seconds', 65, @(x)isscalar(x) && x >= 0);
addParameter(p, 'Channels', 8, @(x)isscalar(x) && x > 0);
addParameter(p, 'FrameSamples', 128, @(x)isscalar(x) && x > 0);
addParameter(p, 'SampleRate', 48828, @(x)isscalar(x) && x > 0);
addParameter(p, 'SaveFile', '', @(x)ischar(x) || isstring(x));
addParameter(p, 'OutputDir', '', @(x)ischar(x) || isstring(x));
addParameter(p, 'ReadyFile', '', @(x)ischar(x) || isstring(x));
addParameter(p, 'StopFile', '', @(x)ischar(x) || isstring(x));
addParameter(p, 'Plot', true, @(x)islogical(x) && isscalar(x));
addParameter(p, 'MinReadyPcmPackets', 20, @(x)isscalar(x) && x > 0);
parse(p, varargin{:}); opts = p.Results;

if strlength(string(opts.OutputDir)) == 0 && strlength(string(opts.SaveFile)) > 0
    opts.OutputDir = fileparts(char(opts.SaveFile));
end
if strlength(string(opts.OutputDir)) > 0 && ~isfolder(opts.OutputDir)
    mkdir(opts.OutputDir);
end
if strlength(string(opts.ReadyFile)) == 0 && strlength(string(opts.OutputDir)) > 0
    opts.ReadyFile = fullfile(opts.OutputDir, 'matlab_ready.flag');
end

u = udpport('datagram', 'IPV4', 'LocalPort', opts.LocalPort, 'Timeout', 0.1);
cleanup = onCleanup(@()clear('u')); %#ok<NASGU>
datagrams = {};
stats = struct('received', 0, 'missing', 0, 'duplicates', 0, ...
    'malformed', 0, 'crc_errors', 0, 'heartbeats', 0, ...
    'raw_udp_diagnostics', 0, 'pcm_packets', 0, ...
    'last_sequence', [], 'ready', false, 'sample_rate_hz', opts.SampleRate);
expected = [];
pcm_capacity = max(round(opts.SampleRate * (opts.Seconds + 5)), 2 * opts.FrameSamples);
pcm_all = zeros(opts.Channels, pcm_capacity, 'int16');
pcm_count = 0;
history_samples = max(round(5 * opts.SampleRate), 5 * opts.FrameSamples);
ring = zeros(history_samples, opts.Channels, 'double');
ring_pos = 0; ring_count = 0;
envelope_t = zeros(0, 1); envelope = zeros(0, opts.Channels);
last_plot = tic;

wave_fig = []; wave_axes = []; wave_lines = [];
spec_fig = []; spec_ax = []; spec_lines = [];
rms_fig = []; rms_ax = []; rms_bar = []; env_lines = [];
if opts.Plot
    wave_fig = figure('Name', 'MIC0 live PCM (dynamic scale)', 'Color', 'w');
    tiledlayout(wave_fig, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    wave_axes = gobjects(opts.Channels, 1); wave_lines = gobjects(opts.Channels, 1);
    for k = 1:opts.Channels
        wave_axes(k) = nexttile;
        wave_lines(k) = plot(wave_axes(k), nan, nan, 'b-', 'LineWidth', 0.7);
        grid(wave_axes(k), 'on'); ylabel(wave_axes(k), 'PCM');
        if k == opts.Channels
            title(wave_axes(k), 'CH8 - UNUSED SLOT / UNVERIFIED');
        else
            title(wave_axes(k), sprintf('CH%d', k));
        end
    end
    xlabel(wave_axes(opts.Channels), 'seconds (recent 5 s)');
    spec_fig = figure('Name', 'MIC0 live spectrum', 'Color', 'w');
    spec_ax = axes(spec_fig); hold(spec_ax, 'on');
    spec_lines = gobjects(opts.Channels, 1);
    for k = 1:opts.Channels, spec_lines(k) = plot(spec_ax, nan, nan); end
    grid(spec_ax, 'on'); xlim(spec_ax, [0 opts.SampleRate / 2]);
    title(spec_ax, 'Magnitude spectrum (centered, recent window)'); xlabel(spec_ax, 'Hz');
    ylabel(spec_ax, 'magnitude');
    rms_fig = figure('Name', 'MIC0 RMS and 5 s envelope', 'Color', 'w');
    tiledlayout(rms_fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    rms_ax = nexttile; rms_bar = bar(rms_ax, zeros(opts.Channels, 2));
    grid(rms_ax, 'on'); xlabel(rms_ax, 'channel'); ylabel(rms_ax, 'PCM');
    legend(rms_ax, {'RMS', 'Peak'}, 'Location', 'northwest');
    title(rms_ax, 'Per-channel live RMS / peak');
    env_ax = nexttile; hold(env_ax, 'on');
    env_lines = gobjects(opts.Channels, 1);
    for k = 1:opts.Channels, env_lines(k) = plot(env_ax, nan, nan); end
    grid(env_ax, 'on'); xlabel(env_ax, 'seconds'); ylabel(env_ax, 'short-time RMS');
    title(env_ax, '5 second short-time RMS envelope');
end

deadline = tic;
fatal_error = [];
try
while toc(deadline) < opts.Seconds
    if strlength(string(opts.StopFile)) > 0 && isfile(opts.StopFile)
        fprintf('MIC_MATLAB_STOP_FILE_DETECTED path=%s\n', char(opts.StopFile));
        break;
    end
    if u.NumDatagramsAvailable == 0
        pause(0.01);
        continue;
    end
    packet = read(u, 1, 'uint8');
    bytes = uint8(packet.Data(:));
    datagrams{end + 1} = bytes; %#ok<AGROW>
    stats.received = stats.received + 1;
    if numel(bytes) >= 14 && startsWith(char(bytes.'), 'MIC_HEARTBEAT ')
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
        if isempty(expected)
            expected = seq;
        elseif seq < expected
            stats.duplicates = stats.duplicates + 1;
        elseif seq > expected
            stats.missing = stats.missing + double(seq - expected);
        end
        expected = seq + uint32(1);
        stats.last_sequence = seq;
        if header.channel_count ~= opts.Channels
            error('MIC:Protocol', 'unexpected channel count');
        end
        sample_count = size(pcm, 2);
        if pcm_count + sample_count > size(pcm_all, 2)
            pcm_all(:, end + 1:end + pcm_capacity) = int16(0); %#ok<AGROW>
        end
        pcm_all(:, pcm_count + 1:pcm_count + sample_count) = int16(pcm);
        pcm_count = pcm_count + sample_count;
        samples = double(pcm.');
        for row = 1:size(samples, 1)
            ring_pos = mod(ring_pos, history_samples) + 1;
            ring(ring_pos, :) = samples(row, :);
            ring_count = min(ring_count + 1, history_samples);
        end
        if ~stats.ready && stats.pcm_packets >= opts.MinReadyPcmPackets
            stats.ready = true;
            write_marker(opts.ReadyFile, sprintf('MIC_ACOUSTIC_ACTION_READY pcm_packets=%d\n', stats.pcm_packets));
            fprintf('MIC_ACOUSTIC_ACTION_READY pcm_packets=%d datagrams=%d\n', ...
                stats.pcm_packets, stats.received);
        end
        if opts.Plot && toc(last_plot) >= 0.50
            recent = ordered_ring(ring, ring_pos, ring_count, history_samples, opts.Channels);
            centered = recent - mean(recent, 1);
            t = ((1:size(centered, 1)) - size(centered, 1)) / opts.SampleRate;
            rms_now = sqrt(mean(centered .^ 2, 1));
            peak_now = max(abs(centered), [], 1);
            if numel(rms_bar) >= 2
                set(rms_bar(1), 'YData', rms_now(:));
                set(rms_bar(2), 'YData', peak_now(:));
            else
                set(rms_bar, 'YData', rms_now(:));
            end
            for k = 1:opts.Channels
                set(wave_lines(k), 'XData', t, 'YData', centered(:, k));
                lim = max(1, 1.20 * max(abs(centered(:, k))));
                ylim(wave_axes(k), [-lim lim]); xlim(wave_axes(k), [t(1) 0]);
            end
            win = min(size(centered, 1), round(opts.SampleRate * 5));
            fft_values = abs(fft(centered(end - win + 1:end, :), [], 1));
            nfft = floor(win / 2) + 1;
            freq = (0:nfft - 1).' * opts.SampleRate / win;
            for k = 1:opts.Channels
                set(spec_lines(k), 'XData', freq, 'YData', fft_values(1:nfft, k));
            end
            if size(centered, 1) >= 512
                w = 512; hop = 128;
                starts = 1:hop:(size(centered, 1) - w + 1);
                env = zeros(numel(starts), opts.Channels);
                for ii = 1:numel(starts)
                    block = centered(starts(ii):starts(ii) + w - 1, :);
                    env(ii, :) = sqrt(mean(block .^ 2, 1));
                end
                envelope_t = t(starts + floor(w / 2));
                envelope = env;
                for k = 1:opts.Channels
                    set(env_lines(k), 'XData', envelope_t, 'YData', envelope(:, k));
                end
                xlim(env_ax, [t(1) 0]);
            end
            drawnow limitrate nocallbacks;
            last_plot = tic;
        end
    catch err
        stats.malformed = stats.malformed + 1;
        if stats.malformed <= 3
            fprintf('MIC_MATLAB_PACKET_ERROR %s\n', err.message);
        end
        if contains(err.message, 'CRC')
            stats.crc_errors = stats.crc_errors + 1;
        end
    end
end
catch err
    fatal_error = err;
    fprintf('MIC_MATLAB_FATAL_ERROR %s\n', err.message);
end

if opts.Plot
    save_plot(wave_fig, opts.OutputDir, 'waveform.png');
    save_plot(rms_fig, opts.OutputDir, 'rms_envelope.png');
    save_plot(spec_fig, opts.OutputDir, 'spectrum.png');
end
pcm_all = pcm_all(:, 1:pcm_count);
result = struct('datagrams', {datagrams}, 'pcm', pcm_all, ...
    'short_time_rms', envelope, 'short_time_rms_time', envelope_t, ...
    'stats', stats, 'git_sha', git_sha(), 'received_at', datetime('now'));
if strlength(string(opts.SaveFile)) > 0
    % Keep the evidence readable by scipy.io.loadmat as well as MATLAB.
    save(opts.SaveFile, '-struct', 'result');
end
fprintf('MIC_MATLAB_LIVE_CAPTURE received=%d heartbeat=%d pcm=%d missing=%d duplicates=%d malformed=%d crc=%d ready=%d\n', ...
    stats.received, stats.heartbeats, stats.pcm_packets, stats.missing, ...
    stats.duplicates, stats.malformed, stats.crc_errors, stats.ready);
if ~isempty(fatal_error)
    rethrow(fatal_error);
end
end

function recent = ordered_ring(ring, pos, count, capacity, channels)
if count == 0
    recent = zeros(0, channels);
elseif count < capacity
    recent = ring(1:count, :);
else
    first = mod(pos, capacity) + 1;
    recent = [ring(first:end, :); ring(1:first - 1, :)];
end
end

function write_marker(path, text)
if strlength(string(path)) == 0, return; end
parent = fileparts(char(path));
if ~isempty(parent) && ~isfolder(parent), mkdir(parent); end
fid = fopen(char(path), 'w');
if fid >= 0, fwrite(fid, text, 'char'); fclose(fid); end
end

function save_plot(fig, out_dir, name)
if isempty(fig) || strlength(string(out_dir)) == 0, return; end
if ~isfolder(out_dir), mkdir(out_dir); end
try
    exportgraphics(fig, fullfile(out_dir, name), 'Resolution', 150);
catch
    saveas(fig, fullfile(out_dir, name));
end
end

function sha = git_sha()
[~, text] = system('git rev-parse HEAD'); sha = strtrim(text);
end
