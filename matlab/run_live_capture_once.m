function run_live_capture_once(saveFile, seconds, plotEnabled)
%RUN_LIVE_CAPTURE_ONCE Batch entry point used by physical evidence runs.
if nargin < 1 || strlength(string(saveFile)) == 0
    saveFile = 'evidence/physical/matlab_live_capture.mat';
end
if nargin < 2, seconds = 45; end
if nargin < 3, plotEnabled = false; end
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, 'matlab'));
live_mic_receiver('LocalPort', 45123, 'Seconds', seconds, ...
    'Channels', 8, 'FrameSamples', 128, 'SaveFile', saveFile, ...
    'Plot', logical(plotEnabled));
end
