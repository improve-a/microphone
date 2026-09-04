function run_live_capture_once(saveFile, seconds, plotEnabled, readyFile, minReadyPcmPackets, stopFile)
%RUN_LIVE_CAPTURE_ONCE Batch entry point used by physical evidence runs.
if nargin < 1 || strlength(string(saveFile)) == 0
    saveFile = 'evidence/physical/matlab_live_capture.mat';
end
if nargin < 2, seconds = 65; end
if nargin < 3, plotEnabled = false; end
if nargin < 4, readyFile = ''; end
if nargin < 5, minReadyPcmPackets = 20; end
if nargin < 6, stopFile = ''; end
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, 'matlab'));
outputDir = fileparts(char(saveFile));
live_mic_receiver('LocalPort', 45123, 'Seconds', seconds, ...
    'Channels', 8, 'FrameSamples', 128, 'SaveFile', saveFile, ...
    'OutputDir', outputDir, 'ReadyFile', readyFile, ...
    'Plot', logical(plotEnabled), ...
    'MinReadyPcmPackets', minReadyPcmPackets, 'StopFile', stopFile);
end
