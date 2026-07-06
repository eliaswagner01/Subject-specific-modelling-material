%-------------------------------------------------------------------------%
% Copyright (c) 2026 Wagner E.                                            %
%    Author:   Wagner E.,  2026                                           %
% ----------------------------------------------------------------------- %
% This script updates a scaled LaiUhlrich2022 OpenSim model using snapped
% femur landmarks, STAPLE femur joint coordinate systems, and coarsened
% femur surface meshes created by CreateFemurModel.m.
%
% Snapped NMSBuilder landmarks are converted from mm to m before replacing
% femur muscle path points and femur wrapping object origins. Femur-side
% hip and knee joint frames are replaced with STAPLE JCS data. Femur wrap
% rotations are transformed from the femur geometry frame into the femur
% body frame using femur_*_offset, and the original patellofemoral frame
% offset from walker_knee is preserved. Femur marker locations are length-
% scaled and transformed with femur_*_offset. Femur mass centers and inertia
% tensors are also transformed with femur_*_offset, with inertia rotated
% about the mass center.
% ----------------------------------------------------------------------- %
clear; clc; close all
import org.opensim.modeling.*

%----------%
% SETTINGS %
%----------%
script_folder = fileparts(mfilename('fullpath'));
material_folder = fileparts(script_folder);
mm_to_m = 0.001;
side_set = {'r', 'l'};

%-------------%
% INPUT FILES %
%-------------%
snapped_landmark_folder = fullfile(material_folder, 'NMSBuilder');
scaled_osim_model_file = fullfile(material_folder, 'OpenSim', 'LaiUhlrich2022_scaled.osim');
updated_osim_model_file = fullfile(material_folder, 'OpenSim', 'LaiUhlrich2022_adjusted.osim');
generic_marker_set_file = fullfile(material_folder, 'OpenSim', 'LaiUhlrich2022_markers_augmenter.xml');
updated_marker_set_file = fullfile(material_folder, 'OpenSim', 'LaiUhlrich2022_markers_augmenter_adjusted.xml');

snapped_landmark_files.r = fullfile(snapped_landmark_folder, 'Muscles_femur_r_snapped.txt');
snapped_landmark_files.l = fullfile(snapped_landmark_folder, 'Muscles_femur_l_snapped.txt');

femur_geometry_files.r = firstExistingPath({ ...
    fullfile(material_folder, 'opensim_models_JBiomech', 'automatic_VISIBLE_H_R_Geometries', 'femur_r.obj'), ...
    fullfile(material_folder, 'opensim_models_JBiomech', 'automatic_VISIBLE_H_R_Geometries', 'femur_r.stl')});
femur_geometry_files.l = firstExistingPath({ ...
    fullfile(material_folder, 'opensim_models_JBiomech', 'automatic_VISIBLE_H_L_Geometries', 'femur_l.obj'), ...
    fullfile(material_folder, 'opensim_models_JBiomech', 'automatic_VISIBLE_H_L_Geometries', 'femur_l.stl')});

staple_jcs_files.r = fullfile(material_folder, 'opensim_models_JBiomech', ...
    'fitted_geometries', 'VISIBLE_H', 'STAPLE_femur_coordinate_systems_r.mat');
staple_jcs_files.l = fullfile(material_folder, 'opensim_models_JBiomech', ...
    'fitted_geometries', 'VISIBLE_H', 'STAPLE_femur_coordinate_systems_l.mat');

femur_scale_factor_files.r = fullfile(material_folder, 'opensim_models_JBiomech', ...
    'fitted_geometries', 'VISIBLE_H', 'Femur_uniform_scaling_factor_r.txt');
femur_scale_factor_files.l = fullfile(material_folder, 'opensim_models_JBiomech', ...
    'fitted_geometries', 'VISIBLE_H', 'Femur_uniform_scaling_factor_l.txt');

reference_model = Model(scaled_osim_model_file);
osim_model = Model(scaled_osim_model_file);
femur_scale_factors = readFemurScaleFactors(femur_scale_factor_files, side_set);

%--------------%
% MODEL UPDATE %
%--------------%
for n_side = 1:numel(side_set)
    side = side_set{n_side};
    landmarks = readSnappedLandmarkFile(snapped_landmark_files.(side), mm_to_m);

    [path_updates, wrap_updates] = updateFemurMuscleGeometry(osim_model, landmarks, side);
    updateFemurMesh(osim_model, femur_geometry_files.(side), side, mm_to_m);
    updateFemurJointFrames(osim_model, staple_jcs_files.(side), side);
    updateFemurInertialProperties(osim_model, side);
    wrap_rotation_updates = updateFemurWrapObjectOrientations(osim_model, landmarks, side);
    updatePatellofemoralFrameFromWalkerKnee(osim_model, reference_model, side);

    disp(['Updated ', num2str(path_updates), ' femur path points for side ', upper(side), '.'])
    disp(['Updated ', num2str(wrap_updates), ' femur wrapping object origins for side ', upper(side), '.'])
    disp(['Updated ', num2str(wrap_rotation_updates), ' femur wrapping object orientations for side ', upper(side), '.'])
    disp(['Updated coarsened femur mesh for side ', upper(side), '.'])
    disp(['Updated femur-side hip and knee joint frames for side ', upper(side), '.'])
    disp(['Updated femur mass center and inertia for side ', upper(side), '.'])
    disp(['Updated femur-side patellofemoral frame for side ', upper(side), '.'])
end

marker_updates = transformFemurMarkersForAdjustedModel( ...
    osim_model, generic_marker_set_file, updated_marker_set_file, femur_scale_factors, side_set);
disp(['Updated ', num2str(marker_updates), ' femur marker locations in: ', updated_marker_set_file])

osim_model.finalizeConnections();
osim_model.print(updated_osim_model_file);
disp(['Updated model written to: ', updated_osim_model_file])

%------------------%
% HELPER FUNCTIONS %
%------------------%
function path = firstExistingPath(candidates)
%FIRSTEXISTINGPATH Return the first existing candidate, or the first default.
path = candidates{1};
for n_candidate = 1:numel(candidates)
    if isfile(candidates{n_candidate})
        path = candidates{n_candidate};
        return
    end
end
end

function landmarks = readSnappedLandmarkFile(landmark_file, unit_scale)
%READSNAPPEDLANDMARKFILE Read snapped NMSBuilder landmarks and scale to m.
fid = fopen(landmark_file, 'r');
if fid < 0
    error('modifyOsimModel:cannotOpenLandmarkFile', ...
        'Could not open landmark file: %s', landmark_file);
end

cleaner = onCleanup(@() fclose(fid));
landmarks.path_points = struct;
landmarks.wrap_objects = struct;

while true
    line = fgetl(fid);
    if ~ischar(line); break; end

    line = strtrim(line);
    if isempty(line); continue; end

    tokens = strsplit(line, ',');
    if numel(tokens) < 4
        warning('modifyOsimModel:badLandmarkLine', ...
            'Skipping malformed landmark line: %s', line);
        continue
    end

    label = strtrim(tokens{1});
    coords = str2double(tokens(2:4)) .* unit_scale;
    if any(isnan(coords))
        warning('modifyOsimModel:badLandmarkCoordinates', ...
            'Skipping landmark with invalid coordinates: %s', label);
        continue
    end

    if startsWith(label, 'O_')
        wrap_name = extractAfter(label, 'O_');
        landmarks.wrap_objects.(matlab.lang.makeValidName(wrap_name)) = coords;
        continue
    end

    label_parts = strsplit(label);
    muscle_key = matlab.lang.makeValidName(label_parts{1});
    entry = struct('label', label, 'coords', coords);

    if isfield(landmarks.path_points, muscle_key)
        landmarks.path_points.(muscle_key)(end + 1) = entry;
    else
        landmarks.path_points.(muscle_key) = entry;
    end
end
end

function femur_scale_factors = readFemurScaleFactors(scale_factor_files, side_set)
%READFEMURSCALEFACTORS Read femur length scaling factors exported earlier.
femur_scale_factors = struct;
for n_side = 1:numel(side_set)
    side = side_set{n_side};
    scale_factor_file = scale_factor_files.(side);
    if ~isfile(scale_factor_file)
        error('modifyOsimModel:missingFemurScaleFactor', ...
            'Could not find femur scale factor file: %s', scale_factor_file);
    end

    file_text = fileread(scale_factor_file);
    match = regexp(file_text, 'Femur_uniform_scale_factor,\s*([0-9eE+\-.]+)', ...
        'tokens', 'once');
    if isempty(match)
        error('modifyOsimModel:badFemurScaleFactorFile', ...
            'Could not read Femur_uniform_scale_factor from: %s', scale_factor_file);
    end
    femur_scale_factors.(side) = str2double(match{1});
end
end

function updateFemurMesh(osim_model, mesh_file, side, mesh_scale)
%UPDATEFEMURMESH Replace femur visualization mesh and scale OBJ mm to m.
import org.opensim.modeling.*

if ~isfile(mesh_file)
    error('modifyOsimModel:missingFemurMesh', ...
        'Could not find femur mesh file: %s', mesh_file);
end

femur_name = ['femur_', side];
femur_mesh = Mesh.safeDownCast(osim_model.upd_BodySet().get(femur_name).upd_attached_geometry(0));
if isempty(femur_mesh)
    error('modifyOsimModel:unsupportedFemurMesh', ...
        'The first attached geometry on %s is not an OpenSim Mesh.', femur_name);
end

femur_mesh.setName([femur_name, '_geom_1']);
femur_mesh.set_mesh_file(mesh_file);
femur_mesh.set_scale_factors(Vec3(mesh_scale, mesh_scale, mesh_scale));
end

function updateFemurJointFrames(osim_model, coordinate_systems_file, side)
%UPDATEFEMURJOINTFRAMES Replace femur-side hip/knee frames with STAPLE JCS.
if ~isfile(coordinate_systems_file)
    error('modifyOsimModel:missingStapleJCS', ...
        ['Could not find STAPLE coordinate systems file: %s\n', ...
        'Run Create_Femur_kinetic_model.m first to generate it.'], ...
        coordinate_systems_file);
end

saved_data = load(coordinate_systems_file, 'JCS');
femur_name = ['femur_', side];
hip_name = ['hip_', side];
staple_knee_name = ['knee_', side];
model_knee_name = ['walker_knee_', side];
femur_jcs = saved_data.JCS.(femur_name);

setFrameTransform(osim_model.updJointSet().get(hip_name).get_frames(1), ...
    femur_jcs.(hip_name).child_location, ...
    femur_jcs.(hip_name).child_orientation);

setFrameTransform(osim_model.updJointSet().get(model_knee_name).get_frames(0), ...
    femur_jcs.(staple_knee_name).parent_location, ...
    stapleOrientationAsLaiOrientation(femur_jcs.(staple_knee_name), side));
end

function orientation = stapleOrientationAsLaiOrientation(staple_frame, side)
%STAPLEORIENTATIONASLAIORIENTATION Convert STAPLE femur axes to LaiUhlrich axes.
staple_axes = staple_frame.V;
switch side
    case 'r'
        lai_axes = [-staple_axes(:, 3), staple_axes(:, 2), staple_axes(:, 1)];
    case 'l'
        lai_axes = [staple_axes(:, 3), staple_axes(:, 2), -staple_axes(:, 1)];
    otherwise
        error('modifyOsimModel:unsupportedSide', 'Unsupported side: %s', side);
end

orientation = computeXYZAngleSeqLocal(lai_axes);
orientation(1) = orientation(1) + 0.12;
end

function updateFemurInertialProperties(osim_model, side)
%UPDATEFEMURINERTIALPROPERTIES Express femur mass properties in body frame.
import org.opensim.modeling.*

femur_name = ['femur_', side];
hip_name = ['hip_', side];
femur_body = osim_model.upd_BodySet().get(femur_name);
femur_offset_frame = osim_model.getJointSet().get(hip_name).get_frames(1);
[offset_R, offset_p] = getFrameTransform(femur_offset_frame);

mass_center = getBodyMassCenter(femur_body);
inertia_matrix = inertiaToMatrix(femur_body.get_inertia());

updated_mass_center = offset_p + offset_R * mass_center;
updated_inertia_matrix = offset_R * inertia_matrix * offset_R';

femur_body.setMassCenter(Vec3( ...
    updated_mass_center(1), updated_mass_center(2), updated_mass_center(3)));
femur_body.setInertia(matrixToInertia(updated_inertia_matrix));
end

function wrap_rotation_updates = updateFemurWrapObjectOrientations(osim_model, landmarks, side)
%UPDATEFEMURWRAPOBJECTORIENTATIONS Express wrap rotations in femur body frame.
import org.opensim.modeling.*

wrap_rotation_updates = 0;
femur_name = ['femur_', side];
hip_name = ['hip_', side];
offset_frame = osim_model.getJointSet().get(hip_name).get_frames(1);
offset_R = xyzAnglesToRotationMatrix(vec3ToColumn(offset_frame.get_orientation()));

wrap_object_set = osim_model.upd_BodySet().get(femur_name).upd_WrapObjectSet();
wrap_names = fieldnames(landmarks.wrap_objects);
for n_wrap = 1:numel(wrap_names)
    wrap_name = wrap_names{n_wrap};
    if wrap_object_set.getIndex(wrap_name) < 0
        continue
    end

    wrap_object = WrapObject.safeDownCast(wrap_object_set.get(wrap_name));
    if isempty(wrap_object)
        continue
    end

    geometry_frame_orientation = vec3ToColumn(wrap_object.get_xyz_body_rotation());
    geometry_frame_R = xyzAnglesToRotationMatrix(geometry_frame_orientation);
    body_frame_R = offset_R * geometry_frame_R;
    body_frame_orientation = computeXYZAngleSeqLocal(body_frame_R);

    wrap_object.set_xyz_body_rotation(Vec3( ...
        body_frame_orientation(1), body_frame_orientation(2), body_frame_orientation(3)));
    wrap_rotation_updates = wrap_rotation_updates + 1;
end
end

function updatePatellofemoralFrameFromWalkerKnee(osim_model, reference_model, side)
%UPDATEPATELLOFEMORALFRAMEFROMWALKERKNEE Preserve original PF offset from knee.
walker_knee_name = ['walker_knee_', side];
patellofemoral_name = ['patellofemoral_', side];

[reference_knee_R, reference_knee_p] = getFrameTransform( ...
    reference_model.getJointSet().get(walker_knee_name).get_frames(0));
[reference_patella_R, reference_patella_p] = getFrameTransform( ...
    reference_model.getJointSet().get(patellofemoral_name).get_frames(0));
[updated_knee_R, updated_knee_p] = getFrameTransform( ...
    osim_model.getJointSet().get(walker_knee_name).get_frames(0));

relative_R = reference_knee_R' * reference_patella_R;
relative_p = reference_knee_R' * (reference_patella_p - reference_knee_p);
updated_patella_R = updated_knee_R * relative_R;
updated_patella_p = updated_knee_p + updated_knee_R * relative_p;

setFrameTransform(osim_model.updJointSet().get(patellofemoral_name).get_frames(0), ...
    updated_patella_p, computeXYZAngleSeqLocal(updated_patella_R));
end

function marker_updates = transformFemurMarkersForAdjustedModel( ...
    osim_model, marker_set_file, updated_marker_set_file, femur_scale_factors, side_set)
%TRANSFORMFEMURMARKERSFORADJUSTEDMODEL Move femur markers into adjusted frames.
% These marker locations were authored for the generic femur frame. The
% femurs were length-scaled along local Y, then moved into femur_offset, so
% apply the same Y scaling and femur_offset transform to femur markers.
if ~isfile(marker_set_file)
    error('modifyOsimModel:missingMarkerSet', ...
        'Could not find marker set file: %s', marker_set_file);
end

marker_doc = xmlread(marker_set_file);
femur_transforms = struct;
for n_side = 1:numel(side_set)
    side = side_set{n_side};
    hip_name = ['hip_', side];
    femur_offset_frame = osim_model.getJointSet().get(hip_name).get_frames(1);
    [femur_transforms.(side).R, femur_transforms.(side).p] = ...
        getFrameTransform(femur_offset_frame);
end

marker_updates = 0;
markers = marker_doc.getElementsByTagName('Marker');
for n_marker = 0:markers.getLength()-1
    marker = markers.item(n_marker);
    parent_node = marker.getElementsByTagName('socket_parent_frame').item(0);
    location_node = marker.getElementsByTagName('location').item(0);
    if isempty(parent_node) || isempty(location_node)
        continue
    end

    parent_frame = strtrim(char(parent_node.getTextContent()));
    if strcmp(parent_frame, '/bodyset/femur_r')
        side = 'r';
    elseif strcmp(parent_frame, '/bodyset/femur_l')
        side = 'l';
    else
        continue
    end

    old_location = sscanf(char(location_node.getTextContent()), '%f');
    scaled_location = old_location(:);
    scaled_location(2) = femur_scale_factors.(side) * scaled_location(2);
    new_location = femur_transforms.(side).R * scaled_location + ...
        femur_transforms.(side).p;
    location_node.setTextContent(sprintf('%.17g %.17g %.17g', new_location));
    marker_updates = marker_updates + 1;
end

xmlwrite(updated_marker_set_file, marker_doc);
end

function [path_updates, wrap_updates] = updateFemurMuscleGeometry(osim_model, landmarks, side)
%UPDATEFEMURMUSCLEGEOMETRY Update femur path points and wrap object origins.
import org.opensim.modeling.*

path_updates = 0;
wrap_updates = 0;
femur_name = ['femur_', side];
femur_frame_name = ['/bodyset/', femur_name];
muscles = osim_model.updMuscles();

for n_muscle = 0:muscles.getSize() - 1
    muscle = muscles.get(n_muscle);
    muscle_name = char(muscle.getName());
    muscle_key = matlab.lang.makeValidName(muscle_name);
    if ~isfield(landmarks.path_points, muscle_key); continue; end

    path_point_set = muscle.updGeometryPath().updPathPointSet();
    femur_point_indices = getPathPointIndicesOnFrame(path_point_set, femur_frame_name);
    if isempty(femur_point_indices); continue; end

    snapped_points = landmarks.path_points.(muscle_key);
    if numel(snapped_points) ~= numel(femur_point_indices)
        warning('modifyOsimModel:pathPointCountMismatch', ...
            ['%s has %d snapped femur points but %d femur path points in the model. ', ...
            'Updating the first %d in path order.'], ...
            muscle_name, numel(snapped_points), numel(femur_point_indices), ...
            min(numel(snapped_points), numel(femur_point_indices)));
    end

    for n_point = 1:min(numel(snapped_points), numel(femur_point_indices))
        path_point = PathPoint.safeDownCast(path_point_set.get(femur_point_indices(n_point)));
        if isempty(path_point)
            warning('modifyOsimModel:unsupportedPathPoint', ...
                'Skipping non-PathPoint object for muscle %s.', muscle_name);
            continue
        end

        coords = snapped_points(n_point).coords;
        path_point.set_location(Vec3(coords(1), coords(2), coords(3)));
        path_updates = path_updates + 1;
    end
end

wrap_object_set = osim_model.upd_BodySet().get(femur_name).upd_WrapObjectSet();
wrap_names = fieldnames(landmarks.wrap_objects);
for n_wrap = 1:numel(wrap_names)
    wrap_name = wrap_names{n_wrap};
    if wrap_object_set.getIndex(wrap_name) < 0
        warning('modifyOsimModel:missingWrapObject', ...
            'Could not find wrap object %s on %s.', wrap_name, femur_name);
        continue
    end

    wrap_object = WrapObject.safeDownCast(wrap_object_set.get(wrap_name));
    if isempty(wrap_object)
        warning('modifyOsimModel:unsupportedWrapObject', ...
            'Skipping unsupported wrap object %s on %s.', wrap_name, femur_name);
        continue
    end

    coords = landmarks.wrap_objects.(wrap_name);
    wrap_object.set_translation(Vec3(coords(1), coords(2), coords(3)));
    wrap_updates = wrap_updates + 1;
end
end

function setFrameTransform(frame, translation, orientation)
%SETFRAMETRANSFORM Set a PhysicalOffsetFrame transform from numeric vectors.
import org.opensim.modeling.*

translation = translation(:);
orientation = orientation(:);
frame.set_translation(Vec3(translation(1), translation(2), translation(3)));
frame.set_orientation(Vec3(orientation(1), orientation(2), orientation(3)));
end

function [rotation_matrix, translation] = getFrameTransform(frame)
%GETFRAMETRANSFORM Return rotation matrix and translation from OpenSim frame.
orientation = vec3ToColumn(frame.get_orientation());
translation = vec3ToColumn(frame.get_translation());
rotation_matrix = xyzAnglesToRotationMatrix(orientation);
end

function mass_center = getBodyMassCenter(body)
%GETBODYMASSCENTER Return mass center across OpenSim MATLAB API variants.
try
    mass_center = vec3ToColumn(body.getMassCenter());
catch
    mass_center = vec3ToColumn(body.get_mass_center());
end
end

function inertia_matrix = inertiaToMatrix(inertia)
%INERTIATOMATRIX Convert OpenSim Vec6 inertia to a symmetric 3x3 tensor.
inertia_values = zeros(6, 1);
for n_value = 1:6
    inertia_values(n_value) = inertia.get(n_value - 1);
end

inertia_matrix = [ ...
    inertia_values(1), inertia_values(4), inertia_values(5); ...
    inertia_values(4), inertia_values(2), inertia_values(6); ...
    inertia_values(5), inertia_values(6), inertia_values(3)];
end

function inertia = matrixToInertia(inertia_matrix)
%MATRIXTOINERTIA Convert a symmetric 3x3 tensor to OpenSim Inertia Vec6.
import org.opensim.modeling.*

inertia_matrix = 0.5 * (inertia_matrix + inertia_matrix');
inertia = Inertia( ...
    inertia_matrix(1, 1), inertia_matrix(2, 2), inertia_matrix(3, 3), ...
    inertia_matrix(1, 2), inertia_matrix(1, 3), inertia_matrix(2, 3));
end

function vector = vec3ToColumn(vec3)
%VEC3TOCOLUMN Convert an OpenSim Vec3 to a MATLAB column vector.
vector = [vec3.get(0); vec3.get(1); vec3.get(2)];
end

function orientation = computeXYZAngleSeqLocal(rotation_matrix)
%COMPUTEXYZANGLESEQLOCAL Convert a rotation matrix to OpenSim XYZ angles.
beta = atan2(rotation_matrix(1, 3), ...
    sqrt(rotation_matrix(1, 1)^2 + rotation_matrix(1, 2)^2));
alpha = atan2(-rotation_matrix(2, 3) / cos(beta), ...
    rotation_matrix(3, 3) / cos(beta));
gamma = atan2(-rotation_matrix(1, 2) / cos(beta), ...
    rotation_matrix(1, 1) / cos(beta));
orientation = [alpha, beta, gamma];
end

function rotation_matrix = xyzAnglesToRotationMatrix(orientation)
%XYZANGLESTOROTATIONMATRIX Convert OpenSim XYZ orientation to rotation matrix.
alpha = orientation(1);
beta = orientation(2);
gamma = orientation(3);

Rx = [1, 0, 0; ...
      0, cos(alpha), -sin(alpha); ...
      0, sin(alpha), cos(alpha)];
Ry = [cos(beta), 0, sin(beta); ...
      0, 1, 0; ...
      -sin(beta), 0, cos(beta)];
Rz = [cos(gamma), -sin(gamma), 0; ...
      sin(gamma), cos(gamma), 0; ...
      0, 0, 1];

rotation_matrix = Rx * Ry * Rz;
end

function indices = getPathPointIndicesOnFrame(path_point_set, frame_name)
%GETPATHPOINTINDICESONFRAME Return zero-based path point indices on frame.
indices = [];
for n_point = 0:path_point_set.getSize() - 1
    path_point = path_point_set.get(n_point);
    parent_frame = char(path_point.getPropertyByName('socket_parent_frame'));
    if strcmp(parent_frame, frame_name)
        indices(end + 1) = n_point; %#ok<AGROW>
    end
end
end
