function datagrams = read_mic_packet_file(path)
%READ_MIC_PACKET_FILE Read little-endian length-prefixed UDP datagrams.
fid = fopen(path, 'rb');
if fid < 0, error('MIC:File', 'cannot open packet file'); end
cleanup = onCleanup(@() fclose(fid));
datagrams = {};
while true
    lengthValue = fread(fid, 1, 'uint32=>uint32', 0, 'ieee-le');
    if isempty(lengthValue), break; end
    if lengthValue == 0, error('MIC:File', 'zero record length'); end
    data = fread(fid, double(lengthValue), 'uint8=>uint8');
    if numel(data) ~= double(lengthValue), error('MIC:File', 'truncated record'); end
    datagrams{end+1} = data; %#ok<AGROW>
end
end

