%-------------------------------------------------------------------------%
% Extract femur path points and wrap origins from an OpenSim model and    %
% combine them with femur landmark files for use in NMSBuilder.           %
%                                                                         %
% The script keeps the original muscle names from the OpenSim model and   %
% writes one combined output file for the right femur and one for the     %
% left femur. Each output file contains:                                  %
% - 24 femur landmarks                                                    %
% - muscle path points attached to femur_r / femur_l                      %
% - origin points of femur wrap cylinders (O_*)                           %
%                                                                         %
%    Author:   Elias Wagner                                               %
%    email:    wagnerel85475@th-nuernberg.de                              %
%-------------------------------------------------------------------------%

clear; clc;
import org.opensim.modeling.*

%% User inputs
scriptFolder = fileparts(mfilename('fullpath'));
materialFolder = fileparts(scriptFolder);

osimFile = fullfile(materialFolder, 'OpenSim', 'LaiUhlrich2022.osim');
outputFolder = fullfile(materialFolder, 'NMSBuilder');

% Export these landmark-only files from NMSBuilder, or adjust the names here
% if your downloaded repository uses a different landmark file name.
landmarkFileR = fullfile(outputFolder, 'NMSBuilderRajagopal_femur_r_landmarks.txt');
landmarkFileL = fullfile(outputFolder, 'NMSBuilderRajagopal_femur_l_landmarks.txt');

outputFileR = fullfile(outputFolder, ...
    'NMSBuilderRajagopal_LaiUhlrich2022_femur_r_landmarks_and_muscle_path_points.txt');
outputFileL = fullfile(outputFolder, ...
    'NMSBuilderRajagopal_LaiUhlrich2022_femur_l_landmarks_and_muscle_path_points.txt');

if ~isfolder(outputFolder); mkdir(outputFolder); end

%% Load landmarks
landmarksR = loadLandmarkLines(landmarkFileR);
landmarksL = loadLandmarkLines(landmarkFileL);

%% Load OpenSim model
model = Model(osimFile);
model.initSystem();

%% Extract femur path points and wrap origins
femurRowsR = extractFemurRows(model, 'r');
femurRowsL = extractFemurRows(model, 'l');

wrapRowsR = extractWrapOriginRows(model, 'femur_r');
wrapRowsL = extractWrapOriginRows(model, 'femur_l');

%% Write outputs
writeLines(outputFileR, [landmarksR; femurRowsR; wrapRowsR]);
writeLines(outputFileL, [landmarksL; femurRowsL; wrapRowsL]);

fprintf('Wrote %s\n', outputFileR);
fprintf('Wrote %s\n', outputFileL);
fprintf('Right side rows: %d\n', numel(landmarksR) + numel(femurRowsR) + numel(wrapRowsR));
fprintf('Left side rows: %d\n', numel(landmarksL) + numel(femurRowsL) + numel(wrapRowsL));

%% Local functions
function lines = loadLandmarkLines(primaryFile)
if ~exist(primaryFile, 'file')
    error('Could not find landmark source:\n%s', primaryFile);
end
lines = readlines(primaryFile);
lines = lines(strlength(strtrim(lines)) > 0);
lines = cellstr(lines);
end

function rows = extractFemurRows(model, side)
import org.opensim.modeling.*

targetFrameName = ['femur_' side];
targetFramePath = ['/bodyset/' targetFrameName];
rows = {};

forceSet = model.getForceSet();
for iForce = 0:forceSet.getSize()-1
    muscle = Millard2012EquilibriumMuscle.safeDownCast(forceSet.get(iForce));
    if isempty(muscle)
        continue;
    end
    
    pathPointSet = muscle.getGeometryPath().getPathPointSet();
    nPoints = pathPointSet.getSize();
    
    for iPoint = 0:nPoints-1
        pathPoint = PathPoint.safeDownCast(pathPointSet.get(iPoint));
        if isempty(pathPoint) || ~isPathPointOnFrame(pathPoint, targetFrameName, targetFramePath)
            continue;
        end
        
        pointName = char(pathPoint.getName());
        label = convertOriginalLabel(pointName, nPoints);
        coords = vec3ToArray(pathPoint.get_location());
        
        rows{end+1,1} = sprintf('%s,\t%s,\t%s,\t%s', label, ...
            formatNum(coords(1)), formatNum(coords(2)), formatNum(coords(3))); %#ok<AGROW>
    end
end
end

function rows = extractWrapOriginRows(model, bodyName)
import org.opensim.modeling.*

rows = {};
body = model.getBodySet().get(bodyName);
wrapObjectSet = body.getWrapObjectSet();

for iWrap = 0:wrapObjectSet.getSize()-1
    wrapCylinder = WrapCylinder.safeDownCast(wrapObjectSet.get(iWrap));
    if ~isempty(wrapCylinder)
        wrapName = char(wrapCylinder.getName());
        coords = vec3ToArray(wrapCylinder.get_translation());
        rows{end+1,1} = sprintf('O_%s,\t%s,\t%s,\t%s', wrapName, ...
            formatNum(coords(1)), formatNum(coords(2)), formatNum(coords(3))); %#ok<AGROW>
    end
end
end

function label = convertOriginalLabel(pointName, nPoints)
tokens = regexp(pointName, '^(.+_[rl])-P([0-9]+)(?:_0)?$', 'tokens', 'once');
if isempty(tokens)
    label = strrep(pointName, '-', ' ');
    return;
end

baseName = tokens{1};
pointIndex = str2double(tokens{2});

if pointIndex == 1
    role = 'orig';
elseif pointIndex == nPoints
    role = 'ins';
else
    role = sprintf('via %d', pointIndex - 1);
end

label = sprintf('%s %s', baseName, role);
end

function tf = isPathPointOnFrame(pathPoint, targetFrameName, targetFramePath)
parentFrame = pathPoint.getParentFrame();
parentFrameName = char(parentFrame.getName());
parentFramePath = char(parentFrame.getAbsolutePathString());
tf = strcmp(parentFrameName, targetFrameName) || strcmp(parentFramePath, targetFramePath);
end

function arr = vec3ToArray(vec3)
arr = [vec3.get(0), vec3.get(1), vec3.get(2)];
end

function txt = formatNum(val)
if abs(val) < 1e-12
    val = 0;
end
txt = regexprep(sprintf('%.12g', val), '(\.\d*?)0+$', '$1');
txt = regexprep(txt, '\.$', '');
end

function writeLines(filePath, lines)
fid = fopen(filePath, 'w');
if fid == -1
    error('Could not open output file:\n%s', filePath);
end
cleanup = onCleanup(@() fclose(fid));
for iLine = 1:numel(lines)
    fprintf(fid, '%s\n', lines{iLine});
end
end
