function [header, pcm] = parse_mic_udp_packet(datagram)
%PARSE_MIC_UDP_PACKET Parse one protocol-v1 microphone UDP datagram.
datagram = uint8(datagram(:));
if numel(datagram) < 32, error('MIC:Protocol', 'truncated header'); end
if ~isequal(char(datagram(1:4).'), 'MIC0'), error('MIC:Protocol', 'bad magic'); end
if datagram(5) ~= 1 || datagram(6) ~= 32, error('MIC:Protocol', 'bad version'); end
if datagram(7) ~= 1, error('MIC:Protocol', 'bad sample format'); end
header.flags = datagram(8);
header.packet_sequence = read_u32(datagram, 9);
header.frame_index = read_u32(datagram, 13);
header.sample_start = read_u32(datagram, 17);
header.channel_count = read_u16(datagram, 21);
header.samples_per_channel = read_u16(datagram, 23);
header.payload_length = read_u16(datagram, 25);
reserved = read_u16(datagram, 27);
header_crc = read_u32(datagram, 29);
if reserved ~= 0, error('MIC:Protocol', 'reserved field nonzero'); end
expected = double(header.channel_count) * double(header.samples_per_channel) * 2;
if double(header.payload_length) ~= expected, error('MIC:Protocol', 'bad payload dimensions'); end
if numel(datagram) ~= 32 + expected, error('MIC:Protocol', 'bad datagram length'); end
if numel(datagram) > 1472, error('MIC:Protocol', 'MTU exceeded'); end
if crc32_bytes(datagram(1:28)) ~= header_crc, error('MIC:Protocol', 'CRC mismatch'); end
payload = datagram(33:end);
values = typecast(payload, 'int16');
[~, ~, endian] = computer;
if endian == 'B', values = swapbytes(values); end
pcm = reshape(values, double(header.channel_count), double(header.samples_per_channel));
end

function value = read_u16(bytes, offset)
value = typecast(bytes(offset:offset+1), 'uint16');
[~, ~, endian] = computer;
if endian == 'B', value = swapbytes(value); end
end

function value = read_u32(bytes, offset)
value = typecast(bytes(offset:offset+3), 'uint32');
[~, ~, endian] = computer;
if endian == 'B', value = swapbytes(value); end
end
