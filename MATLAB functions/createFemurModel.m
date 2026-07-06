%-------------------------------------------------------------------------%
% Copyright (c) 2020 Modenese L.                                          %
%    Original Author: Luca Modenese, 2020                                 %
%    email:           l.modenese@imperial.ac.uk                           %
%    Modified from Modenese et al. for femur-only STAPLE model generation %
% ----------------------------------------------------------------------- %
% This script creates femur-only kinetic models from bone geometries using
% the STAPLE workflow and joint definitions from Modenese et al. J.Biomech.
% (2018), based on the model generation workflow described in:
% Modenese, Luca, and Jean-Baptiste Renault. "Automatic Generation of
% Personalised Skeletal Models of the Lower Limb from Three-Dimensional
% Bone Geometries." bioRxiv (2020).
% https://www.biorxiv.org/content/10.1101/2020.06.23.162727v2
% ----------------------------------------------------------------------- %
clear; clc; close all
addpath(genpath('STAPLE'));

%----------%
% SETTINGS %
%----------%
output_models_folder = 'opensim_models_JBiomech';
datasets_folder = 'bone_datasets';
dataset_set = {'VISIBLE_H'};
subj_mass_set = 90; % kg
side_set = {'r', 'l'};
vis_geom_format = 'stl'; % options: 'stl'/'obj'
output_fitted_geometry_folder = fullfile(output_models_folder, 'fitted_geometries');

generic_osim_model_file = 'C:\Users\wagnerel85475\Documents\opencap-core\opensimPipeline\Models\LaiUhlrich2022_shoulder.osim';
scaled_osim_model_file = 'C:\Users\wagnerel85475\Documents\opencap-core\opensimPipeline\Models\LaiUhlrich2022_shoulder_scaled.osim';
scale_setup_file = fullfile(output_models_folder, 'scale_LaiUhlrich2022_femurs.xml');
scale_factors_file = fullfile(output_models_folder, 'LaiUhlrich2022_femur_scale_factors.xml');

subject_geometry_to_model_scale = 0.001; % STAPLE mm to OpenSim m
joint_defs = 'Modenese2018';
%--------------------------------------%

%-------%
% SETUP %
%-------%
if ~isfolder(output_models_folder); mkdir(output_models_folder); end
if ~isfolder(output_fitted_geometry_folder); mkdir(output_fitted_geometry_folder); end

%------------------%
% MODEL GENERATION %
%------------------%
for n_d = 1:numel(dataset_set)
    cur_dataset = dataset_set{n_d};
    tri_folder = fullfile(datasets_folder, cur_dataset, 'tri');
    log_file = fullfile(output_models_folder, ['automatic_', cur_dataset, '.log']);

    logConsolePrintout('on', log_file);
    femur_scale_factors = struct;

    for n_s = 1:numel(side_set)
        side = side_set{n_s};
        cur_bones_list = {['femur_', side]};
        cur_model_name = ['automatic_', cur_dataset, '_', upper(side)];
        model_file_name = [cur_model_name, '.osim'];
        geometry_folder_name = [cur_model_name, '_Geometries'];
        geometry_folder_path = fullfile(output_models_folder, geometry_folder_name);

        triGeom_set = createTriGeomSet(cur_bones_list, tri_folder);
        writeModelGeometriesFolder(triGeom_set, geometry_folder_path, vis_geom_format, 0.3);

        osimModel = initializeOpenSimModel(cur_model_name);
        osimModel = addBodiesFromTriGeomBoneSet(osimModel, triGeom_set, ...
            geometry_folder_name, vis_geom_format);

        [JCS, BL, CS] = processTriGeomBoneSet(triGeom_set, side);
        saveFemurCoordinateSystems(JCS, BL, CS, cur_dataset, side, ...
            output_fitted_geometry_folder);

        femur_scale_factors.(side) = exportFemurJointCentresAndScaleFactor( ...
            JCS, cur_dataset, side, output_fitted_geometry_folder, ...
            subject_geometry_to_model_scale, generic_osim_model_file);

        createOpenSimModelJoints(osimModel, JCS, joint_defs);
        osimModel = assignMassPropsToSegments(osimModel, JCS, subj_mass_set(n_d));
        addBoneLandmarksAsMarkers(osimModel, BL);

        osimModel.finalizeConnections();
        osimModel.print(fullfile(output_models_folder, model_file_name));

        disp('-------------------------')
        disp(['Model generated in ', sprintf('%.1f', toc), ' s']);
        disp(['Saved as ', fullfile(output_models_folder, model_file_name), '.']);
        disp(['Model geometries saved in folder: ', geometry_folder_path, '.'])
        disp('-------------------------')
        close all
    end

    scaleGenericModelFemurs(generic_osim_model_file, scaled_osim_model_file, ...
        scale_setup_file, scale_factors_file, femur_scale_factors, subj_mass_set(n_d));
    logConsolePrintout('off');
end

rmpath(genpath('STAPLE'));

%------------------%
% HELPER FUNCTIONS %
%------------------%
function uniform_scale_factor = exportFemurJointCentresAndScaleFactor(JCS, dataset_name, side, ...
    output_folder, subject_geometry_to_model_scale, generic_osim_model_file)
%EXPORTFEMURJOINTCENTRESANDSCALEFACTOR Export HJC/KJC and uniform scale.
import org.opensim.modeling.*

femur_name = ['femur_', side];
hip_name = ['hip_', side];
knee_name = ['knee_', side];
generic_hip_joint_name = ['hip_', side];
generic_knee_joint_name = ['walker_knee_', side];
dataset_output_folder = fullfile(output_folder, dataset_name);
if ~isfolder(dataset_output_folder); mkdir(dataset_output_folder); end

femur_jcs = JCS.(femur_name);
subject_hip_joint_centre_mm = femur_jcs.(hip_name).Origin(:);
subject_knee_joint_centre_mm = femur_jcs.(knee_name).Origin(:);
subject_distance_mm = norm(subject_hip_joint_centre_mm - subject_knee_joint_centre_mm);
subject_distance_m = subject_distance_mm * subject_geometry_to_model_scale;

generic_model = Model(generic_osim_model_file);
joint_set = generic_model.getJointSet();
generic_hip_joint_centre_m = osimVec3ToColumn( ...
    joint_set.get(generic_hip_joint_name).get_frames(1).get_translation());
generic_knee_joint_centre_m = osimVec3ToColumn( ...
    joint_set.get(generic_knee_joint_name).get_frames(0).get_translation());
generic_distance_m = norm(generic_hip_joint_centre_m - generic_knee_joint_centre_m);
uniform_scale_factor = subject_distance_m / generic_distance_m;

joint_centres_path = fullfile(dataset_output_folder, ['Joint_centres_', side, '.txt']);
fid = fopen(joint_centres_path, 'w+');
fprintf(fid, 'Subject_Hip_Joint_Centre_mm, %6.4f, %6.4f, %6.4f\n', subject_hip_joint_centre_mm);
fprintf(fid, 'Subject_Knee_Joint_Centre_mm, %6.4f, %6.4f, %6.4f\n', subject_knee_joint_centre_mm);
fprintf(fid, 'Generic_Hip_Joint_Centre_femur_frame_m, %6.6f, %6.6f, %6.6f\n', generic_hip_joint_centre_m);
fprintf(fid, 'Generic_Knee_Joint_Centre_femur_frame_m, %6.6f, %6.6f, %6.6f\n', generic_knee_joint_centre_m);
fclose(fid);

scale_path = fullfile(dataset_output_folder, ['Femur_uniform_scaling_factor_', side, '.txt']);
fid = fopen(scale_path, 'w+');
fprintf(fid, 'Generic_model_file, %s\n', generic_osim_model_file);
fprintf(fid, 'Generic_hip_joint_name, %s\n', generic_hip_joint_name);
fprintf(fid, 'Generic_knee_joint_name, %s\n', generic_knee_joint_name);
fprintf(fid, 'Generic_Hip_Joint_Centre_femur_frame_m, %6.6f, %6.6f, %6.6f\n', ...
    generic_hip_joint_centre_m);
fprintf(fid, 'Generic_Knee_Joint_Centre_femur_frame_m, %6.6f, %6.6f, %6.6f\n', ...
    generic_knee_joint_centre_m);
fprintf(fid, 'Generic_Hip_to_knee_distance_m, %6.6f\n', generic_distance_m);
fprintf(fid, 'Subject_Hip_to_knee_distance_mm, %6.4f\n', subject_distance_mm);
fprintf(fid, 'Subject_Hip_to_knee_distance_m, %6.6f\n', subject_distance_m);
fprintf(fid, 'Femur_uniform_scale_factor, %6.6f\n', uniform_scale_factor);
fclose(fid);
end

function saveFemurCoordinateSystems(JCS, BL, CS, dataset_name, side, output_folder)
%SAVEFEMURCOORDINATESYSTEMS Save full STAPLE femur JCS/CS/BL structures.
dataset_output_folder = fullfile(output_folder, dataset_name);
if ~isfolder(dataset_output_folder); mkdir(dataset_output_folder); end

coordinate_systems_path = fullfile(dataset_output_folder, ...
    ['STAPLE_femur_coordinate_systems_', side, '.mat']);
save(coordinate_systems_path, 'JCS', 'BL', 'CS', 'dataset_name', 'side');
end

function scaleGenericModelFemurs(generic_osim_model_file, scaled_osim_model_file, ...
    scale_setup_file, scale_factors_file, femur_scale_factors, subject_mass)
%SCALEGENERICMODELFEMURS Apply right/left femur manual scales with ScaleTool.
import org.opensim.modeling.*

scale_tool = ScaleTool();
scale_tool.setName('scale_LaiUhlrich2022_femurs');
scale_tool.setSubjectMass(subject_mass);
scale_tool.getGenericModelMaker().setModelFileName(generic_osim_model_file);
scale_tool.getMarkerPlacer().setApply(false);

model_scaler = scale_tool.getModelScaler();
model_scaler.setApply(true);
model_scaler.setPreserveMassDist(true);
model_scaler.setOutputModelFileName(scaled_osim_model_file);
model_scaler.setOutputScaleFileName(scale_factors_file);

scaling_order = ArrayStr();
scaling_order.append('manualScale');
model_scaler.setScalingOrder(scaling_order);

right_scale = Scale();
right_scale.setSegmentName('femur_r');
right_scale.setScaleFactors(Vec3(femur_scale_factors.r, femur_scale_factors.r, femur_scale_factors.r));
model_scaler.addScale(right_scale);

left_scale = Scale();
left_scale.setSegmentName('femur_l');
left_scale.setScaleFactors(Vec3(femur_scale_factors.l, femur_scale_factors.l, femur_scale_factors.l));
model_scaler.addScale(left_scale);

scale_tool.print(scale_setup_file);
scale_tool.run();
end

function vector = osimVec3ToColumn(vec3)
%OSIMVEC3TOCOLUMN Convert an OpenSim Vec3 to a MATLAB column vector.
vector = [vec3.get(0); vec3.get(1); vec3.get(2)];
end
