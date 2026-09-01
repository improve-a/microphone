function value = crc32_bytes(bytes)
%CRC32_BYTES IEEE CRC-32 over a uint8 vector.
bytes = uint8(bytes(:));
crc = uint32(hex2dec('FFFFFFFF'));
poly = uint32(hex2dec('EDB88320'));
for n = 1:numel(bytes)
    crc = bitxor(crc, uint32(bytes(n)));
    for bit = 1:8
        if bitand(crc, uint32(1))
            crc = bitxor(bitshift(crc, -1), poly);
        else
            crc = bitshift(crc, -1);
        end
    end
end
value = bitcmp(crc);
end

